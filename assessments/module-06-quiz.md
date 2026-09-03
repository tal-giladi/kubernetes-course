# Module 06 quiz - Security and multi-tenancy

Eight questions. Answers at the bottom.

---

**1.** A namespace has a ResourceQuota with `requests.cpu: 2`. A developer applies a
Deployment with no `resources` block. `kubectl get deploy` shows it exists; `kubectl get
pods` shows nothing at all. Explain, and name the exact command that reveals the reason.

**2.** What is the difference between a ResourceQuota and a LimitRange, and why does using
one without the other usually go wrong?

**3.** Someone asks for "read-only access so they can debug". You grant a Role with `get`,
`list`, `watch` on `*` in the namespace. What have you actually given away?

**4.** Explain the difference between a RoleBinding that references a ClusterRole and a
ClusterRoleBinding that references the same ClusterRole. Which do you want for "the web
team are admins of their own namespace"?

**5.** A Pod is compromised through an application vulnerability. What determines how much
API access the attacker gains, and what is the single setting most workloads should have
that many do not?

**6.** You want to stop anyone deploying privileged containers in a namespace. Compare
writing it in each Pod's `securityContext` versus Pod Security Admission. Which is
enforcement?

**7.** Two Pods in the same namespace, one labelled `role=client`, one labelled
`role=other`. You apply a default-deny ingress policy and an allow rule for `role=client`.
The `role=other` Pod's request now hangs for 30 seconds and fails with a timeout, and there
is nothing in any log. Is this a bug? What would a *refused* connection have meant instead?

**8.** What is the difference between these two `from` blocks, and which mistake does the
difference cause?

    from:
      - namespaceSelector: {matchLabels: {team: web}}
      - podSelector: {matchLabels: {app: api}}

    from:
      - namespaceSelector: {matchLabels: {team: web}}
        podSelector: {matchLabels: {app: api}}

---

## Answers

**1.** The Deployment object was accepted - quotas apply to **Pods**. Its ReplicaSet then
tried to create Pods, and admission rejected them, because a quota that constrains
`requests.cpu` makes a CPU request **mandatory** on every container. The evidence is on the
ReplicaSet: `kubectl -n NS describe rs <name>` shows `FailedCreate: ... must specify
requests.cpu`. (`kubectl get events --sort-by=.lastTimestamp` also shows it.)

**2.** A ResourceQuota caps the **namespace's total** consumption and object counts, at
admission. A LimitRange applies **per container/PVC**: it fills in default requests and
limits (mutating) and enforces min/max (validating). Without the LimitRange, a quota on
requests rejects every Pod that omits them - which is question 1. Without the quota, a
LimitRange stops one Pod being absurd but lets a thousand of them exhaust the cluster.

**3.** Every Secret in the namespace, in full. `list` returns the objects' contents, and
Secrets are objects. "Read-only" is not "harmless" - scope the resources explicitly
(`pods`, `pods/log`, `deployments`) or use the built-in `view` ClusterRole via a
RoleBinding, which deliberately excludes Secrets.

**4.** A **RoleBinding** referencing a ClusterRole grants those permissions **only inside
the binding's namespace**. A **ClusterRoleBinding** grants them across the entire cluster.
For "admins of their own namespace" you want the first: a RoleBinding in `web` referencing
the built-in `admin` ClusterRole. It is the most useful combination in RBAC and the one
people forget exists.

**5.** Whatever its **ServiceAccount** is allowed to do - the projected token is sitting in
the container's filesystem, and any client library will pick it up. The setting most
workloads should have is `automountServiceAccountToken: false`, because most applications
never call the Kubernetes API at all. Where a Pod does need access, give it its own
ServiceAccount with a minimal Role rather than reusing `default`.

**6.** A `securityContext` is something each author must remember to write, so it is a
convention. **Pod Security Admission** rejects non-compliant Pods at the API server, per
namespace, via labels - nobody can forget it and nobody can opt out. That is enforcement.
Use both: PSA to enforce the floor, securityContext to satisfy it. For rules PSA cannot
express, use an admission webhook (Kyverno, Gatekeeper).

**7.** Not a bug - that is exactly what a NetworkPolicy does. Denied packets are
**dropped**, so the client waits for a TCP timeout and nothing is logged anywhere, because
nothing rejected anything. A *refused* connection (immediate `connection refused`) would
mean the packets arrived and nothing was listening - a wrong port or a dead process, not a
policy. Telling those two apart is the fastest way to categorise a connectivity problem.

**8.** The first is two list items - an **OR**: traffic from *any* Pod in a `team=web`
namespace, **or** from *any* Pod labelled `app=api` in this namespace. The second is one
item with both selectors - an **AND**: only Pods labelled `app=api` **in** a `team=web`
namespace. One stray hyphen turns a narrow rule into a very wide one, and the two look
almost identical on the page. `kubectl describe netpol` shows how the API server actually
parsed it.
