source "$(dirname "$0")/_lib.sh"
NS=lesson-21

# Read the release straight out of its Helm storage Secrets - no helm binary needed.
REVS="$(k -n $NS get secret -l owner=helm,name=shop -o jsonpath='{.items[*].metadata.labels.version}' 2>/dev/null)"
if [ -z "$REVS" ]; then bad "no Helm release called 'shop' in $NS (looked for its release Secrets)"; finish; fi
ok "helm release 'shop' exists in $NS"
COUNT="$(echo "$REVS" | wc -w | tr -d ' ')"
if [ "${COUNT:-0}" -ge 2 ]; then
  ok "it has $COUNT revisions - you upgraded, not just installed"
else
  bad "only $COUNT revision; upgrade the release at least once"
fi

DEPLOY="$(k -n $NS get deploy -l app.kubernetes.io/instance=shop -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
if [ -z "$DEPLOY" ]; then bad "the release created no Deployment labelled app.kubernetes.io/instance=shop"; finish; fi
ok "the release owns deployment '$DEPLOY'"
D() { k -n $NS get deploy "$DEPLOY" -o jsonpath="$1" 2>/dev/null; }
eq "3 replicas Ready" "3" "$(D '{.status.readyReplicas}')"
eq "the image is hello:1.1.0" "hello:1.1.0" "$(D '{.spec.template.spec.containers[0].image}')"
eq "the greeting value was templated in" "shalom-helm" \
   "$(D "{.spec.template.spec.containers[0].env[?(@.name=='GREETING')].value}")"

case "$DEPLOY" in
  shop*) ok "resource names are derived from the release name ($DEPLOY)" ;;
  *)     bad "'$DEPLOY' is not derived from the release name - check the fullname helper" ;;
esac

if k -n $NS get svc -l app.kubernetes.io/instance=shop >/dev/null 2>&1 && \
   [ -n "$(k -n $NS get svc -l app.kubernetes.io/instance=shop -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)" ]; then
  ok "the chart also created a Service"
else
  bad "no Service belongs to the release"
fi

POD="$(k -n $NS get pod -l app.kubernetes.io/instance=shop -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
if k -n $NS exec "$POD" -- wget -qO- --timeout=5 http://127.0.0.1:8080/ 2>/dev/null | grep -q 'shalom-helm'; then
  ok "the running app greets with the value from values.yaml"
else
  bad "the app is not serving the templated greeting"
fi
finish
