# Kubernetes: from Docker to Mastery

**8 modules · 25 lessons · 25 graded exercises · 8 quizzes · 1 capstone**

A hands-on Kubernetes course for engineers who already know Docker. You do not read this
course — you run it. Every lesson ends in an exercise that is **graded against a live
three-node cluster** on your own machine, and none of the 25 checkers is theoretical: every
one was executed against a real cluster while the course was written.

---

## Start here

```bash
bash lab/lab.sh up          # create the 3-node kind cluster (~2 minutes)
source lab/env.sh           # point THIS shell at a lab-only kubeconfig
bash lab/lab.sh             # see where you are and what is next
```

Then open [`lessons/module-01/lesson-01.md`](lessons/module-01/lesson-01.md), do the
exercise at the bottom, and run:

```bash
bash lab/lab.sh check 01
```

`source lab/env.sh` is not optional ceremony. If you have ever run `az aks get-credentials`
or connected to a managed cluster, that context is sitting next to the lab one and tools
switch it behind your back. This isolates the shell to a kubeconfig containing only the lab
cluster; the grader pins the context on every call regardless.

| Command | What it does |
|---|---|
| `bash lab/lab.sh` | progress, cluster status, what is next |
| `bash lab/lab.sh check NN` | grade exercise NN against the live cluster |
| `bash lab/lab.sh hint NN` | a nudge, not the answer |
| `bash lab/lab.sh solve NN` | the solution manifests |
| `bash lab/lab.sh reset NN` | delete that exercise's namespace and start over |
| `bash lab/cleanup.sh --all` | remove every trace of this course from the machine |

---

## What you need

Docker, `kubectl`, and `kind` (plus `helm` from lesson 21). Windows 11 + Docker Desktop +
Git Bash is the environment everything was written and tested in; macOS and Linux work with
no changes except the two Git Bash workarounds noted in lessons 10 and 25.

The cluster is **three nodes** — one control plane, two workers — because half the syllabus
does not exist on a single node: scheduling, anti-affinity, topology spread, DaemonSet
tolerations, drains, and per-node storage all need somewhere else to go.

---

## Contents

### Lessons — `lessons/module-NN/lesson-NN.md`

| Module | Lessons | Title |
|---|---|---|
| 01 | 3 | Foundations — the mental model, kubectl, Pods |
| 02 | 4 | Running workloads — Deployments, rollouts, your own image, Jobs |
| 03 | 3 | Networking — Services, DNS, Ingress and TLS |
| 04 | 3 | Configuration and state — ConfigMaps, volumes, StatefulSets |
| 05 | 4 | Reliability — probes, resources, scheduling, autoscaling |
| 06 | 3 | Security — quotas, RBAC, Pod Security and NetworkPolicy |
| 07 | 2 | Packaging — Helm and Kustomize |
| 08 | 3 | Mastery — debugging, CRDs and operators, capstone |

Each lesson: the mechanism explained properly, a deliberate failure to watch, a graded
exercise, hints, and a full solution.

### Curriculum — `curriculum/`
[`course-outline.md`](curriculum/course-outline.md) and eight module plans with objectives,
dependencies and the misconceptions each module is written to break.

### Assessments — `assessments/`
Eight quizzes with full answer keys, weighted toward diagnosis and judgement rather than
recall. Sample: *"A service adds a liveness probe that checks the database. The database
has a 90-second blip. Describe what happens, and why it is worse than having no liveness
probe."*

### Lab — `lab/`
`lab.sh` (the grader), `cluster/kind-config.yaml`, `checks/` (25 checkers), `solutions/`,
`apps/hello` (the course's ASP.NET application), `apps/broken` (lesson 23's four broken
Deployments), `cleanup.sh`.

### Assets — `assets/`
[`kubectl-cheatsheet.md`](assets/kubectl-cheatsheet.md) and
[`glossary.md`](assets/glossary.md).

---

## How it is built

**One application throughout.** A small ASP.NET minimal API you build yourself in lesson
06, with endpoints designed for the syllabus: a readiness probe that is slow on purpose, a
liveness probe you can tell to start failing, a config dump, a CPU burner, a memory hog and
a writable data path. Everything after lesson 06 deploys the same image with different YAML
— which is the point being taught.

**Failure first.** Nearly every lesson breaks something deliberately, because the symptom
is what you will actually meet: a Service whose selector matches nothing and reports no
error; an image that is on the node and still will not pull; a container OOMKilled at
exactly its limit; a Pod that can never be scheduled; a NetworkPolicy that drops packets
with no log line anywhere. Lesson 23 hands you four broken Deployments and no explanation.

**Nothing hand-waved.** Where a mechanism matters, the course says what it actually does —
the `pod-template-hash`, the EndpointSlice, `ndots:5` and musl's search-domain behaviour,
the kubelet's projected token, Kustomize's content hash, the three-way merge in
`helm upgrade`.

---

## Cleaning up

```bash
bash lab/cleanup.sh --all
```

Deletes the cluster and its three containers, every image the course pulled or built, the
`kind` and `helm` binaries, and the PATH entry. It does not touch Docker, your other
containers and images, or your real kubeconfig.
