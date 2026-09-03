# Module 04 quiz - Configuration and state

Eight questions. Answers at the bottom.

---

**1.** You change one value in a ConfigMap. One container reads it as an env var, another
mounts it as a file, a third mounts it with `subPath`. What does each see after two
minutes, and why?

**2.** Your reviewer says "the password is safe, it is in a Secret". Give the three things
that actually protect a Secret, and one thing that does not.

**3.** You create a PVC and it sits `Pending` with no Pod using it. Your colleague opens a
ticket about broken storage. What do you tell them, and which single field decides this?

**4.** A Deployment with 3 replicas and one `ReadWriteOnce` PVC: describe exactly what
happens to each replica, and what you should have used instead.

**5.** `kubectl delete namespace staging` completes. Two hours later someone asks for the
database back. What determined whether it still exists?

**6.** Name three concrete things a StatefulSet gives you that a Deployment does not, and
one important thing it does *not* give you despite the name.

**7.** You scale a StatefulSet from 5 replicas to 2. What happens to `data-db-2`,
`data-db-3` and `data-db-4`? Is that good or bad?

**8.** From a Pod based on an Alpine image, `nslookup db-1.db` fails but
`nslookup db-1.db.myns.svc.cluster.local` works. From a Debian-based Pod both work. What is
going on, and what is the practical lesson?

---

## Answers

**1.** The **env var** shows the old value - env vars are bound at container start and
never change. The **mounted file** shows the new value, typically within a minute (kubelet
sync plus cache TTL). The **`subPath` mount** shows the old value forever: subPath mounts
are never updated. And the application only benefits if it re-reads the file, which most do
not - so the honest pattern is to treat config changes as deployments (`rollout restart`,
or a checksum annotation, or Kustomize's generator hash).

**2.** RBAC on `get`/`list` of secrets in that namespace; encryption at rest configured on
the API server; and keeping the value out of the cluster entirely (Key Vault / Secrets
Store CSI / External Secrets). Also worth doing: mount as a file rather than an env var, so
it does not leak into crash dumps and child processes. What does **not** protect it: base64,
which is an encoding anyone can reverse with one command.

**3.** Nothing is broken. The StorageClass has `volumeBindingMode: WaitForFirstConsumer`,
which deliberately delays provisioning until a Pod that uses the claim is scheduled, so the
disk is created in the right zone/node. It will bind seconds after the first consumer
appears.

**4.** Whichever replica is scheduled first mounts the volume and runs. Any replica the
scheduler places on the **same node** will also start (RWO is per-node). Any replica placed
on another node sits in `ContainerCreating`/`Pending` forever with a multi-attach error.
Options: keep it at one replica, use an RWX-capable backend, or - if each replica needs its
own disk - use a StatefulSet with `volumeClaimTemplates`.

**5.** The StorageClass's `persistentVolumeReclaimPolicy`. With `Delete` (the default for
dynamic provisioning) the PVC's deletion deleted the underlying disk, and the data is gone.
With `Retain`, the PV and its data still exist in a `Released` state and can be recovered
by hand.

**6.** (a) Stable ordinal names that the replacement Pod reuses; (b) one PVC per Pod via
`volumeClaimTemplates`, re-attached to the same ordinal; (c) ordered, one-at-a-time
creation, deletion and rolling update. Also stable per-Pod DNS via the headless Service.
What it does **not** give you: any clustering. No leader election, no replication, no
failover - `db-0` is just the first Pod, not "the primary".

**7.** All three PVCs remain. This is deliberate: the data outlives the Pod, and scaling
back up re-attaches it - which is what you want after an incident. It is bad when nobody
knows they exist, because they are real disks costing real money; the
`persistentVolumeClaimRetentionPolicy` field lets you opt into cleanup on scale-down or
delete.

**8.** Alpine uses **musl** libc, which only applies the `search` list from
`/etc/resolv.conf` to names containing **no dot at all**; glibc applies it up to `ndots`.
Same cluster, same CoreDNS, different behaviour depending on your base image. The practical
lesson: use fully-qualified service names in configuration, and be suspicious of "DNS is
broken" reports that only come from some images.
