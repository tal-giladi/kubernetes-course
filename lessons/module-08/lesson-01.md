# 23 - The debugging playbook

Everything so far has been "how it works". This is "what to do at 2am". The good news is
that Kubernetes failures are extremely repetitive: a handful of symptoms cover almost
everything, and each has a short, mechanical path to the cause.

## The order that works

    kubectl -n NS get pods                       # STATUS, READY, RESTARTS, AGE
    kubectl -n NS describe pod POD               # spec + conditions + EVENTS (read to the end)
    kubectl -n NS logs POD                       # current container
    kubectl -n NS logs POD --previous            # the one that died - usually the useful one
    kubectl -n NS get events --sort-by=.lastTimestamp

Read those four columns before forming a theory. `STATUS` tells you the phase, `READY`
tells you about probes, `RESTARTS` tells you about liveness or crashes, `AGE` tells you
whether this is new. Events are the single richest source in the system, and they expire
after an hour - so grab them early.

## The symptom table

**`Pending`** - not scheduled. `describe pod` and read `FailedScheduling`, which names
every node and why it was rejected.
  - `Insufficient cpu/memory` - requests too big, or the cluster genuinely full (lesson 15)
  - `node(s) had untolerated taint` - taints (lesson 16)
  - `didn't match Pod's node affinity/selector` - your selector, or a missing node label
  - `pod has unbound immediate PersistentVolumeClaims` - the PVC, not the Pod (lesson 12)

**`ImagePullBackOff` / `ErrImagePull`** - the kubelet cannot get the image. The event says
which: `manifest unknown` (wrong tag), `unauthorized` (missing `imagePullSecrets`),
`no such host` (DNS/network), or, on kind, an image you built locally and never loaded
(lesson 06).

**`CrashLoopBackOff`** - the image is fine; your process exits. `logs --previous` is the
whole answer. Common causes: missing config, a dependency that is not up yet, a container
whose command exits immediately. Note the exit code in `describe`: `137` is SIGKILL
(OOM or liveness), `143` is SIGTERM, `1` is your application.

**`CreateContainerConfigError`** - a referenced ConfigMap or Secret key does not exist. The
event names it exactly. The Pod never starts, so there are no logs at all.

**`Running` but `0/1 READY`** - a failing readiness probe. Not a crash. Curl the endpoint
from inside the Pod and see what it actually returns (lesson 14).

**`Terminating` forever** - a finalizer waiting on something, or a stuck `preStop` /
grace period. `kubectl get pod POD -o yaml | grep -A5 finalizers`.

**`OOMKilled`** - the container exceeded its memory limit. Raise the limit or fix the leak;
do not remove the limit (lesson 15).

**Service returns nothing** - endpoints. Always endpoints.
`kubectl -n NS describe svc X` and look at the `Endpoints:` line. Empty means the selector
does not match, or no Pod is Ready (lesson 08).

**A 404 from an Ingress** - no rule matched (host or path). **A 503** - a rule matched but
the backend Service has no endpoints (lesson 10).

**A timeout with no error anywhere** - NetworkPolicy dropping packets (lesson 20), or a
Service pointing at the wrong port.

## Getting inside

    kubectl -n NS exec -it POD -- sh
    kubectl -n NS port-forward pod/POD 8080:8080
    kubectl -n NS cp POD:/app/log.txt ./log.txt
    kubectl -n NS debug POD -it --image=busybox:1.37 --target=hello

`kubectl debug` adds an **ephemeral container** to a running Pod, sharing its namespaces.
It is the answer to "the image is distroless and has no shell": you attach a busybox that
can see the same processes, network and (with `--target`) the same filesystem namespace,
without restarting anything. Also:

    kubectl debug node/k8s-lab-worker -it --image=busybox:1.37   # a shell on the node

## Cluster-level

    kubectl get nodes
    kubectl describe node NODE | sed -n '/Conditions/,/Events/p'   # DiskPressure, MemoryPressure
    kubectl top nodes ; kubectl top pods -A
    kubectl -n kube-system get pods                                # CoreDNS, kube-proxy healthy?
    kubectl get --raw='/readyz?verbose'
    kubectl api-resources                                          # does the API server answer at all?

A cluster-wide weirdness that resolves to "CoreDNS is crash-looping" or "a node has
DiskPressure" is common enough to check these first when *many* things are broken at once.

## Observability, in one paragraph

`kubectl logs` reads the kubelet's file on one node and is gone when the Pod is. Anything
real ships logs off the node (Fluent Bit/Vector to Loki, Elastic, or your cloud's log
service), scrapes metrics with Prometheus (kube-state-metrics for object state, cAdvisor
for container resources), and traces with OpenTelemetry. `kubectl top` is the two-minute
version of the metrics half, and it needs metrics-server (lesson 17). The debugging skills
here do not go away - they are what you do once the dashboard has told you *where*.

## Do this

This exercise is different: **nothing is provided in working order.** Apply a namespace
full of broken workloads, diagnose each one from the cluster (not from the file), and fix
it. Try hard not to open the manifest until you have a theory.

    kubectl apply -f lab/apps/broken/broken.yaml
    kubectl -n lesson-23 get pods

Four Deployments, four different failures:

  - **`app-a`** - never starts. The Pod never runs a single line of your code.
  - **`app-b`** - looks perfectly healthy, but `curl` through its Service returns nothing.
  - **`app-c`** - never starts either, but for a completely different reason than `app-a`,
    and with no logs at all.
  - **`app-d`** - the Pod exists and the Deployment says 0 available, forever.

For each one, work the playbook: `get pods`, `describe`, `logs`, `logs --previous`,
`get events`. Then fix it **in the cluster** with `kubectl edit`, `kubectl patch` or
`kubectl set` - or edit a copy of the manifest and re-apply. Any route is fine.

The finish line: all four Deployments have all their replicas Ready, and `app-b`'s Service
has endpoints. Then run the checker.

Rules that make this worth doing:

  - Do not delete a Deployment and recreate it from scratch. Fix what is there.
  - Write down your diagnosis for each before you fix it. Being right for the wrong reason
    is the thing this exercise is meant to catch.

## Hints

Only if you are properly stuck - one hint per app, in order of increasing spoiler:

- **app-a**: the STATUS column is the diagnosis. Look at what the event says the kubelet
  asked for, and compare it with `docker images hello`.
- **app-b**: the Pods are fine. `kubectl -n lesson-23 describe svc app-b` and read one
  line. Then `kubectl -n lesson-23 get pods -l app=app-b --show-labels`.
- **app-c**: `describe pod` names the exact thing it could not find. `kubectl -n lesson-23
  get cm app-c-config -o yaml` and compare with what the container asks for.
- **app-d**: `describe pod` and read `FailedScheduling`. Then
  `kubectl describe node k8s-lab-worker | grep -A6 'Allocated resources'`.

## Solution

`lab/solutions/23/fixed.yaml` is the corrected manifest, with a comment on each fix.
Applying it also satisfies the checker - but read it after you have tried, not before.
