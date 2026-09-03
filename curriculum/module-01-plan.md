# Module 01 plan - Foundations

**Lessons 01-03. Prerequisite: Docker. Produces: a running cluster and a working vocabulary.**

## Objectives

1. Describe Kubernetes as a reconciliation loop rather than a command runner, and name the
   control-plane components and what each one does.
2. Drive `kubectl` deliberately: contexts, namespaces, `get/describe/explain`, output
   formats, labels and selectors, `apply` vs `create`.
3. Explain what a Pod is, why it is mortal, and why you almost never write one by hand.

## Lessons

### 01 - The mental model: from Docker to Kubernetes
- **Concept**: desired state vs actual state; `spec` vs `status`; the API server as the
  only door; static Pods and how the cluster bootstraps; contexts and the danger of a
  shared kubeconfig.
- **Example**: touring the cluster kind just built - `docker ps` showing nodes as
  containers, `kubectl get pods -A` showing the control plane running as Pods.
- **Practice**: a quiz submitted *as a ConfigMap*, so the first exercise is also the first
  object creation.
- **Summary**: you never start containers; you record wishes and controllers close the gap.

### 02 - kubectl and the object model
- **Concept**: resources as REST paths; API groups and versions; namespaced vs
  cluster-scoped; `explain` as the authoritative schema; the four write verbs and when each
  is right; labels as the system's only join mechanism; annotations as the place for
  everything you do not select on.
- **Example**: `kubectl -v=6` showing the HTTP request under a command.
- **Practice**: four ConfigMaps, labelled two ways, then a **selector-driven bulk
  annotate** that must hit exactly the production two, plus making one immutable.
- **Summary**: labels are load-bearing; getting them wrong is the most common bug in the
  system.

### 03 - Pods: the atom
- **Concept**: shared network namespace and lifecycle; the pause container; init
  containers and sidecars; the `docker run` to Pod-spec translation table; `containerPort`
  as documentation only; phases and what `Pending` really means.
- **Example**: an init container writing a file that nginx then serves.
- **Practice**: write that Pod from YAML - init container, `emptyDir`, two mount paths -
  and prove it with `port-forward`.
- **Summary**: a Pod is never repaired and never moves; everything above it exists because
  of that.

## Dependencies

01 -> 02 -> 03, strictly. Lesson 03's `emptyDir` returns in 12; its labels in 04 and 08.

## Misconceptions to hit head-on

- "A Pod is a container." (It is a *group* with one IP.)
- "`containerPort` publishes a port." (It documents one.)
- "Kubernetes restarts my Pod." (It creates a *new* one. Nothing is repaired.)
- "My kubeconfig only has the lab cluster in it." (Check. This is why lesson 01 isolates it.)
