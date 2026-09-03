# Module 06 plan - Security and multi-tenancy

**Lessons 18-20. Prerequisite: module 05. Produces: a namespace that constrains what runs
in it, what it may consume, and what it may talk to.**

## Objectives

1. Bound a namespace's total consumption and give every Pod sane defaults automatically.
2. Grant a workload the minimum API access it needs, and prove the boundary without
   deploying anything.
3. Enforce a container security baseline at admission, and reduce the blast radius of a
   compromised Pod on the network.

## Lessons

### 18 - Namespaces, ResourceQuota and LimitRange
- **Concept**: what a namespace is and is not; quotas enforced at admission; the rule that
  a quota on `requests.cpu` makes requests *mandatory*; LimitRange as mutating admission
  supplying what the quota demands; the failure surfacing on the **ReplicaSet**, not the
  Pod; `scopeSelector`.
- **Example**: a Deployment template with no `resources`, and a Pod that has them - the
  clearest demonstration of mutating admission in the course.
- **Practice**: quota plus LimitRange, then break the quota three different ways and read
  each message, including the one that is only visible in `describe rs`.
- **Summary**: quota and LimitRange are a pair; one without the other is a trap.

### 19 - RBAC and ServiceAccounts
- **Concept**: authentication vs authorization; there is no User object; ServiceAccounts as
  the workload identity; Role/ClusterRole/RoleBinding/ClusterRoleBinding and the
  RoleBinding-to-ClusterRole combination that everyone should use; RBAC is additive with no
  deny; `list` reads full object content; projected short-lived tokens;
  `automountServiceAccountToken: false` as the correct default.
- **Example**: an in-Pod `wget` to the API server authenticating with the projected token,
  succeeding for pods and 403-ing for secrets.
- **Practice**: SA + Role + RoleBinding, then five `auth can-i --as=` predictions before
  running them.
- **Summary**: test a Role with `auth can-i` before wiring it to anything.

### 20 - SecurityContext, Pod Security Admission and NetworkPolicy
- **Concept**: the container-level controls and what each buys; PSA profiles and modes, and
  the migration path (`warn`/`audit` then `enforce`); PSP is gone; NetworkPolicies as
  additive allow-lists; "unselected means wide open"; Ingress and Egress independence; CNI
  support as a hard requirement; the DNS-blocking egress trap; the OR-vs-AND selector
  distinction that one hyphen changes.
- **Example**: an ordinary `nginx` Pod refused at admission, with the rule list as the
  error message.
- **Practice**: a restricted namespace, a compliant workload, two clients differing only by
  a label, a default-deny, and one allow rule that separates them.
- **Summary**: a NetworkPolicy failure is a timeout with no log line anywhere.

## Dependencies

18 -> 19 -> 20 in difficulty, though they are independent mechanisms. 20 requires the
non-root image built in 06 and reappears wholesale in the capstone.

## Misconceptions

- "A quota rejected my Deployment." (It accepted it; the ReplicaSet is what failed.)
- "Read-only access is harmless." (`list` on secrets returns their contents.)
- "Namespaces isolate the network." (They do not. Nothing does, until a policy says so.)
- "I can add a deny rule." (There is no deny in either RBAC or NetworkPolicy.)
- "The policy applied cleanly, so it works." (Only if the CNI implements it.)
