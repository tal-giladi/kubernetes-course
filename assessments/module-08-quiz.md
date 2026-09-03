# Module 08 quiz - Mastery

Nine questions. Answers at the bottom.

---

**1.** For each status, name the most likely cause and the next command:
`ImagePullBackOff`, `CreateContainerConfigError`, `CrashLoopBackOff`, `Running 0/1`,
`Pending`.

**2.** A container's `describe` shows exit code 137. Give two different causes and how you
tell them apart.

**3.** Why is `kubectl logs POD --previous` often more useful than `kubectl logs POD`?

**4.** Your image is distroless - no shell, no `wget`, nothing. How do you get a shell that
can see the container's processes and network?

**5.** Ten unrelated services start failing at once. Name three cluster-level checks you
run before looking at any of them.

**6.** You apply a CRD and create three custom resources. Nothing happens. Is the CRD
broken?

**7.** You set `spec.retries: 3` on a custom resource. It applies successfully, and
`kubectl get -o yaml` shows no `retries` field at all. What happened, and why is this the
worst kind of failure?

**8.** Explain "level-triggered" for a controller, and why an event-driven controller is
wrong even though events exist.

**9.** A controller creates a ConfigMap for each custom resource. Someone deletes a custom
resource. What deletes the ConfigMap, and what did the controller author have to write to
make that happen?

---

## Answers

**1.**
- `ImagePullBackOff` - wrong tag, missing pull secret, or an image never pushed/loaded.
  `kubectl describe pod` and read the event's message.
- `CreateContainerConfigError` - a referenced ConfigMap or Secret **key** does not exist.
  `describe pod` names it exactly; there are no logs, because the container never started.
- `CrashLoopBackOff` - the process exits. `kubectl logs POD --previous`.
- `Running 0/1` - a failing readiness probe, not a crash. `describe pod`, then curl the
  probe path from inside the container.
- `Pending` - unschedulable, or still pulling. `describe pod`, read `FailedScheduling`.

**2.** 137 is 128+9, i.e. SIGKILL. Either the kernel **OOM-killed** it for exceeding its
memory limit - `describe` shows `Reason: OOMKilled` in the last state - or the **liveness
probe** failed and the kubelet killed it, which shows as a `Liveness probe failed` event
just before the restart. The events tell you which; the exit code alone does not.

**3.** In a crash loop, the currently running container has just started and has nothing
interesting in its log. `--previous` shows the instance that actually died - the stack
trace, the missing config, the connection refused. It is the first command to reach for
whenever `RESTARTS` is non-zero.

**4.** `kubectl debug POD -it --image=busybox:1.37 --target=<container>` attaches an
**ephemeral container** that shares the Pod's namespaces (and, with `--target`, the target
container's process namespace) without restarting anything. `kubectl debug node/<node>` gets
you a shell on the node itself.

**5.** (a) `kubectl get nodes` - is anything `NotReady`, and does `describe node` show
DiskPressure/MemoryPressure? (b) `kubectl -n kube-system get pods` - are CoreDNS and
kube-proxy healthy? A CoreDNS crash loop makes every service look broken at once.
(c) `kubectl get events -A --sort-by=.lastTimestamp` and `kubectl get --raw='/readyz?verbose'`
- is the control plane itself healthy?

**6.** No. A CRD is **only** a schema and an endpoint: storage, validation, RBAC and
`kubectl get`. Nothing acts on custom resources until a **controller** watches them and
reconciles. CRD + controller + operational knowledge is what people mean by "operator"; you
installed one third of one.

**7.** The field is not in the CRD's OpenAPI schema, so the API server **pruned** it -
silently, with a successful response. It is the worst kind of failure because it looks
exactly like success: no error, no warning, and a setting that simply never takes effect.
Check with `kubectl get <kind> <name> -o yaml` after applying anything you have just added
to a schema.

**8.** Level-triggered means the loop reads **current state** - the desired object and the
actual world - and converges them, rather than reacting to a change notification.
Event-driven is wrong because events are lost when the controller restarts, may arrive
twice, and may arrive out of order; a controller that only handles events drifts
permanently the first time it misses one. The loop must be idempotent and derive everything
from state, which is why running the same reconcile twice changes nothing.

**9.** Kubernetes' **garbage collector** deletes it, because the ConfigMap carries an
`ownerReferences` entry pointing at the custom resource (with its UID). The author wrote no
cleanup code at all - only the ownership stamp when creating the child. `finalizers` are the
separate mechanism for when you must clean up something *outside* the cluster before the
object may go.
