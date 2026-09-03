# Module 04 plan - Configuration and state

**Lessons 11-13. Prerequisite: module 03. Produces: a configured, persistent, identity-
bearing workload.**

## Objectives

1. Externalise configuration and predict exactly what updates on a change and what does not.
2. Explain what a Secret protects against and what it does not.
3. Provision storage dynamically, and explain `WaitForFirstConsumer`, access modes and
   reclaim policy.
4. Choose between a Deployment and a StatefulSet for a given workload, with reasons.

## Lessons

### 11 - ConfigMaps and Secrets
- **Concept**: key/value where values can be whole files; the 1 MiB etcd limit; four
  consumption modes; `subPath` never updating; env vars never updating; the checksum
  annotation pattern; base64 is not encryption; what actually protects a Secret (RBAC,
  encryption at rest, external stores); files over env vars for secrets.
- **Example**: the same ConfigMap key visible as two different values in one Pod - fresh in
  the mounted file, stale in the environment.
- **Practice**: consume a ConfigMap three ways at once, change it, wait, and observe the
  divergence; then decode the Secret to see what "encoded" means.
- **Summary**: treat configuration changes as deployments.

### 12 - Volumes, PVs, PVCs and StorageClasses
- **Concept**: the ephemeral volume types and `hostPath` as a security hole; the
  PVC/PV/StorageClass split and why the workload never names a disk; dynamic provisioning;
  access modes as a statement about *nodes*; `WaitForFirstConsumer`; `Delete` vs `Retain`;
  expansion.
- **Example**: a `Pending` PVC that is not an error, then the same PVC binding the instant
  a Pod is scheduled.
- **Practice**: a PVC-backed Deployment and an `emptyDir` one with identical YAML shape;
  write, delete the Pod, read again; then scale past the RWO limit and read the reason.
- **Summary**: a Deployment plus one RWO claim is a single-replica workload.

### 13 - StatefulSets
- **Concept**: stable ordinal names, per-Pod `volumeClaimTemplates`, ordered lifecycle;
  the required headless Service and per-Pod DNS; what StatefulSets do *not* do (no
  leader election, no replication); PVCs surviving scale-down and deletion; immutable claim
  templates; `partition` as a canary.
- **Example**: deleting `db-1` and getting `db-1` back, with its data.
- **Practice**: three Pods, three PVCs, per-Pod DNS, destroy and verify; plus the musl
  search-domain trap that makes short names fail on Alpine.
- **Summary**: identity is the feature; clustering is still your problem.

## Dependencies

11 -> 12 -> 13 (volumes before claim templates). 12's persistence test and 13's identity
test both reappear in the capstone.

## Misconceptions

- "Changing a ConfigMap restarts my Pods." (Only the mounted files change, eventually.)
- "Secrets are encrypted." (They are base64 in etcd unless you configured otherwise.)
- "A Pending PVC means something is broken." (Usually it means `WaitForFirstConsumer`.)
- "ReadWriteOnce means one Pod." (It means one *node*, unless it is `ReadWriteOncePod`.)
- "Deleting a StatefulSet deletes its data." (It does not - deliberately.)
