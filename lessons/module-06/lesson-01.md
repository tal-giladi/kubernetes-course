# 18 - Namespaces, ResourceQuota and LimitRange

A namespace on its own is only a naming scope. It becomes a *tenancy* boundary when you
attach the three things that actually constrain it: a quota on what it may consume, a
default for what its Pods ask for, and RBAC on who may touch it (lesson 19).

## What a namespace does and does not give you

Gives you: unique names per kind, a unit for `kubectl delete`, a scope for RBAC, quotas,
LimitRanges, NetworkPolicies and ResourceQuotas, and a DNS segment.

Does **not** give you: network isolation (every Pod can reach every other Pod across
namespaces by default - lesson 20), node isolation, or protection from a noisy neighbour.
Namespaces are an organisational boundary that you then have to *enforce*.

Some objects are cluster-scoped and live outside all of this: Nodes, PersistentVolumes,
StorageClasses, ClusterRoles, CRDs, and Namespaces themselves.

`kubectl delete namespace` deletes everything inside it, including PVCs - and therefore,
with a `Delete` reclaim policy, the disks. A namespace stuck in `Terminating` is almost
always a finalizer waiting on something: `kubectl get ns X -o yaml` and look at
`spec.finalizers` and the conditions.

## ResourceQuota - a ceiling for the namespace

    apiVersion: v1
    kind: ResourceQuota
    spec:
      hard:
        requests.cpu: "1"
        requests.memory: 1Gi
        limits.cpu: "2"
        limits.memory: 2Gi
        pods: "10"
        count/deployments.apps: "3"
        persistentvolumeclaims: "4"
        requests.storage: 20Gi

Two behaviours to know:

  - **It is enforced at admission.** Exceed it and the *create* fails, with a clear
    message. Existing objects are never retro-evicted.
  - **If a quota sets `requests.cpu` or `limits.memory`, every container in that namespace
    must specify the matching value.** A Pod with no CPU request is rejected outright:
    `must specify requests.cpu`. This is where a quota and a LimitRange become a pair - the
    LimitRange supplies the value the quota insists upon.

The failure is one level removed and confuses everyone the first time: a Deployment applies
fine, but no Pods appear. The Deployment object was accepted; the **ReplicaSet** could not
create Pods. The evidence is not on the Pod (there is none) - it is on the ReplicaSet:

    kubectl -n lesson-18 describe rs <name>     # FailedCreate: exceeded quota ...
    kubectl -n lesson-18 get events --sort-by=.lastTimestamp

`scopeSelector` lets one quota apply only to, say, `BestEffort` Pods or a
`PriorityClass` - the usual way to reserve headroom for critical workloads.

## LimitRange - defaults and bounds per object

    apiVersion: v1
    kind: LimitRange
    spec:
      limits:
        - type: Container
          default:            { cpu: 200m, memory: 256Mi }   # -> limits, if unset
          defaultRequest:     { cpu: 100m, memory: 128Mi }   # -> requests, if unset
          max:                { cpu: "1",  memory: 1Gi }
          min:                { cpu: 10m,  memory: 32Mi }
        - type: PersistentVolumeClaim
          max: { storage: 10Gi }

A LimitRange is a **mutating** admission step: it fills in what you left blank, then
validates against min/max. It is per-container/per-PVC, where a ResourceQuota is
per-namespace - a LimitRange stops one Pod being absurd; a quota stops the namespace as a
whole being absurd.

It applies at creation time only. Adding a LimitRange does not change Pods that already
exist.

Together they give you the property you actually want in a shared cluster: **nobody can
deploy a Pod with no resources**, because the LimitRange fills them in, and the namespace
cannot exceed its share, because the quota says so.

## Do this

1. Create namespace `lesson-18`, then attach:

   A **ResourceQuota** `team-quota`:

       requests.cpu: 500m
       requests.memory: 512Mi
       limits.cpu: "1"
       limits.memory: 1Gi
       pods: "5"
       count/deployments.apps: "2"

   A **LimitRange** `defaults` for type `Container`:

       default:        cpu 200m, memory 256Mi
       defaultRequest: cpu 100m, memory 128Mi
       max:            cpu 500m, memory 512Mi

2. Deploy `hello`: 2 replicas, label `app=hello`, image `hello:1.1.0`, port 8080 named
   `http`, and **no `resources` block at all**. Then look at what was actually created:

       kubectl -n lesson-18 get deploy hello -o jsonpath='{.spec.template.spec.containers[0].resources}'
       kubectl -n lesson-18 get pod -l app=hello -o jsonpath='{.items[0].spec.containers[0].resources}'

   The Deployment's template still has nothing. The **Pod** has 100m/128Mi requests and
   200m/256Mi limits, injected on the way in. That difference - template unchanged, object
   mutated - is what "mutating admission" means, and it is worth seeing once.

3. Watch the quota fill up:

       kubectl -n lesson-18 describe quota team-quota

   Used vs Hard, for every dimension.

4. Now break it three different ways, and read each message:

       # a) too many Pods for the quota
       kubectl -n lesson-18 scale deploy/hello --replicas=6
       kubectl -n lesson-18 get deploy hello          # 2 available, not 6
       kubectl -n lesson-18 describe rs -l app=hello | grep -A2 Events
       kubectl -n lesson-18 scale deploy/hello --replicas=2

   Note carefully: the *scale* succeeded. The Deployment wants 6. The ReplicaSet cannot
   create them, and the only place that says so is the ReplicaSet's events.

       # b) a container above the LimitRange max
       kubectl -n lesson-18 run toobig --image=hello:1.1.0 --restart=Never \
         --overrides='{"spec":{"containers":[{"name":"c","image":"hello:1.1.0","resources":{"requests":{"cpu":"900m"}}}]}}'

   Rejected immediately: "maximum cpu usage per Container is 500m".

       # c) a third Deployment, against count/deployments.apps: "2"
       kubectl -n lesson-18 create deploy extra --image=hello:1.1.0

   Rejected: "exceeded quota: team-quota, requested: count/deployments.apps=1, used: ...".

5. Leave the namespace with exactly the `hello` Deployment at 2 replicas for the checker.

## Hints

- `kubectl create quota team-quota --hard=pods=5,requests.cpu=500m,...` exists, but writing
  the YAML is clearer for six dimensions.
- There is no `kubectl create limitrange` - write it. `apiVersion: v1`, `kind: LimitRange`.
- If `hello`'s Pods never appear at all, you have hit case (a) with the quota already full;
  `describe rs` will say so.
- `kubectl -n lesson-18 get resourcequota -o yaml` shows `status.used` live.

## Solution

See `lab/solutions/18/all.yaml`.
