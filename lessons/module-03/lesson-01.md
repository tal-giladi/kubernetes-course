# 08 - Services and endpoints

Pods get IPs. Pods also get deleted constantly - you proved that in lesson 04, where a
deleted Pod came back with a different name *and* a different address. So a Pod IP is
never something to write down. A **Service** is the stable name in front of a changing set
of Pods.

    Service  (stable virtual IP + DNS name)
       |  selector: app=web
       v
    EndpointSlice  (the live list of Ready Pod IPs, maintained by a controller)
       |
       v
    Pods  (ephemeral)

## The Service does not know about your Deployment

It knows about **labels**. Nothing links a Service to a Deployment; they simply both
mention `app=web`. Say it twice, because it is the number one cause of "my Service returns
nothing": the selector does not match the Pod labels, the EndpointSlice is empty, and
connections hang or are refused with nothing in any log.

    kubectl -n lesson-08 describe svc web          # look at the Endpoints: line
    kubectl -n lesson-08 get endpointslices -l kubernetes.io/service-name=web

Empty endpoints has exactly two causes:

1. the selector matches no Pods, or
2. it matches Pods that are not **Ready**.

Only Ready Pods are routed to. That is not a detail - it is the entire basis of
zero-downtime rollouts, and the reason readiness probes matter (lesson 14).

(`Endpoints` was the original object; `EndpointSlice` replaced it because a Service with
5,000 Pods produced one enormous object that every node re-read on every change. You will
still see `kubectl get endpoints` in older docs, and it still works.)

## port vs targetPort vs nodePort

    ports:
      - name: http
        port: 80          # the Service listens here
        targetPort: http  # the port on the Pod - number, or the name of a containerPort
        nodePort: 30080   # NodePort/LoadBalancer only: the port opened on every node

Prefer a **named** `targetPort`. Then the app can move from 8080 to 5000 by editing only
the container spec, and every Service pointing at it follows. Multi-port Services must
name every port.

## The four types

**ClusterIP** (default) - a virtual IP reachable only inside the cluster. Ninety-five
percent of the Services you will ever write. The IP is not bound to any interface
anywhere; `kube-proxy` programs kernel rules on every node to rewrite packets destined for
it. Lesson 09 pulls that apart.

**NodePort** - everything ClusterIP does, plus the same port opened on **every** node in
30000-32767. Hit any node's IP on that port and you reach the Service, even if no Pod runs
on that node. Crude, ugly, and the mechanism underneath most ingress paths.

**LoadBalancer** - everything NodePort does, plus "ask the cloud for a real load balancer
pointing at those node ports". On kind there is no cloud, so `EXTERNAL-IP` stays
`<pending>` forever. That is expected, not broken. (`cloud-provider-kind` or MetalLB can
fake it if you want to see it work.)

**ExternalName** - no proxying and no endpoints at all: CoreDNS returns a CNAME to an
external hostname. Useful to give an outside dependency an in-cluster name, so config says
`db.prod.svc.cluster.local` in every environment and only the Service changes:

    spec:
      type: ExternalName
      externalName: my-db.database.windows.net

## A Service with no selector

Omit the selector and no controller manages the endpoints - you write them yourself. This
is how you put a Service name in front of something outside the cluster (a legacy VM, an
on-prem database) while the app keeps using ordinary service discovery. You create the
`EndpointSlice` object by hand with the real IPs.

## Headless, in one line

`clusterIP: None` disables the virtual IP entirely and makes DNS return **all** the Pod
IPs. That is lesson 09.

## Reaching a Service while you develop

    kubectl -n NS port-forward svc/web 8080:80     # laptop -> Service
    kubectl -n NS port-forward deploy/web 8080:80  # laptop -> one Pod of the Deployment

`port-forward` on a Service does not load balance across Pods; it picks one Pod and tunnels
to it. It is a debugging tool, not a proxy.

## Do this

In namespace `lesson-08`:

1. A Deployment `web`: 3 replicas, label `app=web`, image `nginx:1.29-alpine`, with the
   containerPort **named `http`** on port 80.
2. A **ClusterIP** Service `web`: `port: 80`, `targetPort: http`, selector `app=web`.
3. A **NodePort** Service `web-np`: same selector and ports, `nodePort: 30080`.
4. Confirm the endpoints are populated, and that the count matches the replica count:

       kubectl -n lesson-08 describe svc web
       kubectl -n lesson-08 get endpointslices -l kubernetes.io/service-name=web -o yaml

5. Call it from inside the cluster:

       kubectl -n lesson-08 exec deploy/web -- wget -qO- http://web

6. Reach the NodePort. It is **not** on your `localhost:30080` - kind only published 80
   and 443 from the control-plane container - so go in through a node:

       docker exec k8s-lab-worker  curl -s -m 5 http://localhost:30080
       docker exec k8s-lab-worker2 curl -s -m 5 http://localhost:30080

   Both answer, including from a node that may host no Pod at all.

7. **Break it on purpose.** This is the exercise that stops you losing an hour some day:

       kubectl -n lesson-08 patch svc web -p '{"spec":{"selector":{"app":"nope"}}}'
       kubectl -n lesson-08 describe svc web              # Endpoints: <none>
       kubectl -n lesson-08 exec deploy/web -- wget -qO- -T3 http://web   # hangs, then fails
       kubectl -n lesson-08 patch svc web -p '{"spec":{"selector":{"app":"web"}}}'

   Note what did *not* happen: no error, no event, no log line. A Service with a wrong
   selector is perfectly healthy from Kubernetes' point of view.

8. For completeness, create a `LoadBalancer` Service and watch it sit at `<pending>`, then
   delete it:

       kubectl -n lesson-08 expose deploy web --name=web-lb --type=LoadBalancer --port=80 --target-port=http
       kubectl -n lesson-08 get svc web-lb
       kubectl -n lesson-08 delete svc web-lb

## Hints

- `kubectl -n lesson-08 expose deploy web --name=web --port=80 --target-port=http`
- For the NodePort: `--type=NodePort` then patch or edit in the fixed `nodePort: 30080`,
  or just write the YAML.
- `nodePort` must be within 30000-32767 and unique across the cluster.
- A named `targetPort` refers to `ports[].name` on the **container**, not on the Service.

## Solution

See `lab/solutions/08/all.yaml`.
