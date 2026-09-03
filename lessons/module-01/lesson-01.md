# 01 - The mental model: from Docker to Kubernetes

You know Docker. So let's define Kubernetes in your terms:

    docker run             ->  you tell one machine to start one container, now.
    kubernetes             ->  you tell a cluster what should be true, forever.

That is the whole idea. Kubernetes is a **reconciliation loop**, not a command runner.
You submit a *desired state* ("3 copies of this image should be running, reachable at
this name"), and controllers spend the rest of their lives comparing desired state to
actual state and closing the gap. Nobody ever "starts" a container in Kubernetes the way
you do with `docker run`. You write down a wish, and a controller makes it true - and
keeps making it true after a node dies at 3am.

Everything else in this course is a variation on that sentence.

## Anatomy of the cluster you just built

`kind` built you a real Kubernetes cluster where each *node* is a Docker container
running on your laptop. That is the trick: containers-in-containers. Run `docker ps` and
you will see three of them.

    k8s-lab-control-plane   the brain
    k8s-lab-worker          a muscle
    k8s-lab-worker2         a muscle

The **control plane** runs four things worth knowing by name:

  - **kube-apiserver** - the only door into the cluster. `kubectl`, controllers, the
    kubelets, everything talks to this REST API and nothing talks to anything else.
    If you internalise one thing: *the API server is the system.*
  - **etcd** - a key/value store. The cluster's entire desired state lives here. Wipe
    etcd and the cluster has amnesia.
  - **kube-scheduler** - sees Pods that have no node assigned, picks a node for each.
    That is its whole job. It does not start anything.
  - **kube-controller-manager** - the reconciliation loops (Deployment controller,
    ReplicaSet controller, Node controller, ...). This is where "make it true" happens.

Each **node** (control plane included) runs:

  - **kubelet** - the agent that actually talks to the container runtime and starts
    containers. It watches the API server for Pods assigned to *its* node.
  - **kube-proxy** - programs the node's network rules so Service IPs work.
  - a **CNI plugin** (kind uses `kindnet`) - gives every Pod a real, routable IP.

## Objects, and the shape they all share

Every object in Kubernetes has the same four top-level fields:

    apiVersion:  which API group/version this object belongs to
    kind:        what type of object it is
    metadata:    name, namespace, labels, annotations
    spec:        what you want
    status:      what is actually true (written by controllers, never by you)

`spec` is your wish. `status` is reality. Learning Kubernetes is largely learning to read
`status` when it disagrees with `spec`.

## kubectl is a REST client

`kubectl` does nothing clever. It turns your command into an HTTP call against the API
server. These are worth burning into muscle memory:

    kubectl get <kind>                 list
    kubectl get <kind> <name> -o yaml  the full object, spec and status
    kubectl describe <kind> <name>     human summary + recent Events  <- your #1 debug tool
    kubectl explain <kind>.spec        the schema, straight from the API server
    kubectl api-resources              every kind this cluster knows about

Two flags that change your life:

    -A / --all-namespaces
    -o wide

## Contexts - which cluster am I about to break?

A *context* is (cluster + user + default namespace). Your kubeconfig can hold many.

    kubectl config get-contexts
    kubectl config current-context
    kubectl config use-context kind-k8s-lab

Get in the habit of checking `current-context` before any destructive command. The day you
have a work cluster in the same kubeconfig, this habit is the only thing between you and a
very bad afternoon.

**That day is probably today.** Run `kubectl config get-contexts` and look. If you have
ever run `az aks get-credentials`, connected to a managed cluster, or ticked Kubernetes on
in Docker Desktop, there is a second context sitting right next to `kind-k8s-lab`. Tools
switch the current context behind your back - an IDE plugin, a CI helper, a credential
refresh - and `kubectl delete namespace lesson-03` is a perfectly valid command against a
production cluster.

So this course does not rely on your discipline. Point your shell at a kubeconfig that
contains **only** the lab cluster:

    source lab/env.sh

It writes `lab/.kubeconfig` (kind's own export - one cluster, one context), sets
`KUBECONFIG` for **this shell only**, and prints the context so you can see it. Your real
kubeconfig is never modified, and a new terminal is back to normal. Do this at the start of
every lab session. The grader (`bash lab/lab.sh check NN`) pins the context on every call
regardless, so it can never grade - or damage - the wrong cluster.

## Namespaces

A namespace is a name-scoping boundary, not a security boundary by itself. Objects of the
same kind must have unique names *within* a namespace. Each lesson here gets its own
namespace (`lesson-01`, `lesson-02`, ...) so you can throw one away without touching the
others.

## Do this

1. Look around. Nothing here changes anything:

       docker ps
       kubectl get nodes -o wide
       kubectl get pods -A
       kubectl -n kube-system get pods
       kubectl describe node k8s-lab-worker
       kubectl explain pod.spec.containers
       kubectl api-resources | head -40

2. Notice that `kubectl get pods -A` shows Pods for the API server, etcd, the scheduler
   and the controller manager. The control plane runs *as Pods on Kubernetes itself*.
   Those specific ones are **static Pods** - the kubelet reads them off disk instead of
   from the API server, which is how the cluster bootstraps before the API server exists.
   Find their manifests:

       docker exec k8s-lab-control-plane ls /etc/kubernetes/manifests

3. Now answer the quiz. You submit answers *as a Kubernetes object* - a ConfigMap named
   `answers` in namespace `lesson-01`, with these four keys:

       nodes         = how many nodes are in the cluster (a number)
       apiserver     = the name of the component every other component talks to
       cni           = the name of the CNI plugin kind installed (lowercase, one word)
       desired-state = the field name that holds what you want (not what is true)

   Create the namespace, then create the ConfigMap with `--from-literal`.

## Hints

- `kubectl create namespace lesson-01`
- `kubectl -n lesson-01 create configmap answers --from-literal=nodes=... --from-literal=apiserver=... ...`
- The CNI's Pods are in `kube-system` and their name starts with `kindnet`.
- The four top-level fields are listed above; two of them are `spec` and `status`.

## Solution

    kubectl create namespace lesson-01
    kubectl -n lesson-01 create configmap answers \
      --from-literal=nodes=3 \
      --from-literal=apiserver=kube-apiserver \
      --from-literal=cni=kindnet \
      --from-literal=desired-state=spec
