# Module 05 quiz - Reliability

Nine questions. Answers at the bottom.

---

**1.** A service adds a liveness probe that calls `/health`, which checks the database.
The database has a 90-second blip. Describe what happens to the service, and why it is
worse than having no liveness probe.

**2.** Your app takes 60 seconds to warm up. Someone sets
`livenessProbe.initialDelaySeconds: 90`. What is wrong with that, and what should they have
used?

**3.** A Pod is `1/1 Running` with `RESTARTS: 14`. A different Pod is `0/1 Running` with
`RESTARTS: 0`. Which probe is involved in each, and which one is receiving traffic?

**4.** Explain why `timeoutSeconds: 1` on a liveness probe can take down a healthy service
under load. Walk through the cascade.

**5.** A container has `requests.memory: 256Mi`, `limits.memory: 512Mi`, and no CPU limit.
What QoS class is the Pod, when will the kernel kill it, and when will the kubelet evict it?

**6.** A node shows 95% of CPU **requested** and 4% CPU **used**. New Pods will not
schedule. Explain to a colleague why this is working correctly, and what to change.

**7.** You set `podAntiAffinity` with `requiredDuringScheduling` on hostname and scale to 5
replicas on a 3-node cluster. What happens? What should you have used?

**8.** Your HPA shows `TARGETS: <unknown>/70%` and never scales. Give the two causes, in the
order you would check them.

**9.** A node upgrade hangs on `kubectl drain`. The message mentions a disruption budget.
Two of your services are involved: one has 6 replicas and `minAvailable: 50%`, the other
has 1 replica and `minAvailable: 1`. Which is blocking, and what is the fix?

---

## Answers

**1.** Every Pod's liveness probe fails at once, the kubelet kills and restarts every
container, and the fleet comes back cold - empty caches, new connections - hammering the
database that was already struggling. A partial degradation becomes a total outage with a
thundering herd. With no liveness probe the Pods would have returned errors for 90 seconds
and recovered on their own. **Liveness probes must never check dependencies.**

**2.** It delays detection of a genuine hang by 90 seconds forever, and it is fragile: a
slow day pushes startup past 90s and the container is killed mid-boot, in a loop that looks
exactly like a crash. Use a **startupProbe** - while it is failing, liveness and readiness
are suspended - with a generous `failureThreshold`, then keep liveness tight.

**3.** The first has a failing **liveness** probe (or a crashing process) - it is being
restarted repeatedly, but it is currently Ready, so it *is* receiving traffic. The second
has a failing **readiness** probe: the container is running fine, has never been restarted,
and is receiving **no** traffic because it is not in any EndpointSlice.

**4.** Under load the health endpoint takes 1.2s. The probe times out; after
`failureThreshold` consecutive timeouts the container is killed. Its traffic shifts to the
remaining Pods, which get slower, so their probes time out too, and the cluster restarts
your service one Pod at a time under load it can no longer handle. Health endpoints must be
cheap, and timeouts must have headroom.

**5.** **Burstable** (requests set, and lower than limits). The **kernel** OOM-kills the
container the moment it exceeds its own 512Mi limit, regardless of how much memory the node
has free. The **kubelet** evicts it only when the *node* is under memory pressure, and it
evicts BestEffort Pods first, then Burstable Pods that are exceeding their requests.

**6.** Scheduling is based on **requests** - reservations - not on usage. The node has
promised 95% of its CPU to Pods that are not using it, so there is nothing left to promise.
Nothing is malfunctioning. The fix is right-sizing: measure real usage and lower the
requests toward the p50, keeping limits for the peaks.

**7.** Three Pods schedule, one per node, and two stay `Pending` forever - `required`
anti-affinity is a hard filter, and there are only three topology domains. Use
`topologySpreadConstraints` with `maxSkew: 1` and `whenUnsatisfiable: ScheduleAnyway`,
which expresses *balance* and degrades gracefully, or `preferredDuringScheduling`
anti-affinity.

**8.** First: is **metrics-server** installed and healthy (`kubectl top nodes`)? Second:
does the container have a **CPU request**? Utilisation is a percentage *of the request*, so
with no request there is no denominator and the HPA reports `<unknown>` forever.

**9.** The **single-replica** service with `minAvailable: 1`: evicting its only Pod would
breach the budget, so the drain waits indefinitely. The 6-replica service can lose up to 3.
Fixes: run at least 2 replicas, or express the budget as `maxUnavailable: 1`, or accept
that a single-replica workload has no availability guarantee and set no PDB for it. A PDB
on one replica is a deadlock, not a protection.
