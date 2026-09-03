source "$(dirname "$0")/_lib.sh"
NS=lesson-06
if ! k -n $NS get deploy hello >/dev/null 2>&1; then bad "deployment 'hello' exists in $NS"; finish; fi
ok "deployment 'hello' exists"
D() { k -n $NS get deploy hello -o jsonpath="$1" 2>/dev/null; }
E() { k -n $NS get deploy hello -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name=='$1')].value}" 2>/dev/null; }

eq "3 replicas Ready"           "3"                "$(D '{.status.readyReplicas}')"
eq "image is hello:1.1.0"       "hello:1.1.0"      "$(D '{.spec.template.spec.containers[0].image}')"
eq "imagePullPolicy IfNotPresent" "IfNotPresent"   "$(D '{.spec.template.spec.containers[0].imagePullPolicy}')"
eq "container is named hello"   "hello"            "$(D '{.spec.template.spec.containers[0].name}')"
eq "port 8080 named http"       "http"             "$(D '{.spec.template.spec.containers[0].ports[0].name}')"
eq "containerPort is 8080"      "8080"             "$(D '{.spec.template.spec.containers[0].ports[0].containerPort}')"
eq "APP_VERSION=1.1.0"          "1.1.0"            "$(E APP_VERSION)"
eq "GREETING=shalom"            "shalom"           "$(E GREETING)"

if k -n $NS get deploy broken >/dev/null 2>&1; then
  bad "the 'broken' deployment is still there - delete it once you have read its events"
else
  ok "the 'broken' deployment was cleaned up"
fi

POD="$(k -n $NS get pod -l app=hello -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
BODY="$(k -n $NS exec "$POD" -- wget -qO- --timeout=5 http://127.0.0.1:8080/ 2>/dev/null)"
case "$BODY" in
  *shalom*1.1.0*) ok "the app answers with the configured greeting and version" ;;
  "")             bad "could not reach the app inside the Pod" ;;
  *)              bad "unexpected response from the app: $(echo "$BODY" | head -2 | tr '\n' ' ')" ;;
esac
finish
