# Module 02 quiz - Running workloads

Eight questions. Answers at the bottom.

---

**1.** You edit a bare ReplicaSet's image from `v1` to `v2`. `kubectl get rs` shows the new
image. `kubectl get pods -o jsonpath=...` shows the old one. Is this a bug? What would a
Deployment have done differently, and why does the ReplicaSet behave this way?

**2.** A Deployment has `replicas: 4`, `maxSurge: 25%`, `maxUnavailable: 25%`. During a
rollout, what is the minimum and maximum number of Pods that can exist? Which setting would
you change for a service that must never lose capacity, and what does that cost you?

**3.** You push a fix, rebuild `myapp:1.4.0` (the same tag), and `kubectl apply`. Nothing
happens - and even after you delete a Pod, the old code is still running on one node. Give
both reasons.

**4.** `kubectl rollout undo deploy/web` succeeds and the service recovers. Your CI runs
`kubectl apply -f k8s/` every ten minutes. What happens next, and what is the actual fix?

**5.** A rollout has been stuck for fifteen minutes. `kubectl get deploy` shows
`3/4 READY`. Is the service down? What will Kubernetes do about it, and by when?

**6.** You deploy a monitoring agent as a DaemonSet on a 3-node cluster and get 2 Pods.
Nothing is `Pending`, nothing is failing. What happened, and what is the one-line fix?

**7.** A nightly Job that normally takes 4 minutes has been "running" for 12 with no new
Pods. `describe job` shows 3 failures. What is it doing? Would `restartPolicy: OnFailure`
have made debugging easier or harder?

**8.** A CronJob scheduled `*/5 * * * *` runs a report that occasionally takes 8 minutes.
Describe what your cluster looks like at 6pm, and the single field that prevents it.

---

## Answers

**1.** Not a bug. A ReplicaSet only creates Pods from its template when it needs *more*
Pods; it never replaces a healthy one. A Deployment would have created a **new ReplicaSet**
with the new template hash and shifted replicas across, waiting for readiness at each step.
The ReplicaSet has no concept of versions - sequencing is precisely the layer a Deployment
adds.

**2.** Minimum 3, maximum 5 (25% of 4 = 1 each way). For no capacity loss set
`maxUnavailable: 0`; the cost is that you must be able to run *more* Pods than your replica
count during the rollout - extra resource headroom, and a workload that tolerates two
versions running at once.

**3.** (a) The Pod template did not change - same image string - so the Deployment has
nothing to roll out. (b) `imagePullPolicy: IfNotPresent` (the default for a non-`latest`
tag) means a node that already has a layer cached for that tag will not re-pull it. The fix
is immutable tags: bump the version, or pin by digest.

**4.** The next `apply` re-deploys the broken version, because the manifest in git still
says so and `apply` is declarative. A rollback is a stopgap that changes only the live
object; the fix is a commit that changes the manifest.

**5.** No - three of four replicas are Ready and serving. Kubernetes will mark the
Deployment `Progressing=False` with `ProgressDeadlineExceeded` after
`progressDeadlineSeconds` (default 600s) and then **do nothing else**. It never
auto-rolls-back. Reacting is your job, or your CI's, via `kubectl rollout status`' exit
code.

**6.** The control-plane node carries `node-role.kubernetes.io/control-plane:NoSchedule`
and your DaemonSet has no toleration, so it is silently skipped - and a DaemonSet has no
`replicas` field, so nothing looks wrong. Fix: add a toleration with `operator: Exists` for
that key.

**7.** It is backing off between attempts - the delay doubles (10s, 20s, 40s...) up to six
minutes, so a Job with a few failures can look frozen. `OnFailure` would have made
debugging **harder**: it restarts the container in place, so the failed attempt's logs are
overwritten. `Never` creates a new Pod per attempt and keeps every one of them.

**8.** By 6pm you have several overlapping copies of the report competing for the same
rows, because `concurrencyPolicy` defaults to `Allow`. Set `concurrencyPolicy: Forbid`
(skip the new run) or `Replace` (kill the old one). The default is the dangerous choice.
