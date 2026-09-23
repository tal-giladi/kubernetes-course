# 03 - Pods: the atom (and why you'll rarely write one)

*Module 01 - Foundations, lesson 3 of 3. Exercise 03 of 25.*

A **Pod** is the smallest thing Kubernetes schedules. It is *one or more* containers that:

  - are always placed on the **same node**,
  - share a **network namespace** - same IP, same port space, they reach each other on
    `localhost`,
  - can share **volumes**,
  - live and die **together**.

In Docker terms: a Pod is a `docker run --network=container:X` group with a shared
lifecycle. The shared IP is the part people miss. Two containers in one Pod cannot both
bind port 8080 - it is one port space.

Kubernetes creates a hidden "pause" container per Pod that owns the network namespace;
the others join it. That is why a container can crash and restart while the Pod keeps its
IP.

## Pods are mortal, and that is the point

A Pod is **never** repaired in place and **never** moves. If the node dies, the Pod is
gone - not rescheduled, gone. Something *else* (a Deployment) notices and creates a
**new** Pod with a new name and a new IP.

So: **you almost never write a bare Pod.** You write a Deployment, which owns a
ReplicaSet, which creates Pods. We write one by hand here exactly once, so the layers
above it stop being magic.

## Multi-container patterns

When you *do* put two containers in one Pod, it is one of these:

  - **sidecar** - a helper alongside the app: log shipper, proxy, cert refresher.
  - **init container** - runs to completion *before* the app containers start. Ordered,
    one at a time. Perfect for "wait for the DB" or "render config".
  - **ambassador / adapter** - a proxy that reshapes the app's network or output.

If the two things can scale independently, they are two Deployments, not two containers.

## The container spec, in Docker terms

    docker run                       ->  pod.spec.containers[]
      --name web                          name: web
      -e KEY=v                            env: [{name: KEY, value: v}]
      -p (host publish)                   (no equivalent - Services do this)
      --entrypoint                        command: []      <- overrides ENTRYPOINT
      (args after the image)              args: []         <- overrides CMD
      -v /data                            volumeMounts + volumes
      --restart                           restartPolicy (Always/OnFailure/Never)

`containerPort` is **documentation only**. It does not publish or firewall anything. A
container listening on 8080 is reachable on the Pod IP at 8080 whether or not you declare
it. Declare it anyway - Services and humans read it.

## Getting at a Pod

    kubectl -n NS logs POD                     # stdout of the (single) container
    kubectl -n NS logs POD -c NAME --previous  # the *crashed* instance's logs. Gold.
    kubectl -n NS exec -it POD -- sh           # docker exec
    kubectl -n NS port-forward POD 8080:80     # tunnel from your laptop into the Pod
    kubectl -n NS describe pod POD             # spec + status + Events

`--previous` is the single most useful flag in a crash loop: the running container has no
interesting logs, the *dead* one does.

## Pod phases and what they mean

    Pending     accepted, but not running yet -> unschedulable, or still pulling the image
    Running     at least one container is up
    Succeeded   all containers exited 0 and won't restart
    Failed      all containers terminated, at least one non-zero
    Unknown     the node stopped reporting

`Pending` almost always means "no node fits" (resources, taints, node selectors) or
"image still pulling". `describe` tells you which - read the **Events** at the bottom.

## Do this

Create namespace `lesson-03`, then write a Pod **from a YAML file** (not `kubectl run`):

  - name: `web`
  - namespace: `lesson-03`
  - label: `app=web`
  - one container named `nginx`, image `nginx:1.29-alpine`, containerPort 80
  - one **init container** named `seed`, image `busybox:1.37`, that writes the text
    `hello from init` into `/work/index.html`
  - an `emptyDir` volume shared by both: mounted at `/work` in the init container and at
    `/usr/share/nginx/html` in nginx

Then prove it works:

    kubectl -n lesson-03 port-forward pod/web 8080:80
    # in another terminal:
    curl http://localhost:8080

You should get `hello from init` - written by a container that had already exited before
nginx ever started. That is the init-container pattern in eight lines of YAML.

Also try, just to see them:

    kubectl -n lesson-03 get pod web -o wide          # its IP and node
    kubectl -n lesson-03 logs web -c seed             # the init container's output
    kubectl -n lesson-03 exec -it web -c nginx -- sh
    kubectl -n lesson-03 describe pod web             # read the Events list to the end

## Hints

- `kubectl run web --image=nginx:1.29-alpine --dry-run=client -o yaml` gives you a
  skeleton to edit. Generating YAML with `--dry-run=client -o yaml` is a habit worth
  having; nobody writes Kubernetes YAML from memory.
- Init containers go in `spec.initContainers`, same schema as `spec.containers`.
- The busybox command: `["sh","-c","echo 'hello from init' > /work/index.html"]`
- `emptyDir: {}` is a scratch volume that lives as long as the Pod.

## Solution

See `lab/solutions/03/pod.yaml`.
