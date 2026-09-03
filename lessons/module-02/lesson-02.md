# 05 - Rollouts, rollbacks and rollout safety

Lesson 04 ended with a bare ReplicaSet that changed its template and left the running Pods
on the old image. A Deployment fixes that by owning a *sequence* of ReplicaSets and moving
replicas between them under control. This lesson is that mechanism, and how to keep it
from taking your service down.

## What actually happens on `kubectl apply`

You change one byte of the Pod template. The Deployment controller:

1. hashes the new template, finds no ReplicaSet with that hash, and creates one at 0
   replicas;
2. scales the new ReplicaSet up and the old one down, a few Pods at a time, obeying
   `maxSurge` and `maxUnavailable`;
3. **waits for each new Pod to become Ready** before continuing;
4. when the new ReplicaSet holds all the replicas, stops - leaving the old one at 0.

Only step 3 protects you, and only if "Ready" means something. Watch the whole thing:

    kubectl -n lesson-05 get rs -w
    kubectl -n lesson-05 rollout status deploy/web

## The two dials

    strategy:
      type: RollingUpdate
      rollingUpdate:
        maxUnavailable: 25%   # how far below `replicas` you may dip
        maxSurge: 25%         # how far above `replicas` you may go

Both accept an integer or a percentage (rounded down for unavailable, up for surge). With
4 replicas and the defaults, between 3 and 5 Pods run during the rollout.

  - `maxUnavailable: 0` - never lose capacity. Requires `maxSurge >= 1` and enough room in
    the cluster, since you briefly run more Pods than you asked for. This is the right
    setting for anything user-facing.
  - `maxSurge: 0` - never exceed the replica count. For workloads with a hard external
    limit: a fixed licence count, a connection-limited database, a singleton lock.
  - Both zero is rejected. It would mean "change nothing".

`type: Recreate` deletes every old Pod, waits, then creates the new ones. Guaranteed
downtime, and the only correct choice when two versions genuinely cannot run at once - an
exclusive lock, an in-place schema migration, a ReadWriteOnce volume that only one Pod may
mount.

## Readiness is what makes this safe

Without a readiness probe, a Pod is "Ready" the moment its process has not exited. For an
app that takes 20 seconds to warm up, that is a lie - the Deployment marches on, the
Service routes traffic to a Pod that is not listening, and a broken build rolls out to
100% while every dashboard stays green. **A rollout is only as safe as its readiness
probe.** Probes get their own lesson (14); this is why they exist.

## History, and why yours is full of `<none>`

    kubectl -n lesson-05 rollout history deploy/web
    kubectl -n lesson-05 rollout history deploy/web --revision=2

The `CHANGE-CAUSE` column is fed by the annotation `kubernetes.io/change-cause` on the Pod
template. Nothing populates it for you - the old `--record` flag is deprecated and gone.
Set it yourself, in the manifest or in CI, and the history becomes a readable changelog
instead of four identical blank rows:

    kubectl -n lesson-05 annotate deploy/web kubernetes.io/change-cause="bump nginx to 1.29"

How much history you keep is `spec.revisionHistoryLimit` (default 10). Each retained
revision is one scaled-to-zero ReplicaSet object; they cost nothing to run but they are
what `rollout undo` reads. Set it to 0 and you have no rollback.

## Rolling back

    kubectl -n lesson-05 rollout undo deploy/web
    kubectl -n lesson-05 rollout undo deploy/web --to-revision=1

`undo` re-applies an old template, which means it creates a **new revision number** with
old content. Rolling back from revision 2 gives you revision 3, not revision 1 again.
That surprises people reading `rollout history` after an incident.

Important: `undo` changes the live object, not your Git repo. The next `kubectl apply` (or
the next Argo/Flux sync) will happily re-deploy the broken version. A rollback is a
stopgap; the fix is a commit.

## The other rollout verbs

    kubectl -n lesson-05 rollout restart deploy/web    # bounce every Pod, gracefully
    kubectl -n lesson-05 rollout pause   deploy/web
    kubectl -n lesson-05 rollout resume  deploy/web

`restart` stamps `kubectl.kubernetes.io/restartedAt` on the template - a real template
change, so you get a proper rolling restart instead of a `delete pod` massacre. It is how
you pick up a changed ConfigMap or a rotated Secret.

`pause` freezes the controller so you can make several edits and have them roll out as one
change on `resume`. It is also a crude canary: pause after the first new Pod, look at your
metrics, then resume or undo.

## When a rollout is stuck

`progressDeadlineSeconds` (default 600) is the clock. If no progress is made in that
window, the Deployment gets `Progressing=False` with reason `ProgressDeadlineExceeded`.

    kubectl -n lesson-05 rollout status deploy/web        # exits non-zero on failure
    kubectl -n lesson-05 describe deploy web              # read Conditions, then Events

Kubernetes will **not** roll back for you. It stops and waits. In practice the surge Pods
sit in `ImagePullBackOff` or `CrashLoopBackOff` while the old ones keep serving - which is
the system working as designed: a bad rollout degrades to "nothing changed" rather than
"everything is down". Wiring `rollout status` into CI, and reacting to its exit code, is
your half of the deal.

## Do this

In namespace `lesson-05`:

1. Deployment `web`: **4** replicas, label `app=web`, container `nginx`, image
   **`nginx:1.27-alpine`**, containerPort 80, explicit `maxSurge: 25%` /
   `maxUnavailable: 25%`, and `kubernetes.io/change-cause: "initial 1.27"` on the Pod
   template.
2. Roll forward to **`nginx:1.29-alpine`**. Watch it two ways, in two terminals:

       kubectl -n lesson-05 get rs -w
       kubectl -n lesson-05 rollout status deploy/web

3. Read the history. You should have 2 revisions and 2 ReplicaSets, one of them at 0.
4. Decide 1.29 is bad. **Roll back.** Confirm the image is 1.27 again and note that the
   revision number went *up*.
5. Scale to **5** replicas.
6. Finally, break one on purpose and watch the system protect you:

       kubectl -n lesson-05 set image deploy/web nginx=nginx:9.9.9-does-not-exist
       kubectl -n lesson-05 rollout status deploy/web --timeout=60s   # non-zero exit
       kubectl -n lesson-05 get pods                                  # ImagePullBackOff
       kubectl -n lesson-05 get deploy web                            # still 5 READY
       kubectl -n lesson-05 rollout undo deploy/web

   Four healthy Pods never stopped serving. That is `maxUnavailable` doing its job.

End state the checker wants: 5 ready replicas on `nginx:1.27-alpine`, revision >= 3.

## Hints

- `kubectl -n lesson-05 set image deploy/web nginx=nginx:1.29-alpine`
- `kubectl -n lesson-05 rollout undo deploy/web`
- Current revision:
  `kubectl -n lesson-05 get deploy web -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}'`
- If you finish step 6 and the checker complains about the image, you forgot the final
  `rollout undo`.

## Solution

See `lab/solutions/05/deployment.yaml`, then:

    kubectl apply -f lab/solutions/05/deployment.yaml
    kubectl -n lesson-05 rollout status deploy/web
    kubectl -n lesson-05 set image deploy/web nginx=nginx:1.29-alpine
    kubectl -n lesson-05 rollout status deploy/web
    kubectl -n lesson-05 rollout undo deploy/web
    kubectl -n lesson-05 scale deploy/web --replicas=5
    kubectl -n lesson-05 rollout status deploy/web
