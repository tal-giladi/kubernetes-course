source "$(dirname "$0")/_lib.sh"
NS=lesson-18

if ! k -n $NS get quota team-quota >/dev/null 2>&1; then bad "resourcequota 'team-quota' missing in $NS"; finish; fi
ok "resourcequota 'team-quota' exists"
Q() { k -n $NS get quota team-quota -o jsonpath="{.spec.hard.$1}" 2>/dev/null; }
eq "hard pods is 5"                  "5"     "$(Q 'pods')"
eq "hard requests\.cpu is 500m"      "500m"  "$(Q 'requests\.cpu')"
eq "hard requests\.memory is 512Mi"  "512Mi" "$(Q 'requests\.memory')"
eq "hard count/deployments.apps is 2" "2"    "$(Q 'count/deployments\.apps')"
if [ -n "$(k -n $NS get quota team-quota -o jsonpath='{.status.used.pods}' 2>/dev/null)" ]; then
  ok "the quota is tracking usage ($(k -n $NS get quota team-quota -o jsonpath='{.status.used.pods}') pods used)"
else
  bad "the quota reports no usage"
fi

if ! k -n $NS get limitrange defaults >/dev/null 2>&1; then bad "limitrange 'defaults' missing"; finish; fi
ok "limitrange 'defaults' exists"
L() { k -n $NS get limitrange defaults -o jsonpath="{.spec.limits[0].$1}" 2>/dev/null; }
eq "default cpu limit is 200m"       "200m"  "$(L 'default.cpu')"
eq "defaultRequest cpu is 100m"      "100m"  "$(L 'defaultRequest.cpu')"
eq "max cpu is 500m"                 "500m"  "$(L 'max.cpu')"

if ! k -n $NS get deploy hello >/dev/null 2>&1; then bad "deployment 'hello' missing"; finish; fi
ok "deployment 'hello' exists"
eq "2 replicas Ready" "2" "$(k -n $NS get deploy hello -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"

TPL="$(k -n $NS get deploy hello -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null)"
POD="$(k -n $NS get pod -l app=hello -o jsonpath='{.items[0].spec.containers[0].resources.requests.cpu}' 2>/dev/null)"
if [ -z "$TPL" ]; then ok "the Deployment template still declares no resources"; else bad "the template declares cpu=$TPL - leave it blank so the LimitRange can fill it"; fi
eq "the Pod received the injected request" "100m" "$POD"
eq "the Pod received the injected limit"   "200m" \
   "$(k -n $NS get pod -l app=hello -o jsonpath='{.items[0].spec.containers[0].resources.limits.cpu}' 2>/dev/null)"
finish
