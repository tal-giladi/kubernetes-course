# Module 05 plan - Reliability

**Lessons 14-17. Prerequisite: module 04. Produces: a workload that survives rollouts,
load, node maintenance and its own bugs.**

## Objectives

1. Configure the three probes correctly, and justify *not* adding a liveness probe.
2. Set requests and limits deliberately, and explain QoS, throttling, OOMKill and eviction.
3. Place Pods with nodeSelector, affinity, anti-affinity, topology spread and tolerations,
   and recognise the traps in each.
4. Autoscale on CPU and protect availability during voluntary disruption.

## Lessons

### 14 - Probes
- **Concept**: readiness gates traffic, liveness kills containers, startup suspends both;
  why a liveness probe on a dependency turns a partial outage into a total one; the timing
  fields and the arithmetic of detection time; `timeoutSeconds: 1` as a self-inflicted
  outage; the SIGTERM/endpoint-removal race and `preStop`.
- **Example**: three Pods `Running 0/1` for twenty seconds with zero endpoints - the gap
  readiness exists to cover.
- **Practice**: a correctly probed Deployment plus a deliberately flapping one whose
  restart counter climbs forever.
- **Summary**: when in doubt, no liveness probe.

### 15 - Resources, QoS and eviction
- **Concept**: requests schedule, limits constrain; CPU is compressible and memory is not;
  QoS derived from the numbers and the eviction order; scheduling on reservations rather
  than usage; `FailedScheduling` as the most informative message in the system; the .NET
  runtime reading cgroup limits.
- **Example**: `Allocated resources` on a node showing it "full" while idle.
- **Practice**: three deployments differing only in numbers to produce all three QoS
  classes, plus a container OOMKilled on purpose and a Pod that can never be scheduled.
- **Summary**: no resources is not neutral - it is opting into being killed first.

### 16 - Scheduling and placement
- **Concept**: filtering and scoring; nodeSelector vs node affinity; `IgnoredDuringExecution`
  meaning checked once; pod anti-affinity and the `required`-with-too-many-replicas trap;
  topology spread as the modern answer; taints repel while tolerations only permit; the
  node lifecycle controller's own taints.
- **Example**: `required` anti-affinity leaving Pods `Pending` forever at replica 3.
- **Practice**: pin, spread, separate, taint and tolerate - then put the node objects back.
- **Summary**: tolerating is not preferring; you still need a selector to attract.

### 17 - Autoscaling and PodDisruptionBudgets
- **Concept**: the three autoscalers; metrics-server as a prerequisite; the HPA formula and
  its absolute dependence on a CPU *request*; `behavior` and asymmetric stabilisation; not
  setting `replicas` once an HPA owns a Deployment; voluntary vs involuntary disruption; PDB
  as a floor for drains; `minAvailable: 1` on one replica as a self-inflicted deadlock.
- **Example**: load driving replicas up in a minute, and five minutes of patience on the
  way down.
- **Practice**: install metrics-server, autoscale under real load, then drain a node
  against a PDB.
- **Summary**: `<unknown>` in an HPA means metrics-server or a missing request. Always.

## Dependencies

14 -> 15 -> 16 -> 17. 17 needs 15's requests. 16's taint work must be undone before the
node is left; the lesson says so and the checker runs before the cleanup step.

## Misconceptions

- "More probes is safer." (A liveness probe can restart a healthy fleet.)
- "The node is full, so it must be busy." (Requests, not usage.)
- "Anti-affinity is the way to spread replicas." (Topology spread is, usually.)
- "The HPA will scale down as fast as it scaled up." (Five minutes by default.)
- "A PDB protects me from `kubectl delete pod`." (It does not. Only from eviction.)
