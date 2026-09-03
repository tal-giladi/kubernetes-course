source "$(dirname "$0")/_lib.sh"
NS=lesson-19
SA="system:serviceaccount:$NS:reader"

if ! k -n $NS get sa reader >/dev/null 2>&1; then bad "serviceaccount 'reader' missing in $NS"; finish; fi
ok "serviceaccount 'reader' exists"

if ! k -n $NS get role pod-reader >/dev/null 2>&1; then bad "role 'pod-reader' missing"; finish; fi
ok "role 'pod-reader' exists"

if ! k -n $NS get rolebinding -o jsonpath='{.items[*].subjects[*].name}' 2>/dev/null | grep -qw reader; then
  bad "no RoleBinding in $NS names the 'reader' ServiceAccount"
else
  ok "a RoleBinding binds the 'reader' ServiceAccount"
fi

cani() { k auth can-i "$1" "$2" -n "${3:-$NS}" --as="$SA" 2>/dev/null; }
allow() { if [ "$(cani "$1" "$2" "${3:-$NS}")" = "yes" ]; then ok "reader CAN $1 $2 in ${3:-$NS}"; else bad "reader cannot $1 $2 in ${3:-$NS}, but should"; fi; }
deny()  { if [ "$(cani "$1" "$2" "${3:-$NS}")" = "yes" ]; then bad "reader CAN $1 $2 in ${3:-$NS} - too much access"; else ok "reader cannot $1 $2 in ${3:-$NS}"; fi; }

allow list   pods
allow get    pods/log
deny  delete pods
deny  get    secrets
deny  list   pods kube-system

if ! k -n $NS get deploy hello >/dev/null 2>&1; then bad "deployment 'hello' missing"; finish; fi
ok "deployment 'hello' exists"
eq "the Pod runs as the 'reader' ServiceAccount" "reader" \
   "$(k -n $NS get deploy hello -o jsonpath='{.spec.template.spec.serviceAccountName}' 2>/dev/null)"
eq "1 replica Ready" "1" "$(k -n $NS get deploy hello -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"

POD="$(k -n $NS get pod -l app=hello -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
if k -n $NS exec "$POD" -- sh -c 'test -f /var/run/secrets/kubernetes.io/serviceaccount/token' 2>/dev/null; then
  ok "the projected ServiceAccount token is mounted in the Pod"
else
  bad "no projected token inside the Pod"
fi
finish
