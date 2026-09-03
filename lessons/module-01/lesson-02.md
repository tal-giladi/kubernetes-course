# 02 - kubectl and the object model

Lesson 01 said the API server *is* the system. This lesson is about talking to it well,
because for the next twenty-three lessons `kubectl` is your hands.

## Everything is a resource, and the URL proves it

Run any command with `-v=6` and watch the HTTP request underneath:

    kubectl -v=6 get pods -n kube-system

    GET https://127.0.0.1:PORT/api/v1/namespaces/kube-system/pods

That is the entire model:

    /api/v1/...                     the "core" group - Pod, Service, ConfigMap, Secret, Node, Namespace
    /apis/apps/v1/...               Deployment, ReplicaSet, StatefulSet, DaemonSet
    /apis/batch/v1/...              Job, CronJob
    /apis/networking.k8s.io/v1/...  Ingress, NetworkPolicy
    /apis/rbac.authorization.k8s.io/v1/...  Role, RoleBinding

`apiVersion: v1` means the core group. `apiVersion: apps/v1` means group `apps`,
version `v1`. When a tutorial's YAML fails with "no matches for kind", it is almost always
an `apiVersion` that moved between releases.

    kubectl api-resources          # every kind, its group, its short name, namespaced?
    kubectl api-versions           # every group/version this server serves

Note the SHORTNAMES column. `po`, `svc`, `deploy`, `rs`, `cm`, `ns`, `sa`, `pvc`, `ing`.
You will type these thousands of times.

## Namespaced vs cluster-scoped

`kubectl api-resources` has a `NAMESPACED` column. Nodes, PersistentVolumes,
StorageClasses, ClusterRoles and Namespaces themselves are **cluster-scoped** - `-n` means
nothing for them. Everything else lives inside exactly one namespace and is addressed as
(namespace, kind, name).

## explain is the manual, and it is generated from your cluster

Nobody memorises the schema. Ask the server:

    kubectl explain deployment
    kubectl explain deployment.spec.strategy
    kubectl explain deployment.spec.template.spec.containers --recursive | head -50

This is better than any website: it is the schema of *the version you are running*,
including any CRDs you install later.

## create vs apply vs edit vs patch

  - `kubectl create -f` - imperative. Fails if the object exists. Fine for one-offs.
  - `kubectl apply -f` - **declarative**, and the one you use in real life. It computes a
    diff against the last-applied state and PATCHes only what changed. Safe to re-run.
  - `kubectl edit` - opens the live object in an editor. Great for exploring, terrible as
    a habit: the change exists nowhere but the cluster.
  - `kubectl patch` - a surgical, scriptable change. Three merge types (`strategic`,
    `merge`, `json`); the default strategic merge understands how to merge *lists* of
    containers by name, which plain JSON merge does not.
  - `kubectl replace` - full overwrite. Requires `resourceVersion`. Rarely what you want.

Mixing `apply` and `edit` on the same object is how people end up with fields that
mysteriously refuse to change. Pick declarative and stay there.

    kubectl diff -f manifest.yaml     # what would apply actually change? Run this first.

## Generate YAML, never write it from scratch

    kubectl create deploy web --image=nginx --dry-run=client -o yaml > web.yaml
    kubectl create cm app-config --from-literal=k=v --dry-run=client -o yaml
    kubectl create secret generic db --from-literal=pw=s3cr3t --dry-run=client -o yaml

`--dry-run=client` builds the object locally and prints it. `--dry-run=server` sends it to
the API server for full validation and defaulting *without* persisting it - the better
choice when you want to know whether it would actually be accepted.

## Labels and selectors: the joins of Kubernetes

There are no foreign keys. Objects find each other through **labels**.

    metadata:
      labels:
        app: web
        tier: frontend
        env: prod

A Service selects Pods by label. A ReplicaSet owns Pods by label. A NetworkPolicy targets
Pods by label. Get labels wrong and everything silently selects nothing - the single most
common Kubernetes bug there is.

    kubectl get cm -l env=prod
    kubectl get cm -l 'env in (prod,staging),tier!=frontend'
    kubectl get cm -l '!temporary'                    # label absent
    kubectl get pods --show-labels
    kubectl label cm -l env=prod reviewed=true        # bulk-edit by selector
    kubectl get pods -L app,tier                      # labels as columns

**Labels** are for selection and must be short and low-cardinality. **Annotations** are for
data that tools and humans read but nothing selects on - change causes, checksums, ingress
configuration, "who owns this". If you find yourself putting a git SHA in a label, it
probably wants to be an annotation.

The community's recommended set (`app.kubernetes.io/name`, `/instance`, `/version`,
`/component`, `/part-of`, `/managed-by`) is what Helm and most tooling emit. Adopt it and
your dashboards group themselves.

## Output that you can script

    kubectl get pods -o wide
    kubectl get pods -o yaml
    kubectl get pods -o name
    kubectl get pods -o jsonpath='{.items[*].spec.nodeName}'
    kubectl get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName
    kubectl get pods --sort-by=.status.startTime
    kubectl get events --sort-by=.lastTimestamp        # burn this one in

## Field selectors, and `-w`

Labels are yours; **field selectors** query built-in fields:

    kubectl get pods --field-selector status.phase=Running
    kubectl get events --field-selector type=Warning
    kubectl get pods --field-selector spec.nodeName=k8s-lab-worker

`-w` / `--watch` streams changes as they happen; it is the same long-poll mechanism every
controller uses.

## Do this

Everything in namespace `lesson-02`, and use `--dry-run=client -o yaml` at least once so
the habit sticks.

1. Create the namespace.
2. Create four ConfigMaps, each with a single data key `owner` set to anything, labelled:

       cm-a    tier=frontend   env=prod
       cm-b    tier=frontend   env=dev
       cm-c    tier=backend    env=prod
       cm-d    tier=backend    env=dev

3. Prove selectors to yourself:

       kubectl -n lesson-02 get cm --show-labels
       kubectl -n lesson-02 get cm -l env=prod
       kubectl -n lesson-02 get cm -l 'env=prod,tier=backend'
       kubectl -n lesson-02 get cm -l 'tier in (frontend,backend),env!=dev'

4. In **one command**, using a label selector (not by name), annotate every production
   ConfigMap with `reviewed=true`. The dev ones must not get it.
5. Make `cm-d` **immutable**. Find the field yourself with `kubectl explain configmap`.
   Then try to change its data and read the error - that error is the whole point of the
   field.
6. For fun, look at what you built through the API's own eyes:

       kubectl -n lesson-02 get cm cm-a -o yaml
       kubectl -n lesson-02 get cm -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.env}{"\n"}{end}'

## Hints

- `kubectl -n lesson-02 create cm cm-a --from-literal=owner=tal`
- `kubectl -n lesson-02 label cm cm-a tier=frontend env=prod`
- Bulk annotate: `kubectl -n lesson-02 annotate cm -l env=prod reviewed=true`
- `immutable` is a **top-level** field on ConfigMap, a sibling of `data` - not inside
  `metadata` and not inside `spec` (ConfigMap has no `spec`). Patch it:
  `kubectl -n lesson-02 patch cm cm-d -p '{"immutable":true}'`
- An immutable ConfigMap cannot be made mutable again. Only deleted and recreated.

## Solution

    kubectl create namespace lesson-02
    for n in a b c d; do kubectl -n lesson-02 create cm cm-$n --from-literal=owner=tal; done
    kubectl -n lesson-02 label cm cm-a tier=frontend env=prod
    kubectl -n lesson-02 label cm cm-b tier=frontend env=dev
    kubectl -n lesson-02 label cm cm-c tier=backend  env=prod
    kubectl -n lesson-02 label cm cm-d tier=backend  env=dev
    kubectl -n lesson-02 annotate cm -l env=prod reviewed=true
    kubectl -n lesson-02 patch cm cm-d -p '{"immutable":true}'
