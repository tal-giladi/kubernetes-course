# Module 07 plan - Packaging and delivery

**Lessons 21-22. Prerequisite: module 06. Produces: one application definition that ships
to many environments without copy-paste.**

## Objectives

1. Package an application as a Helm chart, install it, upgrade it, and roll it back.
2. Express environment differences as Kustomize overlays over a plain, deployable base.
3. Choose between the two - or combine them - with a defensible reason.

## Lessons

### 21 - Helm
- **Concept**: chart anatomy; `version` vs `appVersion`; releases as named installations;
  Go templating and the whitespace-control idioms that cause most chart bugs; values
  precedence and why `--set` does not scale; the release lifecycle; releases stored as
  Secrets holding the rendered manifest; `--atomic` and `--wait`; the three-way merge; CRDs
  and hooks being outside the lifecycle; rollback creating a new revision.
- **Example**: `helm template` rendering locally with no cluster - the habit that replaces
  debugging by installing.
- **Practice**: scaffold with `helm create`, point it at the course image, add one value of
  your own, install, upgrade, fail an upgrade with `--atomic`, roll back, and read the
  release Secrets with plain `kubectl`.
- **Summary**: render before you install; keep environment values in files, in git.

### 22 - Kustomize
- **Concept**: patching instead of templating; a base that is valid YAML on its own;
  overlay fields (`namespace`, `namePrefix`, `labels`, `images`, `replicas`, `patches`);
  strategic merge vs JSON 6902; `includeSelectors: false` and the immutable-selector
  failure; generators and the **content hash** that turns a config change into a rolling
  update automatically; the secretGenerator trade-off; the accumulation of old ConfigMaps.
- **Example**: the same base rendered as a prod overlay - renamed, relabelled, re-tagged,
  scaled and patched - with the base file untouched.
- **Practice**: build the overlay, render it, apply it, then change one literal and watch a
  new hashed ConfigMap trigger a rollout. Directly answers lesson 11's stale-env-var problem.
- **Summary**: Helm for software you distribute; Kustomize for services you own; both is
  normal.

## Dependencies

21 and 22 are independent of each other, both depend on modules 02-06 for the objects they
package. 22's generator hash is the resolution of a problem raised in lesson 11.

## Misconceptions

- "Helm is a package manager, so it is like apt." (It is a template renderer plus a release
  ledger. Nothing is installed on a node.)
- "`--set` is fine for production." (Untracked and unreviewable; a typo is silently ignored.)
- "Helm upgrade will overwrite my manual `kubectl edit`." (Sometimes. It depends on whether
  the chart mentions the field - which is worse than either answer.)
- "commonLabels is harmless." (It edits the immutable selector unless you say otherwise.)
- "Kustomize needs to be installed." (It is inside `kubectl` - `apply -k`.)
