source "$(dirname "$0")/_lib.sh"
NS=lesson-04
if ! k -n $NS get deploy web >/dev/null 2>&1; then bad "deployment 'web' exists in $NS"; finish; fi
ok "deployment 'web' exists"
D() { k -n $NS get deploy web -o jsonpath="$1" 2>/dev/null; }

eq "spec.replicas is 5"   "5" "$(D '{.spec.replicas}')"
eq "5 replicas are Ready" "5" "$(D '{.status.readyReplicas}')"
eq "image is nginx:1.29-alpine" "nginx:1.29-alpine" "$(D '{.spec.template.spec.containers[0].image}')"
eq "selector is app=web"  "web" "$(D '{.spec.selector.matchLabels.app}')"

HASHES="$(k -n $NS get pods -l app=web -o jsonpath='{.items[*].metadata.labels.pod-template-hash}' 2>/dev/null | tr ' ' '\n' | sort -u | grep -c .)"
if [ "${HASHES:-0}" -ge 1 ]; then ok "Pods carry a pod-template-hash label"; else bad "no pod-template-hash on the web Pods"; fi

if ! k -n $NS get rs rs-demo >/dev/null 2>&1; then bad "bare ReplicaSet 'rs-demo' exists"; finish; fi
ok "bare ReplicaSet 'rs-demo' exists"
R() { k -n $NS get rs rs-demo -o jsonpath="$1" 2>/dev/null; }
eq "rs-demo wants 2 replicas"  "2" "$(R '{.spec.replicas}')"
eq "rs-demo has 2 Ready"       "2" "$(R '{.status.readyReplicas}')"
eq "rs-demo selects app=demo"  "demo" "$(R '{.spec.selector.matchLabels.app}')"

OWNER="$(R '{.metadata.ownerReferences[0].kind}')"
if [ -z "$OWNER" ]; then ok "rs-demo is genuinely bare (no owning Deployment)"; else bad "rs-demo is owned by a $OWNER - it must be a standalone ReplicaSet"; fi
finish
