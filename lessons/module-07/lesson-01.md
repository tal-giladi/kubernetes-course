# 21 - Helm

By now you have written the same Deployment fifteen times with three fields different.
Twelve environments times four services is a lot of copy-paste, and copy-paste is where
drift lives. **Helm** is templated YAML plus a release lifecycle: one chart, many values,
and an `upgrade`/`rollback` that knows what it installed last time.

## The pieces

    mychart/
      Chart.yaml          name, version, appVersion, dependencies
      values.yaml         the defaults, and the chart's public API
      templates/          Go templates rendered into Kubernetes manifests
        deployment.yaml
        service.yaml
        _helpers.tpl      named template snippets, not rendered on their own
        NOTES.txt         printed after install
      charts/             vendored dependency charts

Two versions in `Chart.yaml` and they mean different things: `version` is the *chart's*
version, `appVersion` is the version of the software it deploys. Bump them independently.

A **release** is one installation of a chart into one namespace under a name. The same
chart can be installed many times side by side - that is why every resource name in a
well-written chart is derived from the release name.

## Templating, and the three objects you have

    {{ .Values.replicaCount }}          # from values.yaml, or --set / -f
    {{ .Release.Name }}                 # shop
    {{ .Release.Namespace }}
    {{ .Chart.Name }} / {{ .Chart.AppVersion }}
    {{ include "hello.fullname" . }}    # a named template from _helpers.tpl
    {{- if .Values.ingress.enabled }} ... {{- end }}
    {{ .Values.greeting | quote }}
    {{ toYaml .Values.resources | nindent 12 }}
    {{ required "an image tag is required" .Values.image.tag }}

The `{{-` and `-}}` forms trim whitespace, which is most of what goes wrong in a chart:
YAML is whitespace-sensitive and a template is not. `nindent` re-indents a whole block and
is the idiom for injecting a nested map like `resources`.

Never debug a chart by installing it. Render it:

    helm template shop ./hello --values prod.yaml     # render locally, no cluster
    helm install shop ./hello --dry-run --debug       # render + server validation
    helm lint ./hello

## Values precedence

Lowest to highest: the chart's `values.yaml`, then a parent chart's values for a
subchart, then each `-f file` in order, then `--set` / `--set-string`. Later wins.

`--set` looks convenient and hurts at scale: it is untracked, unreviewable, and easy to
mistype (a wrong key is silently ignored - it just adds an unused value). Keep environment
values in files, in git.

## The release lifecycle

    helm install shop ./hello -n lesson-21 --create-namespace
    helm upgrade shop ./hello -n lesson-21 -f prod.yaml
    helm upgrade --install shop ./hello -n lesson-21      # idempotent; what CI runs
    helm list -n lesson-21
    helm history shop -n lesson-21
    helm rollback shop 1 -n lesson-21
    helm get manifest shop -n lesson-21                   # what is actually installed
    helm get values shop -n lesson-21
    helm uninstall shop -n lesson-21

Helm 3 and later store release state in a **Secret** in the release's namespace, named
`sh.helm.release.v1.<release>.v<revision>`, holding a gzipped copy of the rendered
manifest. That is how `rollback` and `diff` work, and it means a release is visible with
plain kubectl:

    kubectl -n lesson-21 get secret -l owner=helm,name=shop

Useful flags: `--atomic` (roll back automatically if the upgrade fails), `--wait`
(block until resources are ready), `--timeout`.

## The parts that bite

  - **`helm upgrade` does a three-way merge** between the old manifest, the new manifest,
    and the live object. A field you changed with `kubectl edit` may survive an upgrade, or
    may be reverted - depending on whether the chart mentions it. Do not mix the two.
  - **CRDs in `crds/` are installed but never upgraded or deleted** by Helm, on purpose.
    Upgrading a CRD is a manual step.
  - **Hooks** (`helm.sh/hook: pre-upgrade`) run Jobs at defined points - migrations, mostly.
    They are not tracked as part of the release and are not rolled back.
  - **`helm uninstall` deletes everything in the release**, including PVCs unless the chart
    marks them with a `helm.sh/resource-policy: keep` annotation.
  - A rollback creates a **new revision**, exactly like `kubectl rollout undo`. Revision 3
    can be "the content of revision 1".

Helm is not the only answer - Kustomize (lesson 22) does overlays without templating - and
the two are routinely combined: `helm template` piped into a Kustomize overlay, or Argo CD
rendering both.

## Do this

`helm` is installed at `C:\Users\TalGiladi\bin\helm.exe`.

1. Scaffold a chart and read what you got:

       cd lab/apps/charts        # create this directory
       helm create hello

   `helm create` generates a full-featured chart. Skim `templates/deployment.yaml` and
   notice how little of it is literal: names, labels, image, resources and probes are all
   values.

2. Point it at our image and give it a knob of its own. In `values.yaml`:

       replicaCount: 2
       image:
         repository: hello
         tag: "1.1.0"
         pullPolicy: IfNotPresent
       greeting: shalom
       service:
         type: ClusterIP
         port: 8080

   In `templates/deployment.yaml`, set the container port to 8080 and add:

       env:
         - name: GREETING
           value: {{ .Values.greeting | quote }}
         - name: APP_VERSION
           value: {{ .Values.image.tag | quote }}

   (`helm create`'s generated probes point at `/` on the service port, which our app
   answers - so they work as generated.)

3. Render before you install. This is the habit that matters:

       helm template shop ./hello | head -40
       helm lint ./hello

4. Install it as release **`shop`** into namespace **`lesson-21`**:

       helm install shop ./hello -n lesson-21 --create-namespace --wait
       helm list -n lesson-21
       kubectl -n lesson-21 get all

   Note the resource names: `shop-hello`, derived from the release name. Install the same
   chart again as `shop2` and watch a second, independent copy appear - then remove it.

5. Upgrade with an override, without editing the chart:

       helm upgrade shop ./hello -n lesson-21 --set replicaCount=3 --wait
       helm history shop -n lesson-21
       kubectl -n lesson-21 get deploy

   Two revisions. Then upgrade again with a bad value and see `--atomic` protect you:

       helm upgrade shop ./hello -n lesson-21 --set image.tag=nope --atomic --timeout 60s

   It fails, and rolls itself back. `helm history` shows the failed revision *and* the
   rollback.

6. Roll back deliberately and look at what Helm actually stores:

       helm rollback shop 1 -n lesson-21
       helm history shop -n lesson-21
       kubectl -n lesson-21 get secret -l owner=helm,name=shop

   One Secret per revision. Then bring it back to the state the checker wants - the
   `greeting` value overridden to `shalom-helm` and 3 replicas:

       helm upgrade shop ./hello -n lesson-21 \
         --set replicaCount=3 --set greeting=shalom-helm --wait

## Hints

- If `helm` is not on your PATH, open a new terminal - the PATH entry was added when the
  course was set up.
- `helm create` writes probes and a ServiceAccount you do not have to change.
- To check what a running release believes: `helm get values shop -n lesson-21` and
  `helm get manifest shop -n lesson-21`.
- Template errors point at a line in the *rendered* output; `helm template --debug` prints
  it even when rendering fails.

## Solution

A ready-made chart is in `lab/solutions/21/hello/`. To satisfy the checker with it:

    helm upgrade --install shop lab/solutions/21/hello -n lesson-21 --create-namespace \
      --set replicaCount=3 --set greeting=shalom-helm --wait
