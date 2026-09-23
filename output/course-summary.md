# Course summary

**Kubernetes: from Docker to Mastery** — 8 modules, 25 lessons, 25 graded exercises,
8 quizzes, 1 capstone.

## In one paragraph

A hands-on Kubernetes course for an engineer who knows Docker and has never run
Kubernetes. It runs on a real three-node `kind` cluster on the learner's own machine, uses
one ASP.NET application throughout, and grades every lesson by inspecting the live cluster
rather than by asking questions. Nearly every lesson breaks something on purpose, because
the symptoms are the curriculum. It ends with a capstone that ships a two-tier application
behind TLS with probes, resources, storage, autoscaling, a disruption budget, enforced Pod
security and network policies — verified by 38 assertions including a live HTTP request
through a real Ingress.

## What makes it different from the documentation

1. **It is graded.** `bash lab/lab.sh check NN` - `.\lab\lab.ps1 check NN` in PowerShell -
   inspects real objects, real endpoints and
   real traffic. A lesson is complete when the cluster is in the required state, not when
   the page has been read.
2. **Three nodes, not one.** Scheduling, anti-affinity, topology spread, DaemonSet
   tolerations, drains and per-node storage cannot be taught on Docker Desktop's
   single-node Kubernetes.
3. **Deliberate failure in almost every lesson.** A Service selector that matches nothing
   and reports no error. An image on the node that still will not pull. An OOMKill at
   exactly the limit. A Pod that can never be scheduled. A NetworkPolicy that drops packets
   silently. `required` anti-affinity that pins two Pods in `Pending` forever.
4. **Written for one person's actual environment.** Windows 11, Docker Desktop, Git Bash —
   including the Git Bash `//CN=` openssl workaround and, in lesson 01, a kubeconfig
   isolation step because the learner has a production AKS cluster in the same file.
5. **The mechanisms, not the manifests.** `pod-template-hash`, EndpointSlices, `ndots:5`
   and musl's search-domain behaviour, projected ServiceAccount tokens, Kustomize's content
   hash, the three-way merge in `helm upgrade`.

## Coverage

Pods, Deployments, ReplicaSets, DaemonSets, Jobs, CronJobs, StatefulSets · Services
(all types, headless, EndpointSlices), CoreDNS, kube-proxy, Ingress, TLS · ConfigMaps,
Secrets, volumes, PVs, PVCs, StorageClasses · probes, resources, QoS, eviction, scheduling,
affinity, taints, topology spread, HPA, PDB · namespaces, ResourceQuota, LimitRange, RBAC,
ServiceAccounts, SecurityContext, Pod Security Admission, NetworkPolicy · Helm, Kustomize ·
debugging, CRDs, controllers, operators.

Deliberately out of scope: managed-cluster administration, installing Kubernetes,
etcd operations, service meshes, GitOps tooling, and writing controllers in Go.

## Verification

Every one of the 25 checkers was executed against a live cluster during authoring, and
every one passes against its solution. See [`verification-log.md`](verification-log.md).

## Time

Roughly 20-30 hours if the exercises are actually done, which is the only way the course
works. Modules 01-04 are the working minimum to run something in production;
05-06 are what make it survive; 07-08 are what make it maintainable.
