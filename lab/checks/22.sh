source "$(dirname "$0")/_lib.sh"
NS=lesson-22

if ! k -n $NS get deploy prod-hello >/dev/null 2>&1; then bad "deployment 'prod-hello' missing in $NS (namePrefix + namespace from the overlay)"; finish; fi
ok "deployment 'prod-hello' exists (namePrefix applied)"
D() { k -n $NS get deploy prod-hello -o jsonpath="$1" 2>/dev/null; }

eq "3 replicas Ready"        "3"           "$(D '{.status.readyReplicas}')"
eq "the image tag was replaced" "hello:1.1.0" "$(D '{.spec.template.spec.containers[0].image}')"
eq "the env label was added"  "prod"        "$(D '{.metadata.labels.env}')"
eq "the patch added a CPU request" "50m"    "$(D '{.spec.template.spec.containers[0].resources.requests.cpu}')"

SEL="$(D '{.spec.selector.matchLabels.env}')"
if [ -z "$SEL" ]; then
  ok "the label stayed out of the immutable selector (includeSelectors: false)"
else
  bad "env=$SEL leaked into spec.selector - that selector is immutable and will break the next apply"
fi

CMREF="$(D "{.spec.template.spec.containers[0].env[?(@.name=='GREETING')].valueFrom.configMapKeyRef.name}")"
case "$CMREF" in
  prod-app-config-?*)
    ok "the Deployment references the hashed ConfigMap ($CMREF)" ;;
  "") bad "the Deployment does not take GREETING from a ConfigMap" ;;
  *)  bad "expected a generated name like prod-app-config-<hash>, got '$CMREF'" ;;
esac

if [ -n "$CMREF" ] && k -n $NS get cm "$CMREF" >/dev/null 2>&1; then
  ok "that ConfigMap exists"
  eq "its GREETING is the overlay's value" "shalom-prod" "$(k -n $NS get cm "$CMREF" -o jsonpath='{.data.GREETING}' 2>/dev/null)"
else
  bad "the referenced ConfigMap '$CMREF' does not exist - the reference was not rewritten"
fi

if k -n $NS get svc prod-hello >/dev/null 2>&1; then ok "service 'prod-hello' exists"; else bad "service 'prod-hello' missing"; fi
finish
