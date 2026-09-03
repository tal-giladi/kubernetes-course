# Module 03 plan - Networking

**Lessons 08-10. Prerequisite: module 02. Produces: an application reachable from the
browser over TLS.**

## Objectives

1. Diagnose an empty EndpointSlice - the single most common Kubernetes failure - in under a
   minute.
2. Choose between ClusterIP, NodePort, LoadBalancer, ExternalName and headless.
3. Explain what CoreDNS returns for each, and what kube-proxy does to a packet.
4. Route hostnames and paths through an Ingress controller, with TLS terminated at the edge.

## Lessons

### 08 - Services and endpoints
- **Concept**: Services select Pods by label and know nothing about Deployments;
  EndpointSlices; only *Ready* Pods are routed to; `port`/`targetPort`/`nodePort`; the four
  types; Services without selectors.
- **Example**: a NodePort answering on a node that hosts no Pod.
- **Practice**: build ClusterIP + NodePort, then patch the selector to something wrong and
  watch a perfectly healthy Service serve nothing, silently.
- **Summary**: when a Service does not work, look at endpoints first, always.

### 09 - DNS, headless Services and kube-proxy
- **Concept**: `/etc/resolv.conf`, the search list, `ndots:5` and its cost; headless
  Services returning every Pod IP; the gRPC/HTTP-2 single-connection trap; kube-proxy as
  kernel rules, not a process; per-connection random balancing; `sessionAffinity` and
  `externalTrafficPolicy`.
- **Example**: `nslookup` of a ClusterIP Service vs a headless one - one address vs three.
- **Practice**: four Services (ClusterIP, headless, sticky, ExternalName) and ten curls
  showing uneven, random distribution.
- **Summary**: the Service IP is a rule in the kernel, not a machine.

### 10 - Ingress and TLS
- **Concept**: the Ingress object is data, the controller is the program; `ingressClassName`;
  `pathType` semantics; annotations as the portability boundary, and Gateway API as the
  successor; TLS Secrets and cert-manager; how traffic reaches a kind cluster.
- **Example**: 404 (no rule matched) vs 503 (no endpoints) - the two answers that look the
  same and are not.
- **Practice**: install ingress-nginx, route `/` and `/api` to two backends, terminate TLS
  with a self-signed certificate, then probe both failure modes.
- **Summary**: one entry point, many hostnames, TLS in one place.

## Dependencies

08 -> 09 (headless only makes sense once ClusterIP does). 10 needs the `hello` image from
06 and returns in the capstone. The `ingress-nginx` install persists for lesson 25.

## Misconceptions

- "The Service is linked to my Deployment." (It is linked to labels.)
- "ClusterIP round-robins my requests." (It balances *connections*, randomly.)
- "LoadBalancer is broken on kind." (There is no cloud to ask; `<pending>` is correct.)
- "Applying an Ingress makes routing happen." (Not without a controller.)
- "I can ping the ClusterIP." (There is nothing there to ping.)
