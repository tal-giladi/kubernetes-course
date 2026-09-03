# Module 02 plan - Running workloads

**Lessons 04-07. Prerequisite: module 01. Produces: your own image running under every
workload controller that matters.**

## Objectives

1. Explain the Deployment -> ReplicaSet -> Pod chain and predict what each layer will do.
2. Perform a rolling update, read its history, and roll it back; choose `maxSurge` and
   `maxUnavailable` deliberately.
3. Get a locally built image onto a cluster's nodes, and explain `imagePullPolicy`
   including the `:latest` default flip.
4. Choose correctly between Deployment, DaemonSet, Job and CronJob.

## Lessons

### 04 - Deployments and ReplicaSets
- **Concept**: the ReplicaSet's single job; selector immutability; adoption and
  `ownerReferences`; the `pod-template-hash`; self-healing at Pod and node level; the
  300-second eviction delay.
- **Example**: deleting a Pod and watching a differently-named one appear; stopping a node
  container and watching the grace period.
- **Practice**: a Deployment *and* a bare ReplicaSet, then `set image` on the ReplicaSet -
  which changes the template and updates nothing. The gap a Deployment exists to fill.
- **Summary**: ReplicaSets count; Deployments sequence.

### 05 - Rollouts, rollbacks and rollout safety
- **Concept**: what `apply` triggers step by step; the two dials and when zero is right for
  each; readiness as the only real safety; change-cause; `revisionHistoryLimit`;
  `progressDeadlineSeconds` and the fact that Kubernetes never auto-rolls-back.
- **Example**: rolling to a nonexistent tag - surge Pods wedge, old Pods keep serving.
- **Practice**: roll forward, roll back, scale, then deliberately break it and observe that
  capacity never dropped.
- **Summary**: a bad rollout should degrade to "nothing changed".

### 06 - Your own image: build, load, deploy
- **Concept**: why nodes cannot see your Docker daemon; three ways out; `imagePullPolicy`
  and the `:latest` flip; immutable tags and digests; `imagePullSecrets`; the pull failure
  vocabulary.
- **Example**: an image that is *present on the node* and still fails to pull, because it
  is tagged `:latest`.
- **Practice**: build two tags, `kind load` both, deploy one, break it with `:latest`, fix
  it by policy alone, then roll forward.
- **Summary**: bump the tag; never reuse one.

### 07 - DaemonSets, Jobs and CronJobs
- **Concept**: per-node workloads and why the control-plane taint hides one node;
  `completions`/`parallelism`/`backoffLimit`; `Never` vs `OnFailure` and keeping evidence;
  at-least-once semantics; `ttlSecondsAfterFinished`; `concurrencyPolicy` and why the
  default is the dangerous one.
- **Example**: a DaemonSet that covers 2 of 3 nodes until it tolerates the taint.
- **Practice**: all three controllers, plus a deliberately failing Job in a scratch
  namespace to watch exponential backoff.
- **Summary**: pick the controller that matches the lifecycle, not the one you know.

## Dependencies

04 -> 05 (rollout needs the RS chain). 06 must precede everything from module 03 onward -
it produces the `hello` image the rest of the course deploys. 07 introduces taints, which
module 05 lesson 16 develops.

## Misconceptions

- "`kubectl apply` restarts my Pods." (Only a *template* change does.)
- "Rebuilding the same tag deploys my fix." (Nothing changed, as far as the cluster is concerned.)
- "A Job that has not finished in ten minutes is stuck." (It is backing off.)
- "`concurrencyPolicy` defaults to something safe." (It defaults to `Allow`.)
