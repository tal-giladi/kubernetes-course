# 07 - DaemonSets, Jobs and CronJobs

*Module 02 - Running workloads, lesson 4 of 4. Exercise 07 of 25.*

A Deployment says "N copies, somewhere". Three other controllers say something different,
and each is the right answer to a question a Deployment answers badly.

## DaemonSet: one Pod per node

    "run exactly one of these on every node, including nodes that join later"

Log collectors (Fluent Bit), metrics agents (node-exporter), CNI plugins, storage drivers,
security agents. Anything that is *about the node* rather than about your traffic.

No `replicas` field - the count is the node count. Add a node and a Pod appears on it;
drain a node and its Pod goes. `nodeSelector` or `affinity` narrows which nodes qualify,
which is how you run a GPU agent only on GPU nodes.

Your kind cluster has three nodes, but a naive DaemonSet will only produce **two** Pods.
The control-plane node carries a taint:

    kubectl get node k8s-lab-control-plane -o jsonpath='{.spec.taints}'
    [{"effect":"NoSchedule","key":"node-role.kubernetes.io/control-plane"}]

A **taint** on a node repels Pods; a **toleration** on a Pod lets it ignore a specific
taint. This is exactly how a real cluster keeps your workloads off the control plane, and
exactly why every monitoring DaemonSet ships with control-plane tolerations. Taints get
their own lesson (16); here you need one:

    tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule

A DaemonSet updates with `updateStrategy: RollingUpdate` and `maxUnavailable` counted in
*nodes*. `OnDelete` means "only replace a Pod when I delete it by hand" - useful for
agents you upgrade node by node.

## Job: run to completion

    "run this until it succeeds, then stop"

Migrations, batch imports, one-off repairs, ML training runs. A Job creates Pods and
tracks how many finished successfully.

    spec:
      completions: 3       # how many successful Pods make the Job done
      parallelism: 2       # how many may run at once
      backoffLimit: 4      # how many total failures before the Job is marked Failed
      activeDeadlineSeconds: 600   # wall-clock cap on the whole Job
      ttlSecondsAfterFinished: 300 # auto-delete the Job (and its Pods) after it finishes
      template:
        spec:
          restartPolicy: Never     # or OnFailure. Always is rejected.

Details that matter:

  - **`restartPolicy: Never` vs `OnFailure`.** `Never` makes a *new Pod* per attempt, so
    you keep the failed Pods and their logs - almost always what you want when debugging.
    `OnFailure` restarts the container in place; the log of attempt 1 is gone.
  - **`backoffLimit` counts failures, not attempts**, and the retry delay doubles
    (10s, 20s, 40s ... capped at 6 minutes). A Job that "hangs" for ten minutes is usually
    just backing off.
  - **A Job guarantees at-least-once, not exactly-once.** A node can die after your code
    committed but before the Pod reported success. Make Job work idempotent.
  - **Finished Jobs are not cleaned up** unless you set `ttlSecondsAfterFinished`. Namespaces
    full of six-month-old Completed Pods are a real and common mess.
  - `completionMode: Indexed` gives each Pod a fixed index in `JOB_COMPLETION_INDEX` - the
    clean way to shard a batch across parallel Pods.

## CronJob: a Job on a schedule

    "create a Job at these times"

    spec:
      schedule: "*/5 * * * *"        # standard cron, five fields
      timeZone: "Asia/Jerusalem"     # without it: the controller's zone, usually UTC
      concurrencyPolicy: Forbid      # Allow | Forbid | Replace
      startingDeadlineSeconds: 60
      successfulJobsHistoryLimit: 3
      failedJobsHistoryLimit: 1
      suspend: false
      jobTemplate: { ... }           # an entire Job spec

The field that saves you is **`concurrencyPolicy`**. The default is `Allow`: if your
five-minute job takes seven minutes, a second copy starts alongside the first, and by
lunchtime you have fourteen copies of a report generator fighting over the same rows.
`Forbid` skips the new run; `Replace` kills the old one. Choose deliberately - the default
is the dangerous one.

`suspend: true` is the correct way to pause a schedule during an incident. Do not delete
the CronJob; you will forget to recreate it.

`startingDeadlineSeconds` bounds how late a missed run may still start. If the controller
was down longer than that, the run is skipped rather than fired at 3am when everything
comes back. Leave it unset and more than 100 missed schedules will wedge the CronJob
entirely.

## Do this

In namespace `lesson-07`:

1. A **DaemonSet** `node-probe`: image `busybox:1.37`, command
   `["sh","-c","while true; do sleep 3600; done"]`, label `app=node-probe`. Deploy it
   without tolerations first and count the Pods:

       kubectl -n lesson-07 get ds,pods -o wide

   Two Pods, three nodes. Now add the control-plane toleration and get all **three**.

2. A **Job** `pi`: `completions: 3`, `parallelism: 2`, `backoffLimit: 2`,
   `restartPolicy: Never`, image `busybox:1.37`, command that does a little work and
   exits 0, for example
   `["sh","-c","echo computing; sleep 3; echo done"]`.
   Watch it fill up:

       kubectl -n lesson-07 get job pi -w
       kubectl -n lesson-07 get pods -l job-name=pi

   Then look at what a *failing* Job does, in a throwaway namespace:

       kubectl create ns scratch
       kubectl -n scratch create job doomed --image=busybox:1.37 -- sh -c 'exit 1'
       kubectl -n scratch get pods -w        # attempts, with growing gaps between them
       kubectl -n scratch describe job doomed | tail
       kubectl delete ns scratch

3. A **CronJob** `heartbeat`: schedule `"* * * * *"` (every minute),
   `concurrencyPolicy: Forbid`, `successfulJobsHistoryLimit: 2`, image `busybox:1.37`,
   command `["sh","-c","date; echo heartbeat"]`, `restartPolicy: OnFailure`.
   Wait a couple of minutes and watch Jobs appear and old ones get trimmed:

       kubectl -n lesson-07 get cronjob,jobs
       kubectl -n lesson-07 logs job/$(kubectl -n lesson-07 get jobs -o name | head -1 | cut -d/ -f2)

   Then try `kubectl -n lesson-07 patch cronjob heartbeat -p '{"spec":{"suspend":true}}'`
   and confirm no new Jobs appear. (Unsuspend it before you run the checker.)

## Hints

- `kubectl create job` and `kubectl create cronjob` exist and take `--dry-run=client -o yaml`.
  There is no `kubectl create daemonset` - start from a Deployment's YAML, change `kind`
  to `DaemonSet`, and delete `spec.replicas` and `spec.strategy`.
- The DaemonSet's Pod template needs the toleration in `spec.template.spec.tolerations`.
- If `busybox` Pods show `CrashLoopBackOff`, your command exited immediately - busybox
  with no arguments does nothing and stops.

## Solution

See `lab/solutions/07/all.yaml`.
