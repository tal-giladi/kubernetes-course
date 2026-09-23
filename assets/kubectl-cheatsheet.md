# kubectl cheat sheet

Everything here appears somewhere in the course. Short names: `po svc deploy rs sts ds cm
secret ns sa pvc pv ing netpol hpa pdb`.

## Orientation

    kubectl config get-contexts
    kubectl config current-context               # before anything destructive
    kubectl config use-context kind-k8s-lab
    source lab/env.sh                            # isolate this shell to the lab cluster
    . .\lab\env.ps1                              # the same, in PowerShell (note the dot)

    kubectl api-resources                        # every kind, group, short name, namespaced?
    kubectl api-versions
    kubectl explain deployment.spec.strategy     # the schema of YOUR cluster
    kubectl -v=6 get pods                        # show the HTTP call underneath

## Looking

    kubectl get pods -A -o wide
    kubectl get pods --show-labels
    kubectl get pods -L app,tier                 # labels as columns
    kubectl get pods --sort-by=.status.startTime
    kubectl get pods --field-selector status.phase=Running
    kubectl get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,QOS:.status.qosClass
    kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}'
    kubectl describe pod web                     # spec + conditions + EVENTS
    kubectl get events --sort-by=.lastTimestamp
    kubectl get events --field-selector type=Warning

## Writing

    kubectl apply -f m.yaml                      # declarative; safe to re-run
    kubectl diff -f m.yaml                       # what would change
    kubectl apply --dry-run=server -f m.yaml     # validate without persisting
    kubectl create deploy web --image=nginx --dry-run=client -o yaml > web.yaml
    kubectl patch svc web -p '{"spec":{"selector":{"app":"web"}}}'
    kubectl label   cm -l env=prod reviewed=true
    kubectl annotate deploy web kubernetes.io/change-cause="bump to 1.29"
    kubectl label node k8s-lab-worker disktype-  # trailing - removes
    kubectl taint node k8s-lab-worker2 lab=demo:NoSchedule-

## Workloads

    kubectl scale deploy/web --replicas=5
    kubectl set image deploy/web nginx=nginx:1.29-alpine
    kubectl set env  deploy/web APP_VERSION=1.1.0
    kubectl rollout status  deploy/web           # exits non-zero on failure
    kubectl rollout history deploy/web
    kubectl rollout undo    deploy/web --to-revision=1
    kubectl rollout restart deploy/web           # graceful bounce, picks up new config
    kubectl rollout pause|resume deploy/web

## Getting inside

    kubectl logs web -c nginx --previous         # the container that DIED
    kubectl logs -l app=web --tail=50 -f
    kubectl exec -it web -- sh
    kubectl port-forward svc/web 8080:80
    kubectl cp web:/app/log.txt ./log.txt
    kubectl debug web -it --image=busybox:1.37 --target=hello   # distroless images
    kubectl debug node/k8s-lab-worker -it --image=busybox:1.37

## Networking

    kubectl describe svc web                                   # read Endpoints:
    kubectl get endpointslices -l kubernetes.io/service-name=web
    kubectl exec deploy/web -- cat /etc/resolv.conf
    kubectl exec deploy/web -- nslookup web-headless
    kubectl describe ingress shop
    kubectl describe netpol default-deny-ingress               # check OR vs AND

## Security

    kubectl auth can-i --list -n prod
    kubectl auth can-i get secrets -n prod --as=system:serviceaccount:prod:reader
    kubectl auth whoami
    kubectl label ns prod pod-security.kubernetes.io/enforce=restricted

## Capacity

    kubectl top nodes ; kubectl top pods -A                    # needs metrics-server
    kubectl describe node NODE | sed -n '/Allocated resources/,/^Events/p'
    kubectl describe quota team-quota
    kubectl get pdb                                            # ALLOWED DISRUPTIONS
    kubectl drain NODE --ignore-daemonsets --delete-emptydir-data
    kubectl uncordon NODE

## Packaging

    kubectl kustomize overlays/prod            # render
    kubectl apply -k overlays/prod
    helm template shop ./chart -f prod.yaml    # render, no cluster
    helm upgrade --install shop ./chart -n ns --atomic --wait
    helm history shop -n ns
    helm rollback shop 1 -n ns
    helm get manifest shop -n ns

## kind

    kind create cluster --config lab/cluster/kind-config.yaml
    kind load docker-image hello:1.1.0 --name k8s-lab
    kind export kubeconfig --name k8s-lab --kubeconfig lab/.kubeconfig
    kind delete cluster --name k8s-lab
    docker exec k8s-lab-worker crictl images
