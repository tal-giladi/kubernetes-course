# 01 - The mental model: from Docker to Kubernetes

*Module 01 - Foundations, lesson 1 of 3. Exercise 01 of 25.*

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

## The words, before the commands

Five nouns carry the entire course. Nothing below is jargon you can skip - every later
lesson is one of these five getting more detailed.

**Cluster** - the whole thing: a set of machines that Kubernetes manages as one computer.
You do not address the machines. You talk to the cluster, and it decides where things go.

**Node** - one machine in the cluster. A VM, a bare-metal server, or - in this course - a
Docker container pretending to be a machine. A node contributes CPU, memory and disk to the
pool, and runs an agent (the kubelet) that starts containers when it is told to. Nodes are
deliberately boring and interchangeable: the whole design assumes one can die at any moment,
which is why you never care *which* node your application landed on. There are two kinds:

  - a **control-plane node** runs the cluster's brain - the components listed in the next
    section;
  - a **worker node** runs your applications. Ours has two of them.

**Pod** - the smallest thing Kubernetes will run. A Pod is a wrapper around **one or more
containers that are scheduled together, onto one node, and share a network identity**: one
IP address for the Pod, so the containers inside reach each other over `localhost`, and
shared directories if they want them. Nearly every Pod you will ever write has exactly one
container - so for now, read "Pod" as "your container, plus the paperwork Kubernetes needs".
The wrapper exists because occasionally one container genuinely cannot do the job alone: a
log shipper or a proxy that has to live and die with the app and see its filesystem. That
sidecar goes in the same Pod.

Two things about Pods that catch everyone arriving from Docker:

  - a Pod is **disposable**. It is never repaired, never moved, never restarted elsewhere.
    If its node dies, that Pod is gone, and a *different* Pod with a *new* name and a *new*
    IP is created somewhere else. Anything that must survive cannot live inside it.
  - you almost never write a Pod by hand. You write a **Deployment**, and its controller
    creates and replaces Pods for you. Lesson 03 has you write a bare Pod exactly once, so
    that you can watch it *not* come back.

**Container** - exactly what you already know. Same image, same registry, same layers. The
container is the only part of this stack that has not changed since Docker.

**Object** - anything Kubernetes stores and reconciles: a Pod, a Deployment, a Service, a
Namespace. You create objects by describing them in YAML and sending them to the API server.
They all share one shape, described two sections down.

So, top to bottom:

    cluster  ......... everything Kubernetes manages, as one computer
      |
      +-- node  ...... one machine (here: a Docker container on your laptop)
      |    |
      |    +-- pod  .. has its own IP, always lands on exactly one node
      |    |    |
      |    |    +-- container   <- your image
      |    |    +-- container   <- optional sidecar: same IP, same localhost
      |    |
      |    +-- pod
      |
      +-- node
      +-- node

And the same picture in the vocabulary you arrived with:

    docker run nginx                  ->  a Pod (created for you by a Deployment)
    docker run -d --restart=always    ->  a Deployment - a controller keeps it running
    the same container, three times   ->  replicas: 3 in one Deployment
    -p 8080:80 / a container name     ->  a Service: one stable name and IP for those Pods
    a named volume                    ->  a PersistentVolumeClaim
    an .env file                      ->  a ConfigMap (or a Secret)
    docker-compose.yml                ->  a folder of YAML, or a Helm chart (lesson 21)
    docker ps                         ->  kubectl get pods
    docker logs / exec / inspect      ->  kubectl logs / exec / describe

The right-hand column is the syllabus. You now know what every word in it means.

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

    source lab/env.sh          # bash, zsh, Git Bash
    . .\lab\env.ps1            # PowerShell - the leading dot is required

It writes `lab/.kubeconfig` (kind's own export - one cluster, one context), sets
`KUBECONFIG` for **this shell only**, and prints the context so you can see it. Your real
kubeconfig is never modified, and a new terminal is back to normal. Do this at the start of
every lab session. The grader (`bash lab/lab.sh check NN`, or `.\lab\lab.ps1 check NN`)
pins the context on every call regardless, so it can never grade - or damage - the wrong
cluster.

PowerShell has no `source` command, which is why there are two files. Its equivalent is
that lonely leading dot: `. .\lab\env.ps1` runs the script *in your shell*, so the
`KUBECONFIG` it sets survives. Run it without the dot and it works perfectly inside a child
process that then exits, taking the setting with it - the script tells you so rather than
letting you find out three commands later.

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
