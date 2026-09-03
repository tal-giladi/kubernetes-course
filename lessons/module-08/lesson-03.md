# 25 - Capstone: ship a multi-tier application

No new concepts. This is the exam: build one application that uses everything, in one
namespace, from scratch. Give yourself a couple of hours and try to write it without
looking back at the earlier lessons - then look, and see what you forgot. What you forget
here is what you would forget in production.

## What to build

A two-tier application in namespace **`lesson-25`**, reachable from your browser at
`http://shop25.localtest.me/`, that would survive a node reboot, a bad deploy, a traffic
spike and a curious neighbour.

### 1. Namespace and posture
  - Namespace `lesson-25`, labelled to **enforce the `restricted`** Pod Security Standard.
  - A ServiceAccount `shop` for the app, with `automountServiceAccountToken: false` - it
    never calls the API.

### 2. Configuration
  - ConfigMap `shop-config` with `GREETING=shop` and an `app.conf` file.
  - Secret `shop-secret` with `DB_PASSWORD`.
  - The API reads `GREETING` from the ConfigMap and `DB_PASSWORD` from the Secret as env
    vars, and mounts the ConfigMap at `/etc/hello`.

### 3. The stateless tier
  - Deployment `api`: image `hello:1.1.0`, port 8080 named `http`, **3** replicas.
  - Probes: `startupProbe` and `livenessProbe` on `/healthz`, `readinessProbe` on
    `/readyz`, with `READY_AFTER_SECONDS=5` so you can watch readiness gate the rollout.
  - `resources`: requests **and** limits on cpu and memory.
  - A restricted `securityContext`: non-root, `allowPrivilegeEscalation: false`,
    all capabilities dropped, `seccompProfile: RuntimeDefault`,
    `readOnlyRootFilesystem: true` with an `emptyDir` at `/tmp`.
  - `topologySpreadConstraints` so replicas land on different nodes.
  - A `preStop` sleep and a sane `terminationGracePeriodSeconds`.
  - Service `api` (ClusterIP, port 8080 -> the named port).

### 4. The stateful tier
  - StatefulSet `db`: **2** replicas, image `hello:1.1.0` with `DATA_DIR=/data`, a
    `volumeClaimTemplates` entry `data` of 1Gi, and the same restricted securityContext.
  - A headless Service `db` (`clusterIP: None`) so `db-0.db` and `db-1.db` resolve.

### 5. Exposure
  - A TLS Secret `shop25-tls` for `shop25.localtest.me`.
  - Ingress `shop25`, `ingressClassName: nginx`, host `shop25.localtest.me`, TLS via that
    Secret, `/` routed to the `api` Service.

### 6. Elasticity and safety
  - HPA on `api`: min **2**, max **6**, CPU target 60%.
  - PodDisruptionBudget on `api`: `minAvailable: 2`.
  - NetworkPolicies:
      - `default-deny-ingress` for the whole namespace;
      - `allow-ingress-to-api` - from the `ingress-nginx` namespace to `api` on 8080;
      - `allow-api-to-db` - from Pods labelled `app=api` to Pods labelled `app=db` on 8080.

## Then prove it

Do not trust the YAML. Verify each property the way you would in an incident:

    # it serves, through the real ingress path
    curl -s  -H "Host: shop25.localtest.me" http://localhost/
    curl -sk -H "Host: shop25.localtest.me" https://localhost/

    # config and secret actually arrived
    kubectl -n lesson-25 exec deploy/api -- wget -qO- http://127.0.0.1:8080/config

    # the stateful tier has identity and its own disks
    kubectl -n lesson-25 get pods,pvc
    kubectl -n lesson-25 exec db-0 -- wget -qO- http://127.0.0.1:8080/data
    kubectl -n lesson-25 delete pod db-0
    kubectl -n lesson-25 exec db-0 -- wget -qO- http://127.0.0.1:8080/data    # same data

    # a rolling update keeps serving
    kubectl -n lesson-25 set env deploy/api APP_VERSION=2.0.0
    kubectl -n lesson-25 rollout status deploy/api
    # ...while, in another terminal:
    while true; do curl -s -o /dev/null -w '%{http_code} ' -H "Host: shop25.localtest.me" http://localhost/; sleep 0.3; done
    # all 200s. If you see 502s, your readiness probe or preStop hook is wrong.

    # the network policy is real
    kubectl -n lesson-25 run probe --rm -it --image=busybox:1.37 --restart=Never \
      --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":65532,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"probe","image":"busybox:1.37","command":["wget","-qO-","-T3","http://api:8080/"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
    # times out: an unlabelled Pod in the same namespace cannot reach the API.

    # a bad image does not take the service down
    kubectl -n lesson-25 set image deploy/api hello=hello:9.9.9
    kubectl -n lesson-25 get pods            # new Pods stuck, old Pods still serving
    kubectl -n lesson-25 rollout undo deploy/api

## Reflect

When it passes, ask yourself the questions the checker cannot:

  - If a node dies right now, what breaks, and for how long?
  - If `db-1`'s disk fills, what is the failure mode? Who finds out?
  - The HPA scales on CPU. Is CPU what actually limits this app? What would you scale on
    instead, and how would you feed that metric in?
  - A rollout goes out with a config change that only fails under real traffic. What in
    this manifest catches it, and what does not?
  - Where do the logs go when the Pod is gone?

Those five questions are the difference between "I can write Kubernetes YAML" and "I can
run this". Most of the answers are not more YAML.

## Hints

- Build it in pieces and apply as you go; do not write 300 lines then debug them at once.
- `kubectl apply --dry-run=server -f file.yaml` catches schema and admission errors -
  including PSA rejections - before anything runs.
- Under `restricted`, **every** Pod needs the securityContext, including the StatefulSet
  and any debug Pod you launch.
- Mint the TLS Secret the same way as lesson 10, with `//CN=` for Git Bash.
- If the Ingress returns 503, the Service has no endpoints. If it returns 404, the host or
  path did not match. If it times out, look at the NetworkPolicy.
- The `ingress-nginx` namespace has the label `kubernetes.io/metadata.name: ingress-nginx`,
  set automatically on every namespace - that is what your `namespaceSelector` should
  match.

## Solution

`lab/solutions/25/` - `all.yaml` plus `make-tls.sh`. Try to get there yourself first;
this one is worth the struggle.

    bash lab/solutions/25/make-tls.sh
    kubectl apply -f lab/solutions/25/all.yaml
