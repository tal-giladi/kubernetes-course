# 04 - Deployments and ReplicaSets

*Module 02 - Running workloads, lesson 1 of 4. Exercise 04 of 25.*

You now know a Pod is mortal and never repaired. So who makes a new one? A chain of two
controllers:

    Deployment  ->  ReplicaSet  ->  Pods

## ReplicaSet: keep N alive

A ReplicaSet has exactly one job. Its spec says "N Pods matching this selector should
exist"; its control loop counts, and creates or deletes to close the gap. That is all. It
has no notion of versions, upgrades, or history.

    spec:
      replicas: 3
      selector:
        matchLabels:
          app: web
      template:          # a Pod spec, minus apiVersion/kind
        metadata:
          labels:
            app: web
        spec:
          containers: [...]

Two rules that bite everyone once:

1. `spec.selector` must match `spec.template.metadata.labels`, or the API server rejects
   the object outright. A ReplicaSet whose selector didn't match its own template would
   create Pods forever, never counting any of them.
2. `spec.selector` is **immutable**. To change it you delete and recreate.

A ReplicaSet **adopts** any existing Pod that matches its selector and has no other
owner. Label a stray Pod `app=web` in that namespace and the ReplicaSet will happily
count it as one of its own - and delete it when scaling down. Ownership is recorded in
`metadata.ownerReferences`, which is also what makes cascading delete work: delete the
ReplicaSet and the garbage collector removes the Pods it owns.

## Deployment: manage ReplicaSets over time

A Deployment owns ReplicaSets the way a ReplicaSet owns Pods. Change the Pod template and
the Deployment creates a **new** ReplicaSet and shifts replicas from old to new. The old
one stays, scaled to 0. That preserved, scaled-to-zero ReplicaSet is your rollback (lesson
05).

To keep two ReplicaSets that both select `app=web` from stealing each other's Pods, the
Deployment adds a `pod-template-hash` label to every ReplicaSet and Pod it creates and
folds it into the selector. It is why Pod names look like this:

    web-7d9f8c6b45-x2ktq
    ^--- deployment
        ^------- template hash
                 ^---- random suffix

Two Pods of the same Deployment with *different* middle segments means a rollout is in
flight, or a previous one never finished.

## Self-healing, concretely

Delete a Pod and watch:

    kubectl -n lesson-04 delete pod <name>
    kubectl -n lesson-04 get pods -w

Within a second or two the ReplicaSet notices `observed 2 != desired 3` and creates a
replacement - **new name, new IP**. Nothing was repaired. Something new was created. Every
piece of Kubernetes design follows from taking that seriously: never store state in a
Pod's filesystem, never let another component remember a Pod IP.

Now try it at the node level:

    docker stop k8s-lab-worker2

The Node goes `NotReady`. After `node-monitor-grace-period` (~40s) it is marked unhealthy;
after the taint-based eviction timeout (default 300s) its Pods are marked for deletion and
recreated elsewhere. That five-minute default surprises people - Kubernetes deliberately
waits, because a node that vanished for 30 seconds is usually a network blip, and
stampeding every workload onto the remaining nodes is worse than waiting. Bring it back
with `docker start k8s-lab-worker2`.

## Scaling

    kubectl -n lesson-04 scale deploy/web --replicas=5
    kubectl -n lesson-04 get rs           # DESIRED / CURRENT / READY

The three columns are worth reading carefully. `DESIRED` is your wish. `CURRENT` is Pods
that exist. `READY` is Pods passing their readiness check. When `CURRENT` sits below
`DESIRED`, the scheduler cannot place them - check `kubectl get pods` for `Pending` and
read the Events. When `READY` sits below `CURRENT`, the Pods exist but the app is not
answering - that is lesson 14.

## Deleting

    kubectl -n lesson-04 delete deploy web                 # cascades: RS and Pods go too
    kubectl -n lesson-04 delete deploy web --cascade=orphan  # leaves the RS running

Orphaning is occasionally useful and usually a mistake you will discover three days later
when a ReplicaSet nobody owns is still serving traffic.

## Do this

In namespace `lesson-04`:

1. A Deployment `web`: 3 replicas, label `app=web`, container `nginx`, image
   `nginx:1.29-alpine`, containerPort 80.
2. Look at the layers you just created:

       kubectl -n lesson-04 get deploy,rs,pods --show-labels

   Find the `pod-template-hash` in both the ReplicaSet name and the Pod labels.
3. Delete a Pod and watch a new one appear. Confirm the name and IP changed:

       kubectl -n lesson-04 get pods -o wide

4. Scale the Deployment to **5**.
5. Now create a **bare ReplicaSet** called `rs-demo` in the same namespace: 2 replicas,
   selector and labels `app=demo`, image `nginx:1.29-alpine`. Do not wrap it in a
   Deployment. Then try to "upgrade" it:

       kubectl -n lesson-04 set image rs/rs-demo nginx=nginx:1.27-alpine
       kubectl -n lesson-04 get pods -l app=demo -o jsonpath='{.items[*].spec.containers[0].image}'

   The template changed. The running Pods did **not**. A ReplicaSet only creates Pods from
   the template when it needs *more* Pods; it will never replace a healthy one. Delete a
   demo Pod and the replacement comes up on the new image, giving you a half-upgraded
   application. That is precisely the problem a Deployment exists to solve, and it is
   worth feeling once.

## Hints

- `kubectl -n lesson-04 create deploy web --image=nginx:1.29-alpine --replicas=3`
- `kubectl create` has no ReplicaSet generator - write the YAML. Start from the Deployment
  YAML (`kubectl get deploy web -o yaml`), change `kind` to `ReplicaSet`, drop `strategy`
  and `status`, and change the labels to `app=demo`.
- `apiVersion` for a ReplicaSet is `apps/v1`.

## Solution

See `lab/solutions/04/`.
