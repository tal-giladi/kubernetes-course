# 20 - SecurityContext, Pod Security Admission and NetworkPolicy

*Module 06 - Security and multi-tenancy, lesson 3 of 3. Exercise 20 of 25.*

Three independent controls, three different attackers. `securityContext` limits what a
container can do *on its node*. Pod Security Admission stops non-compliant Pods from being
created at all. NetworkPolicy limits what a compromised Pod can *reach*. You want all
three, and by default you have none of them.

## securityContext: what the container may do

Two levels - Pod-wide and per-container, with the container winning:

    spec:
      securityContext:                     # Pod level
        runAsNonRoot: true
        runAsUser: 1654
        runAsGroup: 1654
        fsGroup: 1654                      # chowns mounted volumes to this group
        seccompProfile: { type: RuntimeDefault }
      containers:
        - name: hello
          securityContext:                 # container level
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]

What each one buys you:

  - **`runAsNonRoot: true`** - the kubelet refuses to start the container if the image's
    user resolves to uid 0. Container root is not host root (user namespaces aside), but
    it is one kernel bug away from mattering.
  - **`allowPrivilegeEscalation: false`** - sets `no_new_privs`. setuid binaries inside the
    container cannot gain privileges. Almost never breaks anything.
  - **`capabilities: drop: ["ALL"]`** - containers get ~14 capabilities by default,
    including `CAP_NET_RAW` (packet sniffing, ARP spoofing). Drop them all and add back
    only what you need (`NET_BIND_SERVICE` if you must bind port 80 - or better, listen on
    8080 and let the Service map it).
  - **`readOnlyRootFilesystem: true`** - the strongest of the set. An attacker cannot drop
    a binary anywhere. Mount `emptyDir` volumes for the paths your app genuinely writes -
    usually just `/tmp`.
  - **`seccompProfile: RuntimeDefault`** - the container runtime's syscall filter. Cheap,
    and blocks a large class of kernel exploits.
  - **`privileged: true`** - the opposite of all of the above. It is effectively root on
    the node. Legitimate for some CNI and storage DaemonSets; never for an application.

## Pod Security Admission: enforcement, not advice

A `securityContext` you have to remember to write is a `securityContext` somebody will
forget. **PSA** is a built-in admission controller that enforces the Pod Security Standards
per namespace, configured entirely with labels:

    kubectl label ns lesson-20 \
      pod-security.kubernetes.io/enforce=restricted \
      pod-security.kubernetes.io/enforce-version=latest \
      pod-security.kubernetes.io/warn=restricted

Three profiles:

  - **privileged** - no restrictions. The default for every namespace, which is worth
    sitting with for a moment.
  - **baseline** - blocks the well-known escapes: privileged containers, host namespaces,
    hostPath, hostPort, most added capabilities.
  - **restricted** - baseline plus: must run as non-root, must drop ALL capabilities, must
    set `allowPrivilegeEscalation: false`, must set a seccomp profile, volume types
    limited.

Three modes, and you can use them together: `enforce` (reject), `audit` (log it),
`warn` (tell the person applying it). The migration path for an existing cluster is
`warn` + `audit` first, fix what shouts, then `enforce`.

PSA replaced PodSecurityPolicy, which was removed in v1.25. If you meet PSP in a document,
that document is old. For rules PSA cannot express, the ecosystem uses admission webhooks -
Kyverno or OPA Gatekeeper.

## NetworkPolicy: who may talk to whom

**By default, every Pod in the cluster can reach every other Pod, in every namespace.**
Flat, open, no firewall. A NetworkPolicy is a per-namespace, label-selected allow-list.

    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    spec:
      podSelector: {}              # {} = every Pod in this namespace
      policyTypes: [Ingress]       # with no ingress: rules below -> deny everything

Rules to hold on to:

  - Policies are **additive allow-lists**. There is no deny rule. Union of everything that
    selects the Pod.
  - **A Pod is "unselected" until some policy selects it.** An unselected Pod is wide
    open. The moment *any* policy selects it for Ingress, everything not explicitly
    allowed is denied. That is why the standard first move is a default-deny.
  - **Ingress and Egress are separate.** A default-deny on Ingress leaves outbound traffic
    untouched.
  - **They need CNI support.** Your kind cluster runs kindnet, which enforces them. Flannel
    (plain) does not - the objects apply cleanly and do nothing at all. Verify by testing,
    never by reading YAML.
  - **Careful with egress and DNS.** A default-deny egress policy blocks port 53 to
    CoreDNS, and every name lookup in the namespace fails. Always allow DNS explicitly.

The selector shapes are worth memorising, because the difference is subtle and dangerous:

    from:
      - podSelector: { matchLabels: { role: client } }        # this namespace only
      - namespaceSelector: { matchLabels: { team: web } }     # ALL Pods in those namespaces
      - namespaceSelector: {...}
        podSelector: {...}                                    # AND - one list item
      - ipBlock: { cidr: 10.0.0.0/8, except: [10.1.0.0/16] }

Two list items are an OR. One item with both selectors is an AND. A stray `-` widens your
policy enormously and looks almost identical on the page.

## Do this

In namespace `lesson-20`:

1. Turn on enforcement **before** deploying anything:

       kubectl create namespace lesson-20
       kubectl label ns lesson-20 \
         pod-security.kubernetes.io/enforce=restricted \
         pod-security.kubernetes.io/warn=restricted

2. Prove it bites. Try a perfectly ordinary Pod:

       kubectl -n lesson-20 run nope --image=nginx:1.29-alpine

   Rejected at admission, with a message listing every rule it broke -
   `allowPrivilegeEscalation != false`, `unrestricted capabilities`, `runAsNonRoot != true`,
   `seccompProfile`. Read the whole message; it is the specification, restated.

3. Deploy `hello` compliantly: 2 replicas, label `app=hello`, image `hello:1.1.0`, port
   8080 named `http`, plus a Service `hello` on port 8080. The Pod needs:

       runAsNonRoot: true, runAsUser: 1654
       seccompProfile: RuntimeDefault
       allowPrivilegeEscalation: false
       capabilities: drop ["ALL"]
       readOnlyRootFilesystem: true, with an emptyDir mounted at /tmp

   (1654 is the `app` user the .NET runtime images ship, and the reason this image was
   built non-root back in lesson 06.)

4. Two clients, so you can see a policy discriminate. Deployments `client-allowed`
   (label `role=client`) and `client-denied` (label `role=other`), both `busybox:1.37`
   running `sleep 3600` - and both needing the same restricted `securityContext`, because
   PSA applies to them too. Confirm both can reach the server *before* any policy:

       kubectl -n lesson-20 exec deploy/client-allowed -- wget -qO- -T3 http://hello:8080/
       kubectl -n lesson-20 exec deploy/client-denied  -- wget -qO- -T3 http://hello:8080/

5. Default-deny ingress for the namespace:

       NetworkPolicy `default-deny-ingress`: podSelector {}, policyTypes [Ingress]

   Now **both** clients time out. Note the failure mode: a timeout, not a refusal - the
   packets are dropped, so there is nothing to connect to and nothing in any log. This is
   what a NetworkPolicy problem looks like in production, and it is easy to mistake for a
   dead application.

6. Allow exactly one of them back:

       NetworkPolicy `allow-client`: podSelector app=hello, Ingress from
       podSelector role=client, port 8080

   `client-allowed` works again; `client-denied` still times out. Same Service, same DNS,
   same Pod - the difference is one label.

7. Optional, and the one that catches everyone: add a default-deny **egress** policy and
   watch every DNS lookup in the namespace fail. Then fix it by allowing UDP/TCP 53 to
   `kube-system`, and notice how much of a real policy is just plumbing.

## Hints

- `securityContext` at Pod level and container level are different objects with different
  allowed fields: `runAsNonRoot`/`fsGroup`/`seccompProfile` are Pod-level;
  `allowPrivilegeEscalation`/`readOnlyRootFilesystem`/`capabilities` are container-level.
  (`runAsUser` is valid in both.)
- If a Pod is rejected, the message names the exact field. Fix them one at a time.
- With `readOnlyRootFilesystem: true` you must mount something writable at `/tmp` or the
  runtime will fail on its first temp file.
- Test connectivity with a short timeout (`wget -T3`) - a denied connection hangs until it
  times out.
- `kubectl -n lesson-20 describe netpol default-deny-ingress` shows how the API server
  parsed your selectors, which is where OR-vs-AND mistakes become visible.

## Solution

See `lab/solutions/20/all.yaml`.
