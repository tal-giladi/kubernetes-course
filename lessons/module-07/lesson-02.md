# 22 - Kustomize

Helm templates YAML. Kustomize **patches** it. There are no `{{ }}`, no template language
and no runtime: you keep plain, valid, readable Kubernetes manifests as a *base*, and each
environment is an *overlay* that says what differs. It is built into `kubectl`, so there is
nothing to install.

    kubectl kustomize ./overlays/prod       # render to stdout
    kubectl apply -k ./overlays/prod        # render and apply
    kubectl diff -k ./overlays/prod         # what would change

## The shape

    base/
      kustomization.yaml
      deployment.yaml         <- ordinary, valid, apply-able YAML
      service.yaml
    overlays/
      dev/kustomization.yaml
      prod/
        kustomization.yaml
        resources-patch.yaml

The base is deployable on its own. That is the property people like: you can read it, lint
it, and apply it without a rendering step, and every overlay is a short diff rather than a
second copy.

## What an overlay can do

    apiVersion: kustomize.config.k8s.io/v1beta1
    kind: Kustomization

    namespace: lesson-22          # force every object into this namespace
    namePrefix: prod-             # and prefix every name (nameSuffix also exists)

    resources:
      - ../../base                # or URLs, or other overlays

    labels:
      - pairs: { env: prod }
        includeSelectors: false   # see the warning below

    images:
      - name: hello               # match by image name...
        newTag: "1.1.0"           # ...and replace the tag (or newName, or digest)

    replicas:
      - name: hello
        count: 3

    patches:
      - path: resources-patch.yaml            # strategic merge
      - target: { kind: Deployment, name: hello }
        patch: |                              # or an inline JSON 6902 patch
          - op: replace
            path: /spec/template/spec/containers/0/imagePullPolicy
            value: Always

Two patch styles:

  - **Strategic merge** - a partial manifest. Only the fields you mention change. Lists of
    containers merge by `name`, which is why a patch can set `resources` without erasing
    the image. Readable, and the default choice.
  - **JSON 6902** - `op/path/value`, for surgical edits and for lists that do not merge
    cleanly (`op: remove`, inserting at an index).

**`includeSelectors: false` matters.** With `true` (the old `commonLabels` behaviour),
Kustomize adds the label to `spec.selector.matchLabels` too - and a Deployment's selector
is **immutable**, so applying it over an existing Deployment fails with `field is
immutable`. Add labels to metadata, not to selectors.

## Generators, and the reason to use Kustomize at all

    configMapGenerator:
      - name: app-config
        literals: [GREETING=hello]
        files: [app.conf]
    secretGenerator:
      - name: db-creds
        literals: [DB_PASSWORD=hunter2]

The generated object's name gets a **content hash**: `app-config-9f8b2c4kd7`. And every
reference to `app-config` anywhere in the overlay - `configMapKeyRef`, a volume, an
`envFrom` - is rewritten to the hashed name automatically.

That solves lesson 11's problem exactly. Change a config value, the hash changes, the
ConfigMap name changes, the **Pod template** changes, and you get a rolling update for
free. No checksum annotation, no `rollout restart`, no forgetting. (Set
`generatorOptions.disableNameSuffixHash: true` to turn it off - and lose the property.)

The trade-off with `secretGenerator` is obvious: the literal is in git. Real setups
generate from a file that is not committed, or use Sealed Secrets / External Secrets and
keep Kustomize for the rest.

## Kustomize or Helm?

  - **Kustomize** - your own services, a handful of environments, teams who want to read
    plain YAML. No templating language to learn or debug.
  - **Helm** - distributing software to *other people*, conditional features, a package
    with a version and a lifecycle. Nobody ships a database to strangers as a Kustomize
    base.
  - **Both** - extremely common: `helm template` a third-party chart, then patch it with an
    overlay. Argo CD supports exactly this.

## Do this

1. Build a base in `lab/apps/kustomize/base` (or read the finished one in
   `lab/solutions/22/base`): a Deployment `hello` - 1 replica, image `hello:1.0.0`, port
   8080 named `http`, `GREETING` from a ConfigMap key, and the ConfigMap mounted at
   `/etc/hello` - plus a Service `hello`, plus a `kustomization.yaml` that lists both and
   declares a `configMapGenerator` named `app-config` with `GREETING=hello`.

   Confirm the base is a real, valid manifest on its own:

       kubectl kustomize lab/solutions/22/base

   Note the ConfigMap's hashed name, and that the Deployment already references the hashed
   name rather than the plain one.

2. Write a `prod` overlay that changes five things without touching the base:

       namespace: lesson-22
       namePrefix: prod-
       labels:      env=prod, includeSelectors: false
       images:      hello -> tag 1.1.0
       replicas:    hello -> 3
       patches:     a strategic-merge patch adding requests/limits
       configMapGenerator: app-config, behavior: merge, GREETING=shalom-prod

3. Render before applying - the whole point is that you can see the result:

       kubectl kustomize lab/solutions/22/overlays/prod

   Read it against the base. Everything is renamed, relabelled, re-tagged, scaled and
   patched - and the base file on disk is untouched.

4. Apply it:

       kubectl create namespace lesson-22
       kubectl apply -k lab/solutions/22/overlays/prod
       kubectl -n lesson-22 get deploy,svc,cm

5. Now watch the generator earn its keep. Change `GREETING=shalom-prod` to something else
   in the overlay and re-apply:

       kubectl apply -k lab/solutions/22/overlays/prod
       kubectl -n lesson-22 get cm
       kubectl -n lesson-22 rollout status deploy/prod-hello

   A **new** ConfigMap with a new hash, the Deployment's template updated to reference it,
   and a rolling update - all from editing one literal. Compare that with lesson 11, where
   the env var stayed stale until you restarted by hand.

   Then set it back to `shalom-prod` and re-apply, for the checker.

6. Old ConfigMaps accumulate; that is the known cost. `kubectl apply -k --prune` with a
   label selector is the (careful) cleanup path.

## Hints

- `kustomization.yaml` must be named exactly that.
- Paths in `resources:` are relative to the kustomization file; `../../base` from
  `overlays/prod`.
- If apply fails with `field is immutable`, you added a label to the selector - set
  `includeSelectors: false`.
- `kubectl kustomize` prints the rendered YAML and nothing else; pipe it to `less` or
  `grep` while you work.

## Solution

See `lab/solutions/22/`. To satisfy the checker:

    kubectl apply -k lab/solutions/22/overlays/prod
