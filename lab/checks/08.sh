source "$(dirname "$0")/_lib.sh"
NS=lesson-08
if ! k -n $NS get deploy web >/dev/null 2>&1; then bad "deployment 'web' exists in $NS"; finish; fi
ok "deployment 'web' exists"
D() { k -n $NS get deploy web -o jsonpath="$1" 2>/dev/null; }
S() { k -n $NS get svc "$1" -o jsonpath="$2" 2>/dev/null; }
eps() { k -n $NS get endpointslices -l kubernetes.io/service-name="$1" -o jsonpath='{.items[*].endpoints[*].addresses[0]}' 2>/dev/null | wc -w | tr -d ' '; }

eq "3 replicas Ready"              "3"    "$(D '{.status.readyReplicas}')"
eq "containerPort is named 'http'" "http" "$(D '{.spec.template.spec.containers[0].ports[0].name}')"

for s in web web-np; do
  if k -n $NS get svc $s >/dev/null 2>&1; then ok "service '$s' exists"; else bad "service '$s' missing"; continue; fi
  N="$(eps $s)"
  if [ "${N:-0}" -eq 3 ]; then ok "service '$s' has 3 endpoints"; else bad "service '$s' has ${N:-0} endpoints, expected 3 - check the selector"; fi
done

eq "web is ClusterIP"                 "ClusterIP" "$(S web '{.spec.type}')"
eq "web targetPort is the named port" "http"      "$(S web '{.spec.ports[0].targetPort}')"
eq "web-np is NodePort"               "NodePort"  "$(S web-np '{.spec.type}')"
eq "web-np uses nodePort 30080"       "30080"     "$(S web-np '{.spec.ports[0].nodePort}')"

if k -n $NS exec deploy/web -- wget -qO- --timeout=5 http://web 2>/dev/null | grep -qi nginx; then
  ok "http://web answers from inside the cluster"
else
  bad "could not fetch http://web from inside the cluster"
fi

if docker exec k8s-lab-worker curl -s -m 5 http://localhost:30080 2>/dev/null | grep -qi nginx; then
  ok "the NodePort answers on a worker node"
else
  bad "http://localhost:30080 did not answer inside k8s-lab-worker"
fi
finish
