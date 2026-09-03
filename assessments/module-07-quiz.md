# Module 07 quiz - Packaging and delivery

Seven questions. Answers at the bottom.

---

**1.** What is the difference between `version` and `appVersion` in `Chart.yaml`, and when
would you bump one without the other?

**2.** A teammate debugs a chart by running `helm install` repeatedly and reading the
errors. Give them two better commands and say what each catches.

**3.** `helm rollback shop 1` succeeds. `helm history shop` now shows four revisions.
Explain why rolling back to revision 1 did not leave you *at* revision 1.

**4.** Someone fixed an incident with `kubectl edit deploy web` on a Helm-managed release.
What happens at the next `helm upgrade`, and why is the answer unsatisfying?

**5.** In Kustomize, what does the `configMapGenerator`'s name hash actually buy you? Tie
it to a specific problem from an earlier module.

**6.** You add `commonLabels: {env: prod}` to an overlay and `kubectl apply -k` fails with
`field is immutable`. What happened, and what is the fix?

**7.** Your team ships an internal service to four environments, and also runs a
third-party database that publishes a Helm chart. What do you use for each, and what does
the combination look like?

---

## Answers

**1.** `version` is the chart's own version - bump it whenever the templates or defaults
change. `appVersion` is the version of the software the chart deploys. You bump
`appVersion` alone when releasing a new build of the app with an unchanged chart, and
`version` alone when you fix a template bug or add a value without changing the image.

**2.** `helm template <release> ./chart -f values.yaml` renders locally with no cluster and
catches template and YAML errors; `helm install --dry-run --debug` additionally sends it to
the API server, so it catches schema violations, admission rejections (like PSA) and
conflicts. `helm lint` catches chart-structure problems. Debug by rendering, not by
installing.

**3.** `rollback` does not rewind the ledger - it **re-applies** an old manifest as a
**new** revision. So revision 4 contains the content of revision 1. This is the same
behaviour as `kubectl rollout undo`, and it means `helm history` is an append-only log of
what you did, not of what you had.

**4.** It depends on whether the chart's templates mention the field they edited. `helm
upgrade` performs a three-way merge of the previous manifest, the new manifest and the live
object: a field the chart does not mention may survive, and a field it does mention will be
reverted. The answer is unsatisfying because "it depends" is genuinely the answer - which is
why you should not mix `kubectl edit` with a release tool. Put the fix in the chart or its
values.

**5.** The generated ConfigMap's name includes a hash of its content, and every reference to
it in the overlay is rewritten to the hashed name. So changing a config value changes the
ConfigMap name, which changes the **Pod template**, which triggers a rolling update
automatically. That is the direct fix for lesson 11's problem: env vars are bound at
container start, so a plain ConfigMap edit leaves running Pods stale until someone
remembers to `rollout restart`.

**6.** The older `commonLabels` adds the label to `spec.selector.matchLabels` as well as to
metadata, and a Deployment's selector is immutable once created. Use the newer `labels:`
form with `includeSelectors: false` (or `labels` without selector inclusion), so the label
lands on metadata only.

**7.** **Kustomize** for the internal service: a plain, readable base plus four short
overlays, no templating language, and generator hashes handling config rollouts.
**Helm** for the third-party database, because that is how it is published and versioned.
The combination is routine - `helm template` the vendor chart and patch the output with a
Kustomize overlay (Argo CD supports exactly this), so you can adjust resources or labels
without forking someone else's chart.
