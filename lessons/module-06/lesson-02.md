# 19 - RBAC and ServiceAccounts

Every request to the API server is **authenticated** (who are you?) and then
**authorized** (may you do this?). RBAC is the authorization half, and it is four objects
that fit together in a way that is much simpler than its reputation.

## Identities

  - **Users and groups** - for humans. Kubernetes has **no User object**: identity comes
    from outside - a client certificate's CN, an OIDC token's claims, a cloud IAM mapping.
    You cannot `kubectl create user`.
  - **ServiceAccounts** - for workloads. These *are* real namespaced objects. Every
    namespace has a `default` ServiceAccount, and every Pod runs as one whether you name it
    or not.

A ServiceAccount's identity string is `system:serviceaccount:<namespace>:<name>` - that is
what you put in a binding, and what `--as` impersonates.

## The four objects

    Role         verbs on resources, in ONE namespace
    ClusterRole  verbs on resources, cluster-wide (or on cluster-scoped kinds)
    RoleBinding        binds a Role (or a ClusterRole) to subjects, in ONE namespace
    ClusterRoleBinding binds a ClusterRole to subjects, cluster-wide

The combination people forget: a **RoleBinding referencing a ClusterRole** grants that
ClusterRole's permissions *only inside the binding's namespace*. That is how you reuse the
built-in `view` / `edit` / `admin` ClusterRoles per team without granting anything
cluster-wide. Use it constantly.

    rules:
      - apiGroups: [""]                     # "" is the core group
        resources: ["pods", "pods/log"]     # subresources are separate resources
        verbs: ["get", "list", "watch"]
      - apiGroups: ["apps"]
        resources: ["deployments"]
        resourceNames: ["hello"]            # optional: specific objects only
        verbs: ["get", "update"]

Verbs: `get list watch create update patch delete deletecollection`, plus non-resource
ones. Two rules that surprise people:

  - **RBAC is purely additive.** There is no `deny`. If a subject has any binding granting
    a verb, they have it. You reduce access by removing bindings, never by adding a denial.
  - **`list` implies reading every object's full content**, including Secrets' data.
    "Read-only" is not "harmless".

## The Pod's token

Since v1.24, ServiceAccounts have no permanent Secret. Instead the kubelet **projects** a
short-lived, audience-bound token into every Pod:

    /var/run/secrets/kubernetes.io/serviceaccount/token
    /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    /var/run/secrets/kubernetes.io/serviceaccount/namespace

It is rotated automatically and it is what client libraries pick up when they call
`InClusterConfig()`.

Which means: **any Pod that gets compromised has whatever its ServiceAccount can do.** The
`default` ServiceAccount usually has nothing, which is why the correct default is to turn
the token off entirely for workloads that never call the API:

    automountServiceAccountToken: false     # on the Pod spec, or on the ServiceAccount

Give a Pod its own ServiceAccount when it *does* call the API, and grant it the minimum.

## Debugging, which is genuinely easy

    kubectl auth can-i list pods -n lesson-19
    kubectl auth can-i --list -n lesson-19
    kubectl auth can-i get secrets -n lesson-19 \
      --as=system:serviceaccount:lesson-19:reader
    kubectl auth whoami

`--as` impersonation (which needs the `impersonate` verb, and you have it as
cluster-admin) answers "what can this ServiceAccount actually do" without deploying
anything. Get in the habit of testing a Role with `auth can-i` before wiring it to a
workload.

`kubectl api-resources` gives you the exact `apiGroups` and plural `resources` names that
RBAC rules require - guessing them is the usual reason a rule silently grants nothing.

## Do this

In namespace `lesson-19`:

1. A ServiceAccount `reader`.
2. A Role `pod-reader`: `get`, `list`, `watch` on `pods` and `pods/log` in the core group.
3. A RoleBinding `reader-can-read-pods` binding the ServiceAccount `reader` to that Role.
4. A Deployment `hello`, 1 replica, label `app=hello`, image `hello:1.1.0`, running under
   `serviceAccountName: reader`.

5. Test the boundary from outside, with impersonation. Predict each answer before you run
   it:

       SA=system:serviceaccount:lesson-19:reader
       kubectl auth can-i list   pods    -n lesson-19 --as=$SA     # yes
       kubectl auth can-i get    pods/log -n lesson-19 --as=$SA    # yes
       kubectl auth can-i delete pods    -n lesson-19 --as=$SA     # no
       kubectl auth can-i get    secrets -n lesson-19 --as=$SA     # no
       kubectl auth can-i list   pods    -n lesson-11 --as=$SA     # no - Roles are namespaced
       kubectl auth can-i --list -n lesson-19 --as=$SA

   The last one prints the complete grant. Note how small it is, and note that the
   namespace boundary comes for free with a RoleBinding.

6. Now use it for real, from inside the Pod. The token is already mounted:

       POD=$(kubectl -n lesson-19 get pod -l app=hello -o name | head -1)
       kubectl -n lesson-19 exec $POD -- sh -c '
         T=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token);
         wget -qO- --no-check-certificate --header="Authorization: Bearer $T" \
           https://kubernetes.default.svc/api/v1/namespaces/lesson-19/pods | head -c 200'

   A real, authorized API call made by your application with no credentials in any config
   file. Then try the same URL against `/api/v1/namespaces/lesson-19/secrets` and get a
   403 with a message naming the ServiceAccount and the missing verb.

7. Look at what a Pod gets by default, and turn it off:

       kubectl -n lesson-19 get pod -l app=hello -o jsonpath='{.items[0].spec.volumes[*].name}'
       kubectl -n lesson-19 run notoken --image=busybox:1.37 --restart=Never \
         --overrides='{"spec":{"automountServiceAccountToken":false,"containers":[{"name":"c","image":"busybox:1.37","command":["sleep","300"]}]}}'
       kubectl -n lesson-19 exec notoken -- ls /var/run/secrets/kubernetes.io/ 2>&1

   No token directory at all. That is the setting most workloads should have.

## Hints

- `kubectl -n lesson-19 create sa reader`
- `kubectl -n lesson-19 create role pod-reader --verb=get,list,watch --resource=pods,pods/log`
- `kubectl -n lesson-19 create rolebinding reader-can-read-pods --role=pod-reader --serviceaccount=lesson-19:reader`
- `serviceAccountName` is a **Pod spec** field, not a container field.
- If `auth can-i` says `no` for something you granted, check the plural resource name and
  the apiGroup with `kubectl api-resources | grep <thing>`.

## Solution

See `lab/solutions/19/all.yaml`.
