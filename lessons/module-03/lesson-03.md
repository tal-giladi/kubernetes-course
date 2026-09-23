# 10 - Ingress and TLS

*Module 03 - Networking, lesson 3 of 3. Exercise 10 of 25.*

A Service of type NodePort gets traffic into the cluster on an ugly high port, one port
per service, with no hostnames, no paths and no TLS. That does not scale past the first
demo. **Ingress** is the L7 answer: one entry point, many hostnames and paths, TLS
terminated in one place.

## Two objects, and the split that confuses everyone

The `Ingress` object is only a **description of routing rules**. It does nothing on its
own. You must also run an **ingress controller** - a real proxy (ingress-nginx, Traefik,
HAProxy, Envoy-based ones) that watches Ingress objects and reconfigures itself.

    Ingress object     "shop.example.com/api -> svc api:8080"   (data)
    Ingress controller nginx, reading that and rewriting its config  (the thing that runs)

Apply an Ingress to a cluster with no controller and you get an object with an empty
`status.loadBalancer` and absolutely no error. It is the second-most common "why doesn't
this work" after selector mismatches.

`ingressClassName` says *which* controller should pick up this Ingress - a cluster can run
several (one internal, one internet-facing).

## How traffic actually arrives, in kind

    curl http://localhost/  (Windows)
      -> docker published port 80 on the k8s-lab-control-plane container
        -> the ingress-nginx Pod, which runs on that node with hostPort 80
          -> nginx matches Host + path against the Ingress rules
            -> the Pod IP of a backend Service's endpoint

Note the last step: ingress-nginx reads the Service's **EndpointSlice** and proxies
straight to Pod IPs. It does not go through the ClusterIP. So the Service still has to
exist with the right selector, but kube-proxy is out of the path.

The cluster you built has `ingress-ready=true` on the control-plane node and publishes
80/443 - that is what the two `extraPortMappings` in `lab/cluster/kind-config.yaml` were
for.

## The Ingress spec

    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: shop
      annotations:
        nginx.ingress.kubernetes.io/rewrite-target: /$1
    spec:
      ingressClassName: nginx
      tls:
        - hosts: [shop.localtest.me]
          secretName: shop-tls
      rules:
        - host: shop.localtest.me
          http:
            paths:
              - path: /
                pathType: Prefix
                backend:
                  service:
                    name: web
                    port:
                      name: http
              - path: /api
                pathType: Prefix
                backend:
                  service: { name: api, port: { name: http } }

`pathType` has three values and it matters:

  - `Prefix` - path segments, so `/api` matches `/api` and `/api/v1` but **not** `/apixyz`.
  - `Exact` - the whole path, case-sensitive.
  - `ImplementationSpecific` - whatever the controller wants. ingress-nginx treats it as a
    regex, which is how the old `/api/(.*)` rewrite recipes work.

Most path rules are one line of YAML and one line of annotation. **Annotations are where
Ingress stops being portable**: rewrites, body size, timeouts, auth, rate limits and CORS
are all controller-specific (`nginx.ingress.kubernetes.io/*` here). Rules are standard,
annotations are not. That gap is exactly what the newer **Gateway API** exists to close -
`GatewayClass`/`Gateway`/`HTTPRoute` make routing, headers, splits and redirects
first-class typed fields. It is the direction the ecosystem is moving; Ingress remains
what you will meet in every existing cluster.

## TLS

    kubectl create secret tls shop-tls --cert=tls.crt --key=tls.key

The Secret must be of type `kubernetes.io/tls`, live **in the same namespace as the
Ingress**, and contain `tls.crt` and `tls.key`. The controller terminates TLS and speaks
plain HTTP to your Pods (unless you annotate it to re-encrypt).

In production nobody hand-rolls this: **cert-manager** watches Ingress objects, requests
certificates from Let's Encrypt via ACME, writes the Secret and renews it. The mechanism
below the automation is still exactly this Secret.

An Ingress with a `tls` block also makes ingress-nginx redirect HTTP to HTTPS by default.
Turn that off with `nginx.ingress.kubernetes.io/ssl-redirect: "false"` when you are
testing over plain HTTP.

## Do this

1. Install the controller (the kind-specific manifest, which uses hostPort and the
   `ingress-ready` node selector):

       kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/kind/deploy.yaml
       kubectl -n ingress-nginx wait --for=condition=Ready pod \
         -l app.kubernetes.io/component=controller --timeout=180s

2. In namespace `lesson-10`, deploy two backends using the image you built in lesson 06:

       Deployment `web`  2 replicas, GREETING=web,  port 8080 named http, Service `web`
       Deployment `api`  2 replicas, GREETING=api,  port 8080 named http, Service `api`

3. Create a TLS Secret. A self-signed certificate is fine:

       MSYS_NO_PATHCONV=1 openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
         -keyout tls.key -out tls.crt \
         -subj "/CN=shop.localtest.me" -addext "subjectAltName=DNS:shop.localtest.me"
       kubectl -n lesson-10 create secret tls shop-tls --cert=tls.crt --key=tls.key

   `MSYS_NO_PATHCONV=1` is a Git Bash quirk, not a Kubernetes one: without it Git Bash
   helpfully rewrites `/CN=shop.localtest.me` into `C:/Program Files/Git/CN=...` and
   openssl rejects it. You will hit this again with any tool that takes `/`-prefixed
   arguments.

   In PowerShell there is no such rewriting, so drop the prefix and use backticks for the
   line breaks:

       openssl req -x509 -nodes -newkey rsa:2048 -days 365 `
         -keyout tls.key -out tls.crt `
         -subj "/CN=shop.localtest.me" -addext "subjectAltName=DNS:shop.localtest.me"
       kubectl -n lesson-10 create secret tls shop-tls --cert=tls.crt --key=tls.key

4. Create an Ingress `shop` with `ingressClassName: nginx`, host `shop.localtest.me`,
   TLS via `shop-tls`, and two Prefix paths: `/` -> `web`, `/api` -> `api`.

5. Test it from Windows. `shop.localtest.me` is a public DNS name that resolves to
   127.0.0.1, so this works with no hosts-file editing - but pass the Host header
   explicitly so the test does not depend on DNS at all:

       curl -s -H "Host: shop.localtest.me" http://localhost/
       curl -s -H "Host: shop.localtest.me" http://localhost/api
       curl -sk -H "Host: shop.localtest.me" https://localhost/

   The first says `web`, the second says `api`, the third is the same over TLS.

   On Windows PowerShell 5.1, write `curl.exe` - there `curl` is an alias for
   `Invoke-WebRequest`, which does not understand `-s`, `-H` or `-k`. PowerShell 7 removed
   the alias, so `curl` is the real binary again.

6. Now poke at the failure modes, because these are the ones you will actually hit:

       # no Host header at all - no rule matches
       curl -s http://localhost/ ; echo
       # 404 from nginx itself, not from your app.

       # a path that does not match any rule
       curl -s -H "Host: shop.localtest.me" http://localhost/nope ; echo

       # what the controller thinks it is doing
       kubectl -n lesson-10 describe ingress shop
       kubectl -n ingress-nginx logs -l app.kubernetes.io/component=controller --tail=30

   `503` from nginx means the rule matched but the backend Service has no endpoints;
   `404` means no rule matched. Learning to tell those two apart saves hours.

## Hints

- The controller runs in its own namespace `ingress-nginx`. Your Ingress and its TLS
  Secret live in `lesson-10`.
- `kubectl -n lesson-10 create ingress shop --class=nginx --rule="shop.localtest.me/*=web:http"`
  generates most of it.
- If the Ingress `ADDRESS` column stays empty for more than a minute, the controller is
  not running or not watching your class.
- `openssl` ships with Git for Windows - it is on your PATH already.
- Backend port can be given by name (`port: {name: http}`) or number
  (`port: {number: 8080}`). The name must match the **Service** port's name.

## Solution

See `lab/solutions/10/`.
