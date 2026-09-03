# Module 03 quiz - Networking

Eight questions. Answers at the bottom.

---

**1.** `curl http://api:8080` from another Pod hangs and eventually times out. The `api`
Pods are `Running`. Give the single command you run first, the one line you read, and the
two possible causes.

**2.** Your gRPC service has 10 replicas behind a ClusterIP Service. One Pod is at 100% CPU
and the other nine are idle. Explain precisely why, and give two fixes.

**3.** What is the difference between these two, and when does it matter?

    ports: [{ port: 80, targetPort: 8080 }]
    ports: [{ port: 80, targetPort: http }]

**4.** A Pod resolves `api` instantly but `api.github.com` feels slow. What in
`/etc/resolv.conf` explains it, and what are two ways to avoid the cost?

**5.** You create a `LoadBalancer` Service on your kind cluster. `EXTERNAL-IP` says
`<pending>` after ten minutes. What is wrong?

**6.** You apply an Ingress and get 404 from nginx for every request. Then you fix that and
start getting 503. What was each problem?

**7.** A Service has `sessionAffinity: ClientIP` and `externalTrafficPolicy: Local`.
Explain what each does, and name the failure mode `Local` introduces.

**8.** Your team wants each Pod of a database StatefulSet addressable individually. Which
Service type, what exactly does DNS return, and what does the Service *not* do for you?

---

## Answers

**1.** `kubectl -n NS describe svc api`, and read the `Endpoints:` line. Empty endpoints
means either (a) the Service's selector does not match the Pods' labels, or (b) the Pods
match but are not **Ready**, and only Ready Pods are routed to. Note that neither case logs
an error anywhere - a Service with a wrong selector is a perfectly healthy Service.

**2.** kube-proxy load balances **connections**, not requests, and a gRPC client opens a
single long-lived HTTP/2 connection and multiplexes everything over it. That connection is
DNAT'd to one Pod once, and stays there. Fixes: a **headless Service** plus client-side
load balancing in the gRPC client, or an L7 proxy that speaks HTTP/2 (a service mesh /
Envoy). Periodically recycling connections is a weaker third option.

**3.** They resolve to the same port today. The named form refers to the container's
`ports[].name`, so if the application later moves from 8080 to 5000 you change only the
container spec and every Service pointing at it follows. The numeric form has to be found
and edited in every Service. Multi-port Services must name their ports regardless.

**4.** `options ndots:5` - any name with fewer than five dots is tried against every search
domain first, so `api.github.com` (two dots) issues several failing queries before the
correct one. Avoid it with a trailing dot (`api.github.com.`) or a per-Pod `dnsConfig`
lowering `ndots`.

**5.** Nothing. `LoadBalancer` asks the cloud provider for a load balancer, and there is no
cloud provider here. `<pending>` forever is the correct behaviour on kind. Use the NodePort
it also created, or install something like `cloud-provider-kind`/MetalLB to fake it.

**6.** **404** comes from the ingress controller itself: no rule matched - wrong `Host`
header, or a path that does not match any `pathType` rule. **503** means a rule *did*
match, but the backend Service has no endpoints - so it is question 1 again, one layer
further in. Learning to separate those two saves hours.

**7.** `sessionAffinity: ClientIP` pins a given source IP to the same backend Pod (default
3 hours), giving crude stickiness. `externalTrafficPolicy: Local` stops the node SNAT-ing
external traffic, so your application sees the real client IP - but it will only route to
Pods **on the node that received the packet**, so a node with no Pod of that Service
blackholes the traffic unless your load balancer's health checks stop sending to it.

**8.** A **headless** Service (`clusterIP: None`). DNS returns one A record per Ready Pod
instead of a single virtual IP, and with a StatefulSet each Pod additionally gets
`db-0.db.<ns>.svc.cluster.local`. What it does *not* do: any load balancing, any proxying,
any leader election, or any idea which replica is the primary. That is entirely your
application's problem.
