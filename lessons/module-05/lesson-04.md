# 17 - Autoscaling and PodDisruptionBudgets

Two ways the replica count changes without you: something scales it up because load
demands it, and something scales it *down* because a node is going away. The first is the
HorizontalPodAutoscaler. The second is voluntary disruption, and a PodDisruptionBudget is
how you set the floor.

## Three autoscalers, doing three different things

  - **HPA** - more Pods. Reacts to CPU, memory or custom metrics. The one you will use.
  - **VPA** - bigger Pods. Rewrites requests/limits based on observed usage. Mostly
    incompatible with HPA on the same resource, and it usually has to restart the Pod to
    apply.
  - **Cluster Autoscaler / Karpenter** - more *nodes*, when Pods are `Pending`. Not
    present on kind; on a managed cluster it is what turns "unschedulable" into "wait 90
    seconds".

They compose: HPA adds Pods, the Pods do not fit, the cluster autoscaler adds a node.

## metrics-server is a prerequisite, not an extra

`kubectl top` and CPU-based HPAs both read the **metrics.k8s.io** API, which nothing
serves by default. Installing metrics-server is step zero; on kind it needs
`--kubelet-insecure-tls`, because the kubelets present self-signed certificates.

Without it, an HPA sits there with `<unknown>/50%` and never scales - which looks
identical to "my HPA is broken".

## How the HPA computes

    desiredReplicas = ceil( currentReplicas x ( currentMetric / targetMetric ) )

With `averageUtilization`, `currentMetric` is average CPU **as a percentage of the
request**. So an HPA on CPU utilisation **requires a CPU request** on the container - with
no request there is no denominator, and the HPA reports `<unknown>` forever. That is the
single most common HPA misconfiguration.

    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    spec:
      scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: hello }
      minReplicas: 1
      maxReplicas: 5
      metrics:
        - type: Resource
          resource:
            name: cpu
            target: { type: Utilization, averageUtilization: 50 }
      behavior:
        scaleDown:
          stabilizationWindowSeconds: 300   # the default: look back 5 minutes
        scaleUp:
          stabilizationWindowSeconds: 0     # scale up immediately

It re-evaluates every 15 seconds, and a 10% tolerance keeps it from oscillating around the
target. `behavior` is the field worth knowing: scale-up is immediate by default, scale-down
waits five minutes and uses the *highest* recommendation in that window, so a brief dip
does not shed capacity you are about to need.

Once an HPA owns a Deployment, **stop setting `replicas` in your manifests.** Your value
and the HPA's will fight, and a GitOps sync will re-apply yours every few minutes. Remove
the field.

CPU is a weak proxy for load in most .NET services, where the bottleneck is usually I/O
wait or queue depth. Real setups scale on custom or external metrics - queue length,
requests per second - through the `custom.metrics.k8s.io` API (KEDA is the common way in).
The mechanism is identical; only the metric source changes.

## PodDisruptionBudgets

Two kinds of disruption:

  - **Involuntary** - a node dies, an OOM kill, hardware failure. Nothing can protect you;
    only replicas help.
  - **Voluntary** - `kubectl drain` for an upgrade, a cluster autoscaler consolidating
    nodes, a node pool rotation. These go through the **eviction API**, and the eviction
    API respects PodDisruptionBudgets.

    apiVersion: policy/v1
    kind: PodDisruptionBudget
    spec:
      minAvailable: 2          # or: maxUnavailable: 1  (never both)
      selector:
        matchLabels: { app: hello }

"At least 2 of these must stay up while someone is voluntarily removing Pods." A drain
that would breach it blocks and waits rather than proceeding. That is the point: node
upgrades roll through the cluster without ever taking your service below its floor.

The classic self-inflicted wound: `minAvailable: 1` on a **single-replica** Deployment.
Now no node can ever be drained, cluster upgrades hang, and someone eventually deletes the
PDB in anger. Percentages are usually the right form (`minAvailable: 50%`), and a PDB only
makes sense alongside more than one replica.

Note it protects against *eviction*, not against you: `kubectl delete pod` ignores PDBs
entirely.

## Do this

1. Install metrics-server and make it work on kind:

       kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
       kubectl -n kube-system patch deploy metrics-server --type=json \
         -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
       kubectl -n kube-system rollout status deploy/metrics-server
       kubectl top nodes

   If `kubectl top nodes` prints numbers, the metrics pipeline is alive. Give it a minute
   after the rollout - the first scrape takes a moment.

2. In namespace `lesson-17`, Deployment `hello` with `hello:1.1.0`, **1** replica, label
   `app=hello`, port 8080 named `http`, and - this is the part people forget -
   `resources.requests.cpu: 100m` and `limits.cpu: 300m`.

3. An HPA `hello`: target the Deployment, `minReplicas: 1`, `maxReplicas: 5`, CPU
   utilisation target **50%**.

       kubectl -n lesson-17 get hpa -w

   Wait until the TARGETS column shows a real number rather than `<unknown>`.

4. A PDB `hello`: `minAvailable: 1`, selector `app=hello`.

5. Make it scale. Drive load through the app's CPU burner from a throwaway Pod:

       kubectl -n lesson-17 expose deploy hello --port=8080 --target-port=http
       kubectl -n lesson-17 run load --image=busybox:1.37 --restart=Never -- \
         sh -c 'while true; do wget -q -O- "http://hello:8080/burn?seconds=20" >/dev/null; done'

       kubectl -n lesson-17 get hpa -w        # watch REPLICAS climb
       kubectl -n lesson-17 get pods

   Within a minute or two the HPA adds Pods. Then stop the load and watch it *not*
   immediately scale back:

       kubectl -n lesson-17 delete pod load
       kubectl -n lesson-17 get hpa -w        # five minutes of stabilization

   That patience is `scaleDown.stabilizationWindowSeconds`, and it is a feature.

6. See the PDB actually block something. Drain the node your Pods are on:

       kubectl -n lesson-17 get pods -o wide
       kubectl drain k8s-lab-worker --ignore-daemonsets --delete-emptydir-data --timeout=30s

   With `minAvailable: 1` and Pods on both workers the drain succeeds; if every replica is
   on that node it blocks with "Cannot evict pod as it would violate the disruption
   budget". Either way, put the node back:

       kubectl uncordon k8s-lab-worker

   Run `kubectl get pdb -n lesson-17` and read `ALLOWED DISRUPTIONS` - that number is the
   whole object in one column.

## Hints

- `kubectl -n lesson-17 autoscale deploy hello --min=1 --max=5 --cpu-percent=50` creates
  the HPA in one line (it generates `autoscaling/v2` on modern clusters).
- There is no `kubectl create pdb` - write the YAML. `apiVersion: policy/v1`.
- `<unknown>` in the HPA's TARGETS column means either metrics-server is not serving or
  the container has no CPU **request**. Check both, in that order.
- Remove `replicas` from the Deployment manifest once the HPA exists, or the next `apply`
  will fight it.

## Solution

See `lab/solutions/17/all.yaml`.
