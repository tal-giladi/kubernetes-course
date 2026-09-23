# 15 - Resources, QoS and eviction

*Module 05 - Reliability, lesson 2 of 4. Exercise 15 of 25.*

Two numbers per container decide where your Pod runs, what happens when the node is busy,
and who dies when it runs out of memory. They are the most consequential four lines in a
Pod spec, and the most commonly left blank.

    resources:
      requests:            # what the scheduler reserves for you
        cpu: 100m
        memory: 128Mi
      limits:              # what the kernel will not let you exceed
        cpu: 500m
        memory: 256Mi

`100m` is 100 millicores - a tenth of one core. Memory suffixes are binary: `Mi` is
1048576 bytes, `M` is 1000000. Use `Mi`/`Gi`.

## Requests are for scheduling. Limits are for the kernel.

**Requests** are the *only* thing the scheduler looks at. It sums the requests of all Pods
on a node and refuses to place a Pod whose request does not fit in what remains. Note what
this means: scheduling is based on **reservations, not usage**. A node can be 5% busy and
still be "full", because everything on it requested more than it uses.

**Limits** are enforced by the kernel at runtime, and the two resources behave completely
differently:

  - **CPU is compressible.** Exceed the limit and you are *throttled* - the kernel gives
    you fewer time slices. Your app gets slow. Nothing dies. High CPU throttling is one of
    the most common invisible causes of latency, and you only see it in
    `container_cpu_cfs_throttled_seconds_total`.
  - **Memory is not compressible.** Exceed the limit and the kernel's OOM killer kills the
    process. Exit code 137, `reason: OOMKilled`, and the container restarts.

Consequences worth internalising: **always set a memory limit** (an unbounded leak
otherwise takes down the whole node, not just your Pod), and **be careful with CPU
limits** - a Pod that is throttled to 500m while the node is idle is pure waste. Many
teams set CPU requests and no CPU limit deliberately.

For .NET specifically: modern runtimes read the cgroup limit, so a memory limit changes
the GC's heap sizing and `Environment.ProcessorCount` reflects the CPU limit. Setting them
is how you tune the runtime, not just the scheduler.

## QoS classes: who gets killed first

The kubelet derives a class from your numbers - you do not set it directly:

  - **Guaranteed** - every container has `requests == limits` for both CPU and memory.
    Last to be evicted.
  - **Burstable** - requests are set and lower than limits (or only some are set).
  - **BestEffort** - no requests or limits at all. **First to be evicted**, always.

When a node runs low on memory, the kubelet evicts BestEffort Pods first, then Burstable
Pods that are exceeding their requests, and Guaranteed Pods last. "We set no resources" is
therefore not neutral - it is opting into being killed first.

    kubectl -n lesson-15 get pods -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass

Note the difference between **eviction** (the kubelet reclaiming a node under pressure -
the Pod is deleted and rescheduled elsewhere) and **OOMKill** (the kernel killing one
container that exceeded *its own* limit - the container restarts in place). They look
similar and have different fixes.

## Pending: the other half

If no node has room for your request, the Pod stays `Pending` forever with a clear
message:

    kubectl -n lesson-15 describe pod toobig | tail -5
    Warning  FailedScheduling  ... 0/3 nodes are available:
             3 Insufficient cpu. preemption: 0/3 nodes are available

That message is the single most useful line in the scheduler. It tells you *why* each node
was rejected: insufficient cpu/memory, taints, node affinity, volume-zone conflicts. Read
it before theorising.

**PriorityClasses** change this: a high-priority Pod that cannot be scheduled can *preempt*
(evict) lower-priority Pods to make room. Useful, and easy to misuse.

## Right-sizing, honestly

    kubectl top pods -n lesson-15     # needs metrics-server (lesson 17)
    kubectl top nodes

Rules of thumb that survive contact with reality: set requests near the p50 of real usage,
memory limits near the observed peak plus headroom, and treat a memory request equal to
its limit as the honest choice for anything stateful. Then measure - guessing produces
either constant OOMKills or a cluster that is 20% utilised and "full".

## Do this

In namespace `lesson-15`:

1. Three workloads that differ **only** in their resources block, so you can see QoS
   derived from the numbers. All use `hello:1.1.0`, 1 replica each:

       Deployment `guaranteed` - requests == limits: cpu 100m, memory 128Mi
       Deployment `burstable`  - requests cpu 100m / memory 128Mi, limits cpu 500m / memory 256Mi
       Deployment `besteffort` - no `resources` block at all

   Then look at what Kubernetes decided:

       kubectl -n lesson-15 get pods -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass

2. Get a container OOMKilled on purpose. A Pod `hungry`, image `busybox:1.37`,
   command `["sh","-c","tail /dev/zero"]` (which allocates without limit), with
   `limits.memory: 32Mi`:

       kubectl -n lesson-15 get pod hungry -w
       kubectl -n lesson-15 describe pod hungry | grep -A3 'Last State'
       kubectl -n lesson-15 get pod hungry -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'

   `OOMKilled`, exit code 137, then `CrashLoopBackOff` as it tries again. The node is fine;
   only this container hit *its own* ceiling.

3. Get a Pod stuck `Pending` on purpose. A Pod `toobig`, image `hello:1.1.0`, requesting
   `cpu: "100"` (a hundred cores):

       kubectl -n lesson-15 get pod toobig
       kubectl -n lesson-15 describe pod toobig | tail -6

   Read the FailedScheduling event and notice that it names every node and its reason.
   Nothing is broken - the cluster is telling you precisely what you asked for is
   impossible.

4. See the node's own accounting, which is where "the node is full but idle" becomes
   obvious:

       kubectl describe node k8s-lab-worker | sed -n '/Allocated resources/,/^Events/p'

   Requests and limits as percentages of capacity - reservations, not usage.

## Hints

- `resources` is per **container**, under `spec.template.spec.containers[0]`.
- QoS `Guaranteed` requires requests to equal limits for **both** cpu and memory, on
  **every** container in the Pod.
- `kubectl -n lesson-15 run hungry --image=busybox:1.37 --restart=Never --limits=memory=32Mi -- sh -c 'tail /dev/zero'`
  is close, but `--limits` is deprecated; writing the YAML is cleaner.
- Leave `hungry` and `toobig` in place - the checker looks at them.

## Solution

See `lab/solutions/15/all.yaml`.
