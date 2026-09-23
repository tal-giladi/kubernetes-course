# Course outline

**Kubernetes: from Docker to mastery** - 8 modules, 25 lessons, 25 graded exercises, one
capstone. Roughly 20-30 hours if you actually do the exercises, which is the only way this
course works.

## Audience and prerequisites

See [`brief/course-brief.md`](../brief/course-brief.md). In short: you know Docker, you have
never run Kubernetes, and you own production services.

Required on the machine: Docker, `kubectl`, `kind`, and (from lesson 21) `helm`.
Setup is one command - `bash lab/lab.sh up`, or `.\lab\lab.ps1 up` in PowerShell.

## Design principles

1. **Every lesson is graded against a live cluster.** No lesson is "done" because you read
   it. `bash lab/lab.sh check NN` (PowerShell: `.\lab\lab.ps1 check NN`) inspects real
   objects and real traffic.
2. **Break it on purpose.** Each lesson includes a deliberate failure, because the symptom
   is what you will actually meet - a hanging Service, an `ImagePullBackOff`, an OOMKill, a
   silently dropped packet.
3. **One image, twenty-five configurations.** The application never changes after lesson
   06. Everything that changes is the YAML around it.
4. **Concepts arrive when they are needed**, not when they are adjacent. Probes come after
   you have watched a rollout succeed without them; taints come after a DaemonSet has
   quietly missed a node.
5. **Nothing hand-waved.** Where a mechanism matters - `pod-template-hash`, the
   EndpointSlice, `ndots:5`, the kubelet's projected token, kustomize's name hash - the
   course says what it actually does.

## Module map

| # | Module | Lessons | You can, afterwards |
|---|---|---|---|
| 01 | Foundations | 01-03 | Explain the control plane, drive `kubectl`, and read any object |
| 02 | Running workloads | 04-07 | Deploy, roll out, roll back, ship your own image, run batch work |
| 03 | Networking | 08-10 | Expose a service internally and to the outside world, over TLS |
| 04 | Configuration and state | 11-13 | Externalise config, persist data, run a stateful workload |
| 05 | Reliability | 14-17 | Make a service survive rollouts, load, node loss and its own bugs |
| 06 | Security and multi-tenancy | 18-20 | Constrain a namespace, a workload, and the network between them |
| 07 | Packaging and delivery | 21-22 | Ship the same app to many environments without copy-paste |
| 08 | Mastery | 23-25 | Debug anything, extend the API, and ship the whole thing |

## Lesson map

**Module 01 - Foundations**
1. The mental model: from Docker to Kubernetes - reconciliation, the control plane, contexts
2. kubectl and the object model - the REST API, labels and selectors, apply vs create
3. Pods: the atom - shared network namespace, init containers, phases

**Module 02 - Running workloads**
4. Deployments and ReplicaSets - self-healing, the template hash, ownership
5. Rollouts, rollbacks and rollout safety - maxSurge/maxUnavailable, history, stuck rollouts
6. Your own image: build, load, deploy - registries, `kind load`, the `:latest` trap
7. DaemonSets, Jobs and CronJobs - per-node agents, batch, schedules and concurrency

**Module 03 - Networking**
8. Services and endpoints - selectors, EndpointSlices, the four Service types
9. DNS, headless Services and kube-proxy - CoreDNS, `ndots`, per-connection balancing
10. Ingress and TLS - controllers, rules, path types, certificates

**Module 04 - Configuration and state**
11. ConfigMaps and Secrets - the four consumption modes, what refreshes and what does not
12. Volumes, PVs, PVCs and StorageClasses - dynamic provisioning, access modes, reclaim
13. StatefulSets - stable names, per-Pod storage, ordered lifecycle

**Module 05 - Reliability**
14. Probes: liveness, readiness, startup - and why a liveness probe is dangerous
15. Resources, QoS and eviction - requests vs limits, throttling, OOMKilled, Pending
16. Scheduling and placement - affinity, anti-affinity, topology spread, taints
17. Autoscaling and PodDisruptionBudgets - metrics-server, HPA behaviour, drains

**Module 06 - Security and multi-tenancy**
18. Namespaces, ResourceQuota and LimitRange - admission, defaults, the ReplicaSet event
19. RBAC and ServiceAccounts - Roles vs ClusterRoles, projected tokens, `auth can-i`
20. SecurityContext, Pod Security Admission and NetworkPolicy - enforce it, do not document it

**Module 07 - Packaging and delivery**
21. Helm - charts, values, releases, upgrade and rollback
22. Kustomize - bases and overlays, patches, the generator hash

**Module 08 - Mastery**
23. The debugging playbook - the symptom table, then four broken apps to fix
24. CRDs, controllers and operators - schema, status, reconcile loops, owner references
25. Capstone: ship a multi-tier application

## Assessment

  - **25 graded exercises**, one per lesson, run with `bash lab/lab.sh check NN` or
    `.\lab\lab.ps1 check NN`.
  - **8 quizzes**, one per module, in [`assessments/`](../assessments/) - written to test
    judgement and diagnosis rather than recall. Full answer keys.
  - **The capstone** (lesson 25) is the exam: 38 assertions across security, storage,
    networking, elasticity and a live HTTP request through a real Ingress.

## What this course does not cover

Managed cluster administration (node pools, cloud IAM), installing Kubernetes from
scratch, etcd operations, service meshes, GitOps tooling (Argo CD/Flux) beyond a mention,
and writing controllers in Go. Lesson 24 gives you the model those tools are built on.
