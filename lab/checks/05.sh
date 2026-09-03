source "$(dirname "$0")/_lib.sh"
NS=lesson-05
if ! k -n $NS get deploy web >/dev/null 2>&1; then bad "deployment 'web' exists in $NS"; finish; fi
ok "deployment 'web' exists"
J() { k -n $NS get deploy web -o jsonpath="$1" 2>/dev/null; }
eq "spec.replicas is 5"        "5"                 "$(J '{.spec.replicas}')"
eq "5 replicas are Ready"      "5"                 "$(J '{.status.readyReplicas}')"
eq "rolled back to 1.27-alpine" "nginx:1.27-alpine" "$(J '{.spec.template.spec.containers[0].image}')"
REV="$(J '{.metadata.annotations.deployment\.kubernetes\.io/revision}')"
if [ "${REV:-0}" -ge 3 ] 2>/dev/null; then ok "revision is $REV (rolled forward and back)"; else bad "revision is '${REV:-none}', expected >= 3 - roll forward to 1.29 and undo"; fi
RS="$(k -n $NS get rs -l app=web --no-headers 2>/dev/null | wc -l | tr -d ' ')"
if [ "${RS:-0}" -ge 2 ] 2>/dev/null; then ok "$RS ReplicaSets kept (rollback history)"; else bad "expected >= 2 ReplicaSets, found ${RS:-0}"; fi
finish
