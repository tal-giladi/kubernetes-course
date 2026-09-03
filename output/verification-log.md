# Verification log

Every exercise checker in this course was executed against a live three-node `kind`
cluster (Kubernetes v1.37.0, kind v0.33.0, Docker 29.7.2, Windows 11 + Git Bash) while the
course was written. All 25 pass against their solutions.

| # | Exercise | Verified by |
|---|---|---|
| 01 | The mental model | quiz ConfigMap with 4 correct answers |
| 02 | kubectl and the object model | 4 labelled ConfigMaps, a selector-scoped bulk annotate, an immutable ConfigMap |
| 03 | Pods: the atom | init container's file served by nginx over a shared `emptyDir` |
| 04 | Deployments and ReplicaSets | 5 Ready replicas, `pod-template-hash` present, a genuinely unowned ReplicaSet |
| 05 | Rollouts and rollbacks | revision ≥ 3, image back at 1.27, 2 ReplicaSets retained |
| 06 | Your own image | `hello:1.1.0` running from `kind load`, env applied, `broken` cleaned up, live HTTP response |
| 07 | DaemonSets, Jobs, CronJobs | DaemonSet on all 3 nodes via toleration, Job `succeeded: 3`, CronJob fired |
| 08 | Services and endpoints | 3 endpoints per Service, in-cluster HTTP, NodePort answered from inside a worker |
| 09 | DNS and headless Services | headless resolved to 3 addresses, ClusterIP to 1, ExternalName + sessionAffinity |
| 10 | Ingress and TLS | live `curl` for `/` and `/api` plus HTTPS through ingress-nginx on `localhost` |
| 11 | ConfigMaps and Secrets | env from ConfigMap and Secret, file mounted, all three read back from inside the container |
| 12 | Volumes and PVCs | checker deletes the Pod itself, then verifies the old line survived and the new Pod appended |
| 13 | StatefulSets | per-Pod PVCs, per-Pod DNS by FQDN, `db-1` deleted and its data re-attached |
| 14 | Probes | all three probes configured, preStop present, `flaky` restart count climbing |
| 15 | Resources and QoS | all three QoS classes observed, a real `OOMKilled`, a real `Unschedulable` |
| 16 | Scheduling | nodeSelector pin, 4 Pods spread 2/2, anti-affinity across 2 nodes, toleration onto a tainted node |
| 17 | Autoscaling and PDB | `kubectl top` working, HPA `ScalingActive=True`, PDB reporting healthy Pods |
| 18 | Quota and LimitRange | quota tracking usage; template with no resources, Pod with injected 100m/200m |
| 19 | RBAC | 5 `auth can-i --as=` assertions (2 allow, 3 deny), projected token present in the Pod |
| 20 | Security and NetworkPolicy | a plain nginx Pod rejected at admission; `role=client` reaches the API, `role=other` times out |
| 21 | Helm | release read from its storage Secrets, 2 revisions, templated value serving live |
| 22 | Kustomize | namePrefix, image tag, replicas, patch, label kept out of the selector, hashed ConfigMap resolved |
| 23 | Debugging playbook | all four planted faults reproduce as designed, then all four fixed and green |
| 24 | CRDs and operators | CRD Established, invalid resource rejected by schema, controller reconciled both CRs with ownerReferences |
| 25 | Capstone | 38 assertions: security context, config delivery, StatefulSet PVCs, HPA, PDB, 3 NetworkPolicies, live HTTP + HTTPS through the Ingress, and an unlabelled Pod confirmed blocked |

## Notes found while verifying

Three environment-specific behaviours were discovered by running this and are documented in
the lessons rather than left as traps:

- **Git Bash rewrites `/CN=...`** into a Windows path, so `openssl req -subj` needs `//CN=`.
  Using `MSYS_NO_PATHCONV=1` instead breaks `-keyout`/`-out`, which do need translation.
- **Alpine (musl) applies the resolv.conf search list only to names with no dot**, so
  `db-1.db` fails from an Alpine Pod while the FQDN works. glibc images behave differently
  on the same cluster.
- **busybox `nslookup` exits non-zero** once any search-domain permutation misses, even
  when it printed a correct answer — so the checkers judge its output, not its exit code.
