# 14 - Probes: liveness, readiness, startup

*Module 05 - Reliability, lesson 1 of 4. Exercise 14 of 25.*

Kubernetes has no idea what "healthy" means for your application. Without probes its only
signal is "did the process exit", which is the weakest possible definition. Probes are how
you tell it something better - and they are what make Services and rolling updates safe.

## Three probes, three different questions

**`readinessProbe` - "should traffic come to me right now?"**
Failing removes the Pod from every Service's EndpointSlice. The container is **not**
restarted. This is the probe that matters most: it is what makes a rolling update safe,
what keeps a warming-up Pod out of the load balancer, and what lets an overloaded Pod shed
traffic without dying.

**`livenessProbe` - "am I wedged and beyond saving?"**
Failing **kills the container** and the kubelet restarts it. Powerful and dangerous. Use
it only for genuinely unrecoverable states - a deadlock, an exhausted thread pool. Never
point it at a dependency: if it checks your database, then a database blip restarts every
Pod you own, turning a partial outage into a total one with a thundering herd behind it.
**When in doubt, do not add a liveness probe.** An app with no liveness probe is restarted
only when it crashes, which is usually correct.

**`startupProbe` - "has it finished booting?"**
While it is failing, the liveness and readiness probes are **suspended**. This is the
right answer for a slow starter (a big .NET app warming up, a JVM, a cache to load).
Without it you have to choose between a liveness `initialDelaySeconds` long enough for the
worst boot - which delays detection of real hangs forever - or a probe that kills the
container mid-boot, forever, in a loop that looks exactly like a crash.

## Handlers

    httpGet:    { path: /readyz, port: http, httpHeaders: [...] }   # 200-399 is success
    tcpSocket:  { port: 5432 }                                      # can we connect?
    exec:       { command: ["sh","-c","test -f /tmp/ready"] }        # exit 0 is success
    grpc:       { port: 9000 }                                       # gRPC health protocol

`exec` is the expensive one - it forks a process on every probe, on every Pod, forever.
At scale that is real CPU.

## The timing fields, and what they actually cost

    initialDelaySeconds: 0    # wait this long before the first probe
    periodSeconds: 10         # how often
    timeoutSeconds: 1         # how long one probe may take        <- often too low
    successThreshold: 1       # consecutive successes to be "up"   (must be 1 for liveness)
    failureThreshold: 3       # consecutive failures to be "down"

Time to detection is `periodSeconds x failureThreshold` (plus the initial delay). The
defaults mean a dead Pod keeps receiving traffic for up to 30 seconds. Tighten readiness
if that matters; leave liveness generous, because a liveness probe that is too aggressive
does far more damage than one that is too slow.

`timeoutSeconds: 1` is the classic self-inflicted outage: under load your health endpoint
takes 1.2 seconds, the probe times out, the liveness probe restarts the container, load
shifts to the remaining Pods, they get slower, and the cluster restarts your entire
service one Pod at a time. Health endpoints must be cheap and must not touch dependencies.

## Termination is part of health

When a Pod is deleted, two things happen **at the same time**: the kubelet sends
`SIGTERM`, and the endpoint controller removes it from Services. They race. For a second
or two, traffic can still arrive at a Pod that has already begun shutting down. The
standard fix is a small `preStop` sleep, so the endpoint removal propagates before your
process starts refusing connections:

    lifecycle:
      preStop:
        exec: { command: ["sh","-c","sleep 5"] }
    terminationGracePeriodSeconds: 30

After the grace period, `SIGKILL`. If your app needs to drain long requests, raise it.

## Reading the evidence

    kubectl -n lesson-14 describe pod <pod>       # "Liveness probe failed: ..."
    kubectl -n lesson-14 get pods                 # RESTARTS column
    kubectl -n lesson-14 logs <pod> --previous    # what the killed container said
    kubectl -n lesson-14 get endpointslices       # who is actually receiving traffic

A Pod that is `Running` but `0/1 READY` is a failing readiness probe - not a crash. A
`RESTARTS` counter that climbs steadily is liveness, and the answer is almost never "make
the probe more aggressive".

## Do this

In namespace `lesson-14`, with `hello:1.1.0`:

1. Deployment `hello`: 3 replicas, label `app=hello`, port 8080 named `http`,
   env `READY_AFTER_SECONDS=20`, and:

   - a `readinessProbe` on `GET /readyz`, `periodSeconds: 5`, `failureThreshold: 3`
   - a `livenessProbe` on `GET /healthz`, `periodSeconds: 10`, `failureThreshold: 3`
   - a `startupProbe` on `GET /healthz`, `periodSeconds: 5`, `failureThreshold: 30`
   - a `preStop` sleep of 5 seconds and `terminationGracePeriodSeconds: 30`

2. Watch readiness gate the Service. Apply, then immediately:

       kubectl -n lesson-14 get pods -w

   The Pods are `Running 0/1` for about twenty seconds before flipping to `1/1`. During
   that window, create a Service and look at its endpoints:

       kubectl -n lesson-14 expose deploy hello --name=hello --port=8080 --target-port=http
       kubectl -n lesson-14 get endpointslices -l kubernetes.io/service-name=hello -o yaml | grep -c 'ready: true'

   Zero at first, then three. That gap is the whole reason readiness probes exist: for
   twenty seconds these Pods existed and could not serve, and no traffic reached them.

3. Now watch liveness do its job - and see why it is dangerous. A second Deployment
   `flaky`: 1 replica, label `app=flaky`, env `FAIL_LIVENESS_AFTER_SECONDS=20`, and a
   `livenessProbe` on `/healthz` with `periodSeconds: 5`, `failureThreshold: 2`:

       kubectl -n lesson-14 get pods -l app=flaky -w
       kubectl -n lesson-14 describe pod -l app=flaky | grep -A5 'Liveness'

   The app answers `/healthz` for 20 seconds, then starts returning 500. Two failed probes
   later the container is killed and restarted - and because the timer restarts with the
   process, it does this forever. `RESTARTS` climbs. That is exactly what a liveness probe
   pointed at a flapping dependency looks like in production.

4. Compare the two failure modes side by side:

       kubectl -n lesson-14 get pods

   `hello` Pods: `1/1 Running`, 0 restarts. `flaky`: `1/1 Running` with a climbing restart
   count. Neither is `Error`. Neither is `CrashLoopBackOff` at first. Health problems hide
   in the READY and RESTARTS columns, not in STATUS.

## Hints

- `port: http` in a probe refers to the **named containerPort** - clearer than repeating
  8080 everywhere.
- All three probes are siblings of `image` inside the container spec.
  `terminationGracePeriodSeconds` is on the **Pod** spec, not the container.
- `failureThreshold: 30` with `periodSeconds: 5` gives a startup budget of 150 seconds.
- If every Pod is `0/1` forever, curl the endpoint by hand from inside:
  `kubectl -n lesson-14 exec <pod> -- wget -qO- http://127.0.0.1:8080/readyz`

## Solution

See `lab/solutions/14/all.yaml`.
