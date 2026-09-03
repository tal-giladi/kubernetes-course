# 06 - Your own image: build, load, deploy

Every lesson so far ran `nginx`. Real work runs *your* image, and the gap between
`docker run myapp` and `kubectl apply` is where most first days go wrong. This lesson
closes it, and gives you the application the rest of the course uses.

## The registry problem

`docker build` puts an image in **your laptop's** Docker daemon. A kind cluster's nodes
are separate containers with their own **containerd** image stores. They cannot see your
daemon. So this fails:

    docker build -t hello:1.0.0 .
    kubectl create deploy hello --image=hello:1.0.0
    # ErrImagePull - repository does not exist or may require 'docker login'

The Pod stayed `Pending`/`ErrImagePull` because the kubelet asked *Docker Hub* for an
image called `hello`, and Docker Hub has never heard of you.

Three ways out, and you should know all three:

1. **Push to a registry** the nodes can reach - Docker Hub, GHCR, ACR, ECR. What
   production does.
2. **`kind load docker-image`** - copies an image from your daemon straight into every
   node's containerd store. What local development does.
3. **Run a registry container** on the kind network and point the cluster at it. Best for
   a tight inner loop where you rebuild constantly.

We use (2).

    kind load docker-image hello:1.0.0 --name k8s-lab
    docker exec k8s-lab-worker crictl images | grep hello   # prove it landed

## imagePullPolicy - the trap

    Always         pull every time a container starts
    IfNotPresent   use the local copy if there is one
    Never          never pull; fail if it is not already on the node

The default is **`IfNotPresent`** - **except** when the tag is `:latest` (or omitted),
where the default flips to `Always`. So an image called `hello:latest` that you loaded
with `kind load` will still be fetched from Docker Hub and still fail. Two consequences:

  - In this lab, always tag your images with a real version. Never `latest`.
  - `IfNotPresent` plus a mutable tag means different nodes can run different code from
    the same tag, indefinitely, with nothing in the UI to tell you. **Tag immutably**, or
    pin by digest (`myapp@sha256:...`), which is the only truly reproducible form.

Rebuilding under the *same* tag is the classic "why is my fix not deployed": the tag did
not change, so the Pod template did not change, so the Deployment has nothing to roll out,
and even if it did, `IfNotPresent` finds the stale copy already on the node. Bump the tag.

## Private registries

A real registry needs credentials. They live in a Secret of type
`kubernetes.io/dockerconfigjson`, referenced by the Pod:

    kubectl create secret docker-registry regcred \
      --docker-server=myreg.azurecr.io --docker-username=x --docker-password=y

    spec:
      imagePullSecrets:
        - name: regcred

You can also attach it to a ServiceAccount so every Pod using that account inherits it -
usually the tidier choice (lesson 19).

## Reading the failure modes

    ErrImagePull        the pull failed once
    ImagePullBackOff    it failed repeatedly and Kubernetes is backing off (up to 5 min)
    InvalidImageName    the reference is not parseable
    CrashLoopBackOff    the image is fine; your process exits

`describe pod` and read the Events. "manifest unknown" means wrong tag; "unauthorized"
means missing or wrong `imagePullSecrets`; "no such host" means DNS or an air-gapped node.

## The course application

`lab/apps/hello` is a small ASP.NET minimal API. You will deploy it a dozen more times, so
it is worth knowing what it offers:

    GET /                 greeting, hostname (= Pod name), version, uptime
    GET /healthz          liveness - 200, unless FAIL_LIVENESS_AFTER_SECONDS is set
    GET /readyz           readiness - 503 until READY_AFTER_SECONDS has elapsed
    GET /config           env vars it received + every file under /etc/hello
    GET /data             appends to $DATA_DIR/log.txt and returns the file
    GET /crash            exits 1
    GET /burn?seconds=n   burns CPU
    GET /eat?mb=n         allocates memory

Environment: `APP_VERSION`, `GREETING`, `READY_AFTER_SECONDS`,
`FAIL_LIVENESS_AFTER_SECONDS`, `DATA_DIR`. It listens on **8080** and runs as a
**non-root** user.

Its Dockerfile is an ordinary two-stage .NET build. The first build pulls the SDK image
(~900 MB) and takes a couple of minutes; after that it is cached. `lab/cleanup.sh` removes
all of it.

## Do this

1. Build the image, twice, with two versions:

       cd lab/apps/hello
       docker build -t hello:1.0.0 .
       docker build -t hello:1.1.0 .

   The second build is fully cached and takes a second - the layers are identical, only
   the tag differs. That is exactly what most releases look like from Kubernetes' point
   of view: a new immutable name for a new artifact.

2. Load **both** into the cluster:

       kind load docker-image hello:1.0.0 --name k8s-lab
       kind load docker-image hello:1.1.0 --name k8s-lab

3. In namespace `lesson-06`, deploy it: Deployment `hello`, 3 replicas, label `app=hello`,
   container named `hello`, image **`hello:1.0.0`**, containerPort **8080** named `http`,
   `imagePullPolicy: IfNotPresent`, and env `APP_VERSION=1.0.0`, `GREETING=shalom`.
4. Prove it serves, and that each request may hit a different Pod:

       kubectl -n lesson-06 port-forward deploy/hello 8080:8080
       curl http://localhost:8080/

5. Feel the trap. Retag `hello:1.0.0` as `hello:latest`, load it, and deploy a second
   Deployment using `hello:latest`. Watch it fail:

       docker tag hello:1.0.0 hello:latest
       kind load docker-image hello:latest --name k8s-lab
       kubectl -n lesson-06 create deploy broken --image=hello:latest
       kubectl -n lesson-06 get pods                 # ErrImagePull / ImagePullBackOff
       kubectl -n lesson-06 describe pod -l app=broken | tail -20

   The image *is* on the node. The `:latest` tag flipped the policy to `Always`, so the
   kubelet went to Docker Hub anyway. Fix it without changing the image:

       kubectl -n lesson-06 patch deploy broken \
         -p '{"spec":{"template":{"spec":{"containers":[{"name":"hello","imagePullPolicy":"IfNotPresent"}]}}}}'

   Then delete the `broken` Deployment - the checker wants it gone, and so should you.
6. Roll `hello` forward to **`hello:1.1.0`** and set `APP_VERSION=1.1.0` to match.
   Confirm with `curl` that the version string changed.

## Hints

- `kind` must be able to see the image: `docker images hello` first.
- `--name k8s-lab` is required; without it kind looks for a cluster called `kind`.
- To set both image and env in one edit, just edit the manifest and `kubectl apply`.
- `kubectl -n lesson-06 set env deploy/hello APP_VERSION=1.1.0` also works.

## Solution

See `lab/solutions/06/deployment.yaml`.
