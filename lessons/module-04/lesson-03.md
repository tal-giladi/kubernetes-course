# 13 - StatefulSets

*Module 04 - Configuration and state, lesson 3 of 3. Exercise 13 of 25.*

A Deployment's Pods are interchangeable: random names, random IPs, one shared claim if
any. That is exactly wrong for a database replica set, a Kafka broker, or anything where
"who am I" is part of the protocol. **StatefulSet** is the controller that gives Pods
identity.

## Three guarantees

**1. Stable names.** Pods are `db-0`, `db-1`, `db-2` - ordinal, not random. Delete `db-1`
and the replacement is called `db-1` again.

**2. Stable per-Pod storage.** `volumeClaimTemplates` creates one PVC *per Pod*, named
`<template>-<pod>`: `data-db-0`, `data-db-1`. The replacement `db-1` re-attaches
`data-db-1`, with its data. This is the field that makes StatefulSets worth the
complexity - and the reason a Deployment plus one RWO PVC (lesson 12) cannot do this.

**3. Ordered, controlled lifecycle.** Pods are created 0, 1, 2 - each waiting for the
previous to be Running and Ready - and deleted in reverse. Rolling updates go from the
highest ordinal down. `podManagementPolicy: Parallel` turns the ordering off when your
system does not need it (and many do not).

## The required headless Service

    spec:
      serviceName: db      # must name a headless Service

That Service must exist and be headless (`clusterIP: None`), because it is what creates
the per-Pod DNS records:

    db-0.db.lesson-13.svc.cluster.local
    db-1.db.lesson-13.svc.cluster.local

That name is the point. A replica can be told "your primary is `db-0.db`" and that stays
true across restarts, reschedules and node failures - which no Pod IP ever does.

You usually want **two** Services: the headless one for identity, and an ordinary
ClusterIP one for clients that just want "any replica".

## What StatefulSets do not do

They are a scheduling and naming primitive, not a database. Kubernetes will not elect your
primary, replicate your data, or reshard anything. `db-0` is not "the leader" - it is
simply the first Pod. Everything about clustering lives in your init scripts, your
application, or an **operator** (lesson 24) that encodes the real operational knowledge.

Other sharp edges:

  - **Scaling down does not delete the PVCs.** Deliberate: the data outlives the Pod, and
    scaling back up re-attaches it. It also means orphaned disks quietly cost money.
    `persistentVolumeClaimRetentionPolicy` (`whenScaled` / `whenDeleted`) lets you opt into
    cleanup.
  - **`volumeClaimTemplates` is immutable.** You cannot add a volume, or resize through
    the template, after creation. Resizing means patching each PVC individually.
  - **A stuck Pod blocks the rollout.** With `OrderedReady`, if `db-1` never becomes
    Ready, `db-2` is never touched. Safe, and occasionally maddening. `partition` in the
    update strategy is the escape hatch, and doubles as a canary: set
    `updateStrategy.rollingUpdate.partition: 2` and only ordinals >= 2 update.
  - **Deleting the StatefulSet does not delete the PVCs** either. That has saved more data
    than it has wasted.

## Do this

In namespace `lesson-13`, with `hello:1.1.0`:

1. A **headless** Service `db`: `clusterIP: None`, selector `app=db`, port 8080 named
   `http`.
2. A **StatefulSet** `db`: 3 replicas, `serviceName: db`, selector and labels `app=db`,
   container `hello` on port 8080 named `http`, env `DATA_DIR=/data`, and a
   `volumeClaimTemplates` entry named `data`: 1Gi, ReadWriteOnce, mounted at `/data`.

3. Watch them come up **in order** - this is worth actually watching:

       kubectl -n lesson-13 get pods -w

   `db-0` Ready, then `db-1` is created, then `db-2`. Not in parallel.

4. Look at the identity you just bought:

       kubectl -n lesson-13 get pods,pvc
       kubectl -n lesson-13 exec db-0 -- nslookup db-1.db.lesson-13.svc.cluster.local

   Three PVCs: `data-db-0`, `data-db-1`, `data-db-2`. And `db-1` has a DNS name.

   Use the **full** name there, and try the short `db-1.db` as well - it fails. That is
   not Kubernetes: these are Alpine images, and musl libc only applies the `search` list
   from `/etc/resolv.conf` to names containing **no dot at all**. glibc (Debian, Ubuntu,
   the .NET non-alpine images) applies it up to `ndots`. Same cluster, same DNS, different
   answer depending on your base image - a genuinely nasty one to debug in production, and
   a good reason to use fully-qualified names in configuration.

5. Write something distinct into each Pod's own volume:

       for i in 0 1 2; do kubectl -n lesson-13 exec db-$i -- wget -qO- http://127.0.0.1:8080/data; done

   Each returns one line naming itself - separate disks, not a shared one.

6. Now destroy `db-1` and prove all three guarantees at once:

       kubectl -n lesson-13 delete pod db-1
       kubectl -n lesson-13 wait --for=condition=Ready pod/db-1 --timeout=120s
       kubectl -n lesson-13 exec db-1 -- wget -qO- http://127.0.0.1:8080/data

   Same name, same PVC, and the previous line is still in the file. Compare that to lesson
   04, where the replacement Pod had a new name, a new IP and nothing of its own.

7. Optional, and instructive: scale down and back up.

       kubectl -n lesson-13 scale sts db --replicas=1
       kubectl -n lesson-13 get pods,pvc          # Pods gone, PVCs still there
       kubectl -n lesson-13 scale sts db --replicas=3
       kubectl -n lesson-13 exec db-2 -- wget -qO- http://127.0.0.1:8080/data

   `db-2` comes back to its own old data. Leave it at 3 for the checker.

## Hints

- `serviceName` must match the headless Service's name exactly, or the DNS records never
  appear and `kubectl describe sts` says nothing useful about it.
- `volumeClaimTemplates` is a list of PVC objects (with `metadata.name` and `spec`), a
  sibling of `template`, not inside it.
- The container references it by name in `volumeMounts` - there is no `volumes:` entry;
  the controller creates one per Pod.
- If Pods hang at `db-0` Pending, look at the PVC: `kubectl -n lesson-13 describe pvc data-db-0`.

## Solution

See `lab/solutions/13/all.yaml`.
