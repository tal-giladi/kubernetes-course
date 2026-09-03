# Course brief

## The learner

One specific person, and the course is written for them rather than for a generic
audience: a senior .NET backend engineer who has used Docker daily for years - builds
images, writes Dockerfiles and compose files, debugs containers - and has never run
Kubernetes. They own production services, so the questions they care about are
operational: what breaks, how would I know, and what do I do at 2am.

Assumed: Docker, the shell, YAML by osmosis, HTTP, TLS, DNS as a user, and enough
networking to know what a port is. Not assumed: any Kubernetes, any Go, any cloud
provider's managed offering.

## The outcome

By the end they can take a service they own, containerise it if it is not already, and run
it on a real cluster with the properties production demands: rolling updates that do not
drop requests, health that is checked rather than assumed, configuration and secrets kept
out of the image, storage that outlives a Pod, traffic that arrives over TLS on a real
hostname, resource limits that stop one workload eating a node, a security posture that is
enforced rather than documented, and a debugging routine that finds the cause in minutes.

They can also read someone else's cluster: `kubectl get`, `describe`, events, endpoints,
and the handful of status fields that actually explain a failure.

## The shape

**Interactive, not a book.** Twenty-five exercises, each graded by a script that inspects
the live cluster (`bash lab/lab.sh check NN`). A lesson is not complete because it was
read; it is complete because the cluster is in the required state. Every checker was
executed against a real cluster while the course was written - none of the exercises are
theoretical.

**A real cluster, locally.** `kind` runs a three-node Kubernetes cluster as Docker
containers: a control plane and two workers, with a real scheduler, real CNI, real taints
and real NetworkPolicy enforcement. Docker Desktop's single-node Kubernetes would hide half
the syllabus - you cannot teach scheduling, anti-affinity, topology spread, DaemonSet
tolerations or drains on one node.

**One application throughout.** A small ASP.NET minimal API (`lab/apps/hello`), built by
the learner in lesson 06, with endpoints designed for the syllabus: a slow readiness probe,
a liveness probe that can be told to start failing, a config dump, a CPU burner, a memory
hog, and a writable data path. Every later lesson deploys the same image with different
YAML - which is the point being taught.

**Failure first.** Almost every lesson breaks something deliberately: a Service selector
that matches nothing, an image that will not pull, a container that is OOMKilled, a Pod
that is unschedulable, a network policy that drops packets silently. The symptoms are the
curriculum; the YAML is just how you fix them.

## Constraints the design had to respect

  - **Windows 11 + Docker Desktop + Git Bash.** Every command in the course was run there,
    including the ones that need Git Bash workarounds (`//CN=` for openssl).
  - **The learner has a production AKS cluster in the same kubeconfig.** Lesson 01
    therefore starts with `source lab/env.sh`, which isolates the shell to a lab-only
    kubeconfig, and every grading script pins the context explicitly. No exercise can touch
    another cluster.
  - **Nothing permanent on the machine.** Two binaries in `~/bin`, one kind cluster, some
    images. `bash lab/cleanup.sh --all` removes all of it.

## Non-goals

Managed-cluster administration (AKS/EKS/GKE node pools, IAM), cluster installation and
etcd operations, service meshes, writing a controller in Go, and CKA/CKAD exam drilling.
Lesson 24 covers the CRD/controller *model* - enough to understand every operator you will
install - without turning into a Go course.
