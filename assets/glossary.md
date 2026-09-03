# Glossary

Definitions as this course uses them, with the lesson that introduces each.

**Admission controller** - code that runs inside the API server after authentication and
before persistence. *Mutating* controllers change the object (LimitRange filling in
defaults); *validating* ones accept or reject it (ResourceQuota, Pod Security Admission).
(18, 20)

**Annotation** - arbitrary metadata that nothing selects on: change causes, checksums,
controller-specific configuration. Contrast **label**. (02)

**API group** - the namespace of the REST API: `""` (core), `apps`, `batch`,
`networking.k8s.io`, ... The first half of `apiVersion`. (02)

**cgroup** - the kernel mechanism that enforces CPU and memory limits. Modern .NET reads it
to size the GC heap and `ProcessorCount`. (15)

**CNI** - the network plugin that gives every Pod a routable IP, and (if it implements it)
enforces NetworkPolicy. kind uses kindnet. (01, 20)

**ClusterIP** - a virtual IP with no interface behind it; kube-proxy programs kernel rules
that rewrite packets destined for it to a Pod IP. Not pingable. (08, 09)

**Context** - a (cluster, user, namespace) triple in your kubeconfig. The thing to check
before any destructive command. (01)

**Controller** - a loop that compares desired state with actual state and closes the gap.
The whole system is controllers. (01, 24)

**CRD** - CustomResourceDefinition. Registers a new kind: schema, storage, endpoint, RBAC,
`kubectl get`. Adds no behaviour by itself. (24)

**DaemonSet** - one Pod per node, automatically. No `replicas` field. (07)

**Deployment** - manages ReplicaSets over time; the object that gives you rolling updates
and rollback. (04, 05)

**EndpointSlice** - the live list of Ready Pod IPs behind a Service. When something does not
work, look here first. (08)

**Ephemeral container** - a container injected into a running Pod for debugging, sharing its
namespaces. `kubectl debug`. (23)

**Eviction** - the kubelet removing a Pod to reclaim node resources, or the eviction API
removing one for a drain. Distinct from an **OOMKill**, which is the kernel killing one
container. (15, 17)

**Finalizer** - a key that blocks deletion until a controller removes it; the reason an
object sits in `Terminating`. (13, 23, 24)

**Headless Service** - `clusterIP: None`. No virtual IP, no proxying; DNS returns every
Ready Pod IP. Required for StatefulSet identity. (09, 13)

**HPA** - HorizontalPodAutoscaler. Changes replica count from a metric. Needs
metrics-server and a CPU **request**. (17)

**Ingress** - routing rules for HTTP(S) by host and path. Inert without an **ingress
controller**. (10)

**Init container** - runs to completion before the app containers start; ordered, one at a
time. (03)

**Job / CronJob** - run-to-completion work, and a schedule for it. (07)

**kubelet** - the per-node agent that actually starts containers, runs probes, and projects
ServiceAccount tokens. (01)

**kube-proxy** - watches Services and writes kernel (iptables/IPVS/nftables) rules. There is
no proxy process in the data path. (09)

**Label** - a key/value on an object that other objects **select** on. The system's only
join mechanism. Getting one wrong is the most common bug in Kubernetes. (02)

**LimitRange** - per-container defaults and bounds within a namespace. Pairs with a
ResourceQuota. (18)

**NetworkPolicy** - a namespaced, label-selected allow-list for Pod traffic. Additive, no
deny, needs CNI support, and a denial looks like a timeout with no logs. (20)

**Node** - a machine (here, a Docker container) running kubelet, kube-proxy and a CNI. (01)

**OOMKilled** - the kernel killed a container for exceeding its own memory limit. Exit code
137. (15)

**Operator** - a CRD plus a controller that encodes how to run a specific thing. (24)

**Owner reference** - a pointer from a child object to its parent, used by the garbage
collector to cascade deletes. Replaces cleanup code. (04, 24)

**PSA** - Pod Security Admission. Enforces the Pod Security Standards (`privileged`,
`baseline`, `restricted`) per namespace, by label. Replaced PodSecurityPolicy. (20)

**PDB** - PodDisruptionBudget. A floor on availability during **voluntary** disruption
(drains, evictions). Ignored by `kubectl delete pod`. (17)

**Pod** - one or more containers sharing a network namespace and a lifecycle. The unit of
scheduling. Mortal, never repaired, never moved. (03)

**pod-template-hash** - the label a Deployment adds so two ReplicaSets with the same
selector do not steal each other's Pods; the middle segment of a Pod's name. (04)

**Probe** - `readinessProbe` (gate traffic), `livenessProbe` (restart the container),
`startupProbe` (suspend the other two while booting). (14)

**PV / PVC / StorageClass** - a real disk / a claim for one / the recipe that provisions it
dynamically. The workload names only the claim. (12)

**QoS class** - `Guaranteed`, `Burstable` or `BestEffort`, derived from requests and limits.
Decides eviction order. (15)

**Reconciliation** - reading current state and converging it toward desired state,
repeatedly and idempotently. Level-triggered, not event-driven. (01, 24)

**ReplicaSet** - keeps N Pods matching a selector alive. No concept of upgrades. (04)

**ResourceQuota** - a namespace-wide ceiling, enforced at admission. (18)

**Requests / limits** - what the scheduler reserves / what the kernel enforces. Scheduling
uses requests only; a node can be "full" while idle. (15)

**RBAC** - Role, ClusterRole, RoleBinding, ClusterRoleBinding. Purely additive; there is no
deny. (19)

**Service** - a stable name and virtual IP in front of Pods chosen by label. Types:
ClusterIP, NodePort, LoadBalancer, ExternalName, plus headless. (08)

**ServiceAccount** - the identity a Pod uses to call the API, delivered as a short-lived
projected token. Most workloads should have it turned off. (19)

**StatefulSet** - stable ordinal names, one PVC per Pod, ordered lifecycle. Gives identity,
not clustering. (13)

**Static Pod** - a Pod the kubelet reads from disk rather than from the API server; how the
control plane bootstraps. (01)

**Taint / toleration** - a node repelling Pods / a Pod being permitted on it. A toleration
permits, it does not attract. (07, 16)

**Topology spread constraint** - "balance my Pods across this topology key, with at most
this skew". The modern alternative to anti-affinity. (16)
