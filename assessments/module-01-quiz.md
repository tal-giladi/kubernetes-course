# Module 01 quiz - Foundations

Seven questions. Answers and explanations at the bottom - try all seven first.

---

**1.** You run `kubectl delete pod web` and the Pod disappears. Ten seconds later a Pod
called `web-7d9f8c6b45-x2ktq` is running. Explain, in terms of `spec` and `status`, what
happened - and say what is *not* true about the new Pod.

**2.** Which component actually starts a container: the scheduler, the controller manager,
the API server, or the kubelet? What does each of the other three do instead?

**3.** A colleague says "etcd is where the logs go". Correct them in one sentence, and say
what etcd actually holds.

**4.** You have this in your kubeconfig:

    CURRENT   NAME           CLUSTER
              kind-k8s-lab   kind-k8s-lab
    *         prod-aks       prod-aks

You are about to run `kubectl delete namespace lesson-03`. What happens, and what should
you have done first? Name two ways to make this impossible rather than unlikely.

**5.** `kubectl get pods -n kube-system` shows `kube-apiserver-k8s-lab-control-plane` as a
Pod. But the API server is what creates Pods. How did that Pod get created?

**6.** For each field, say whether *you* write it or a controller does:
`spec.replicas`, `status.readyReplicas`, `metadata.labels`, `status.podIP`,
`spec.nodeName`.

**7.** Your Pod is `Pending`. Give three distinct causes, and the single command that will
tell you which one it is.

---

## Answers

**1.** Nothing was repaired or moved. The ReplicaSet's `spec.replicas` still said 3 while
its observed `status` showed 2, so the controller created a **new** Pod to close the gap.
Not true of the new Pod: it is the same Pod, it has the same name, it has the same IP, or
it has anything the old one wrote to its container filesystem. It is a new object that
happens to match the same template.

**2.** The **kubelet**. The scheduler only *assigns* a node by writing `spec.nodeName` -
it never starts anything. The controller manager runs the reconciliation loops that create
Pod objects. The API server validates and stores; it is the only component the others talk
to.

**3.** etcd holds the cluster's desired and observed **state** - every object you can
`kubectl get` - and no logs at all. Container logs live on the node the container ran on,
written by the container runtime, and vanish with the Pod.

**4.** It deletes `lesson-03` in **prod-aks**, because that is the current context, and it
is a valid command that will succeed. You should have checked
`kubectl config current-context` first. Two ways to make it structurally impossible:
(a) `source lab/env.sh` so `KUBECONFIG` points at a file containing only the lab cluster;
(b) pass `--context kind-k8s-lab` on every command, which is what the course's grader does.

**5.** It is a **static Pod**. The kubelet reads its manifest from
`/etc/kubernetes/manifests` on disk and starts it directly, without asking anyone - which
is how the cluster bootstraps before the API server exists. The Pod object you see is a
read-only *mirror* the kubelet creates afterwards so the object is visible.

**6.** You: `spec.replicas`, `metadata.labels`. Controllers: `status.readyReplicas`,
`status.podIP`, and `spec.nodeName` - which is the interesting one, because it is in
`spec` but written by the scheduler. `spec` means "desired", not "written by a human".

**7.** (a) No node has enough allocatable resource for its **requests**; (b) every node
carries a taint the Pod does not tolerate, or a nodeSelector/affinity matches nothing;
(c) it references an unbound PersistentVolumeClaim. One command:
`kubectl describe pod <name>` - read the `FailedScheduling` event at the bottom, which
names each node and its reason. ("Still pulling the image" also shows as `Pending`, and
the same command tells you.)
