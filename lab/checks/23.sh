source "$(dirname "$0")/_lib.sh"
NS=lesson-23

for d in app-a app-b app-c app-d; do
  if ! k -n $NS get deploy $d >/dev/null 2>&1; then bad "deployment '$d' is missing - fix it, do not delete it"; continue; fi
  WANT="$(k -n $NS get deploy $d -o jsonpath='{.spec.replicas}' 2>/dev/null)"
  GOT="$(k -n $NS get deploy $d -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
  if [ "${GOT:-0}" = "$WANT" ]; then
    ok "$d: $GOT/$WANT Ready"
  else
    STATE="$(k -n $NS get pods -l app=$d -o jsonpath='{.items[0].status.containerStatuses[0].state}' 2>/dev/null | head -c 80)"
    PHASE="$(k -n $NS get pods -l app=$d -o jsonpath='{.items[0].status.phase}' 2>/dev/null)"
    bad "$d: ${GOT:-0}/$WANT Ready (phase=$PHASE $STATE)"
  fi
done

N="$(k -n $NS get endpointslices -l kubernetes.io/service-name=app-b -o jsonpath='{.items[*].endpoints[*].addresses[0]}' 2>/dev/null | wc -w | tr -d ' ')"
if [ "${N:-0}" -ge 2 ]; then
  ok "service app-b has $N endpoints"
else
  bad "service app-b has ${N:-0} endpoints - the Pods are fine, the Service is not finding them"
fi

if k -n $NS exec deploy/app-b -- wget -qO- --timeout=5 http://app-b:8080/ 2>/dev/null | grep -q .; then
  ok "http://app-b:8080 answers from inside the namespace"
else
  bad "app-b's Service still does not serve"
fi

GREET="$(k -n $NS exec deploy/app-c -- wget -qO- --timeout=5 http://127.0.0.1:8080/ 2>/dev/null | head -1)"
case "$GREET" in
  *hello-from-configmap*) ok "app-c is reading its greeting from the ConfigMap" ;;
  "")                     bad "app-c is not serving" ;;
  *)                      bad "app-c answers '$GREET' - it is not using the ConfigMap value" ;;
esac
finish
