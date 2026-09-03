# 16 - Scheduling and placement

By default the scheduler puts Pods wherever they fit and you should mostly let it. But
"wherever" is wrong when a workload needs specific hardware, when two replicas of the same
service must not share a failure domain, or when a node is reserved for something else.
These are the four tools, from bluntest to sharpest.

## How a Pod gets a node

Two phases, every time:

  - **Filtering** - eliminate nodes that cannot work: insufficient requests, taints you do
    not tolerate, node affinity that does not match, a volume that lives in another zone.
  - **Scoring** - rank the survivors: most free resources, image already present, affinity
    preferences, spread.

The winner is written to `pod.spec.nodeName`, and *that* is what the kubelet watches for.
Setting `nodeName` yourself bypasses the scheduler entirely - a debugging trick, never a
design.

## nodeSelector - the blunt one

    nodeSelector:
      disktype: ssd

Exact label match, all of them, hard requirement. Simple and readable. When it does not
fit, you want affinity.

## Node affinity - the expressive one

    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: disktype
                  operator: In           # In, NotIn, Exists, DoesNotExist, Gt, Lt
                  values: [ssd, nvme]
        preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 80
            preference:
              matchExpressions:
                - { key: topology.kubernetes.io/zone, operator: In, values: [eu-west-1a] }

`required` filters; `preferred` only scores, so the Pod still schedules if nothing
matches. Read `IgnoredDuringExecution` literally: **the rule is checked once, at scheduling
time.** Change a node's labels afterwards and running Pods are not moved.

## Pod affinity and anti-affinity - placement relative to other Pods

    affinity:
      podAntiAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels: { app: web }
            topologyKey: kubernetes.io/hostname

"Do not put me where a Pod labelled `app=web` already is, where 'where' means the same
node." Change `topologyKey` to `topology.kubernetes.io/zone` and it means the same zone.

This is how you stop all three replicas landing on one node and dying together. Two
warnings: **`required` anti-affinity with more replicas than topology domains leaves the
extras `Pending` forever** (3 replicas, 2 usable nodes, one Pod never schedules), and pod
affinity is computationally expensive at scale - it must compare against every other Pod.
Prefer `preferred`, or prefer the next tool.

## Topology spread constraints - the modern answer

    topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: ScheduleAnyway     # or DoNotSchedule
        labelSelector:
          matchLabels: { app: spread }

"Across nodes, the count of my Pods must not differ by more than 1." With 4 Pods and 2
usable nodes you get 2 and 2. This says what you actually mean - *balance* - where
anti-affinity only says *never together*, and `ScheduleAnyway` degrades gracefully instead
of leaving Pods stuck. For most services this is the right choice.

## Taints and tolerations - the node's own opinion

Affinity is the Pod choosing nodes. Taints are the **node repelling Pods**.

    kubectl taint node k8s-lab-worker2 lab=demo:NoSchedule

    NoSchedule         do not place new Pods here
    PreferNoSchedule   avoid if you can
    NoExecute          also evict Pods already running here

A Pod may only land on a tainted node if it carries a matching **toleration**:

    tolerations:
      - key: lab
        operator: Equal
        value: demo
        effect: NoSchedule

You met this in lesson 07: the control-plane node is tainted, which is why a naive
DaemonSet covered two nodes out of three. Real clusters taint GPU nodes, spot/preemptible
nodes, and nodes reserved for a tenant.

Key point: **a toleration permits, it does not attract.** Tolerating `lab=demo` does not
make a Pod prefer that node - it only stops the taint from filtering it out. To *pull* a
Pod onto specific nodes you still need a nodeSelector or affinity. Taint + label + selector
is the standard pair.

The node lifecycle controller also uses taints: an unreachable node gets
`node.kubernetes.io/unreachable:NoExecute`, and the default 300-second
`tolerationSeconds` on every Pod is exactly the five-minute delay you saw in lesson 04.

## Do this

In namespace `lesson-16`, with `hello:1.1.0`. This lesson changes **node** objects, which
are cluster-scoped - the final step puts them back.

1. Label a node, then pin a workload to it:

       kubectl label node k8s-lab-worker disktype=ssd
       kubectl get nodes -L disktype

   Deployment `pinned`: 2 replicas, label `app=pinned`, `nodeSelector: {disktype: ssd}`.
   Confirm both Pods are on `k8s-lab-worker`:

       kubectl -n lesson-16 get pods -l app=pinned -o wide

   Step 4 taints `k8s-lab-worker2`, which would leave the next two workloads with a single
   usable node and nothing to spread across. So `spread` and `apart` both carry a
   toleration for that taint - a small preview of how these tools compose, and of why a
   placement rule is only as good as the set of nodes it is allowed to consider.

2. Deployment `spread`: **4** replicas, label `app=spread`, a toleration for
   `lab=demo:NoSchedule`, and a topology spread constraint - `maxSkew: 1`,
   `topologyKey: kubernetes.io/hostname`, `whenUnsatisfiable: ScheduleAnyway`, selecting
   `app=spread`. Count them per node:

       kubectl -n lesson-16 get pods -l app=spread -o wide
       kubectl -n lesson-16 get pods -l app=spread -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c

   Two per worker. (The control-plane node is tainted, so it does not participate.)

3. Deployment `apart`: 2 replicas, label `app=apart`, the same toleration, and
   **required** pod anti-affinity on `kubernetes.io/hostname` selecting `app=apart`. Two
   Pods, two different nodes.

   Then break it on purpose and read the message:

       kubectl -n lesson-16 scale deploy/apart --replicas=4
       kubectl -n lesson-16 get pods -l app=apart
       kubectl -n lesson-16 describe pod <a Pending one> | tail -5
       kubectl -n lesson-16 scale deploy/apart --replicas=2

   Two Pods `Pending` forever: there are only two usable nodes and the rule is `required`.
   This is the anti-affinity trap, and now you have seen it.

4. Taint a node and tolerate it:

       kubectl taint node k8s-lab-worker2 lab=demo:NoSchedule

   Deployment `tolerant`: 1 replica, label `app=tolerant`, with a matching toleration
   **and** `nodeSelector: {kubernetes.io/hostname: k8s-lab-worker2}` - because tolerating
   is not the same as choosing. Confirm it landed there, then confirm the untolerated
   `spread` Pods have drifted off that node when rescheduled:

       kubectl -n lesson-16 get pods -o wide

5. Put the cluster back:

       kubectl taint node k8s-lab-worker2 lab=demo:NoSchedule-
       kubectl label node k8s-lab-worker disktype-

   Note the trailing `-` in both: that is how kubectl removes a label or a taint. Run the
   checker **before** this step - it verifies the taint and label are in place.

## Hints

- `kubernetes.io/hostname` is a built-in label on every node; `kubectl get node
  k8s-lab-worker --show-labels` lists the rest.
- `topologySpreadConstraints` and `affinity` are Pod-spec fields, siblings of `containers`.
- A `required` rule that cannot be met produces `Pending`, never an error on apply.
- To see the scheduler's reasoning: `kubectl -n lesson-16 get events --field-selector reason=FailedScheduling`.

## Solution

See `lab/solutions/16/all.yaml`.
