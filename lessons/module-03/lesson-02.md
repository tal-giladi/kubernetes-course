# 09 - DNS, headless Services and kube-proxy

*Module 03 - Networking, lesson 2 of 3. Exercise 09 of 25.*

Lesson 08 gave you a stable IP. This lesson is about the two things that make it usable: a
name that resolves to it, and the kernel machinery that makes packets to a fake IP arrive
at a real Pod.

## CoreDNS and the names you get

CoreDNS runs as a Deployment in `kube-system`, fronted by a Service called `kube-dns`
(the name is historical). Every Pod's `/etc/resolv.conf` is written by the kubelet to
point at it. Look inside a Pod:

    kubectl -n lesson-09 exec deploy/web -- cat /etc/resolv.conf

    nameserver 10.96.0.10
    search lesson-09.svc.cluster.local svc.cluster.local cluster.local
    options ndots:5

That `search` list is why a bare `web` works from a Pod in the same namespace, and why
`web.lesson-09` works from anywhere. The full form is:

    <service>.<namespace>.svc.cluster.local

`ndots:5` means any name with fewer than five dots is tried against every search domain
**first**, before being tried as-is. So a Pod resolving `api.github.com` (two dots) issues
four failing queries before the right one. It is a real, measurable latency cost in
chatty applications; the fix, when you care, is a trailing dot (`api.github.com.`) or a
per-Pod `dnsConfig` with a lower `ndots`.

Debugging DNS:

    kubectl -n lesson-09 exec deploy/web -- nslookup web
    kubectl -n lesson-09 exec deploy/web -- nslookup web.lesson-09.svc.cluster.local
    kubectl -n kube-system logs -l k8s-app=kube-dns --tail=50
    kubectl -n kube-system get cm coredns -o yaml       # the Corefile

If DNS is broken cluster-wide, check that CoreDNS Pods are Running *and* that the
`kube-dns` Service has endpoints. A CoreDNS crash loop takes everything with it and looks,
from the application's side, like every dependency failing at once.

## Headless Services: addressing individual Pods

    spec:
      clusterIP: None

No virtual IP, no kube-proxy rules, no load balancing. DNS returns **one A record per
Ready Pod**:

    nslookup web-headless
    Address: 10.244.1.5
    Address: 10.244.2.7
    Address: 10.244.1.6

You want this when the client must reach specific Pods rather than "any one of them":

  - **StatefulSets** (lesson 13), where each Pod additionally gets its own stable name,
    `web-0.web-headless.lesson-09.svc.cluster.local`.
  - **Databases with replicas** - a client that must write to the primary and read from
    the followers cannot use a Service that shuffles them.
  - **gRPC and any long-lived HTTP/2 client.** This is the classic production surprise: a
    ClusterIP Service load balances *connections*, not *requests*. A gRPC client opens one
    connection and multiplexes thousands of requests over it - so it pins to exactly one
    Pod, forever, and your other nine Pods sit idle while one is on fire. The fixes are a
    headless Service plus client-side load balancing, or a proxy that speaks HTTP/2 (a
    service mesh, or Linkerd/Envoy).

## kube-proxy: there is no proxy

The name is a lie left over from 2015. There is no process in the data path.

`kube-proxy` watches Services and EndpointSlices and writes **kernel rules** on every
node - iptables by default, IPVS or nftables optionally. A packet sent to a Service's
ClusterIP is DNAT'd by the kernel to one of the Pod IPs, and the reverse translation
happens on the way back. Nothing is copied to userspace. Go and look:

    docker exec k8s-lab-control-plane iptables-save | grep -c KUBE-
    docker exec k8s-lab-control-plane iptables-save | grep lesson-09

Consequences you can feel:

  - **Balancing is per-connection and random**, not round-robin. Ten `curl`s may not hit
    ten different Pods; a single long-lived connection never moves.
  - **The ClusterIP is not pingable.** It exists only as a rule. `ping` failing tells you
    nothing; use the actual port.
  - **Rule count grows with Services x endpoints.** At thousands of Services, iptables
    mode gets slow to *update* (it rewrites large chunks), which is why big clusters
    switch to IPVS or nftables.

Two spec fields worth knowing:

    sessionAffinity: ClientIP        # pin a source IP to a Pod (default timeout 3h)
    externalTrafficPolicy: Local     # NodePort/LB: only route to Pods on the receiving
                                     # node - preserves the client source IP, but a node
                                     # with no Pod blackholes traffic

`Cluster` (the default) always works but SNATs the packet, so your application sees a node
IP instead of the real client. `Local` preserves the client IP - the trade is that your
load balancer's health checks must be the thing that stops sending traffic to empty nodes.

## Pod DNS, and the other record types

Pods themselves get DNS entries too, though you rarely use them:
`10-244-1-5.lesson-09.pod.cluster.local`. StatefulSets are the exception that makes them
useful. `hostname` and `subdomain` on a Pod spec produce stable per-Pod names under a
headless Service - which is exactly the trick StatefulSets automate.

SRV records exist for named ports: `_http._tcp.web.lesson-09.svc.cluster.local`. Some
service-discovery libraries want them.

## Do this

In namespace `lesson-09`:

1. A Deployment `web`: 3 replicas, label `app=web`, image `nginx:1.29-alpine`,
   containerPort named `http` on 80.
2. A ClusterIP Service `web` (port 80 -> `http`).
3. A **headless** Service `web-headless`: `clusterIP: None`, same selector and ports.
4. A Service `web-sticky`: ClusterIP, same selector, but with
   `sessionAffinity: ClientIP`.
5. An **ExternalName** Service called `upstream` pointing at `example.com`.

Then look at the difference with your own eyes:

    kubectl -n lesson-09 exec deploy/web -- nslookup web
    kubectl -n lesson-09 exec deploy/web -- nslookup web-headless
    kubectl -n lesson-09 exec deploy/web -- nslookup upstream

One address, three addresses, a CNAME. Then:

    kubectl -n lesson-09 exec deploy/web -- cat /etc/resolv.conf
    kubectl -n lesson-09 get svc

Notice `web-headless` shows `CLUSTER-IP: None` and `upstream` shows no endpoints at all.

Finally, prove that balancing is per-connection. Give each Pod a distinct page and call
the Service ten times:

    for p in $(kubectl -n lesson-09 get pods -l app=web -o name); do
      kubectl -n lesson-09 exec $p -- sh -c 'hostname > /usr/share/nginx/html/index.html'
    done
    kubectl -n lesson-09 exec deploy/web -- sh -c 'for i in $(seq 10); do wget -qO- http://web; done'

Ten lines, unevenly distributed across three Pod names. Not round-robin - random.

## Hints

- ExternalName needs no selector and no ports:
  `kubectl -n lesson-09 create svc externalname upstream --external-name=example.com`
- For the headless one, `kubectl create svc clusterip web-headless --clusterip="None" --tcp=80:80`
  works, but you still need to add the `app: web` selector.
- `sessionAffinity` is a top-level field under `spec`, not inside `ports`.
- If `nslookup web-headless` returns one address, your selector is wrong or only one Pod
  is Ready.

## Solution

See `lab/solutions/09/all.yaml`.
