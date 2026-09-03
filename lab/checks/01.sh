source "$(dirname "$0")/_lib.sh"
NS=lesson-01
yes_ "namespace $NS exists" k get ns $NS
if k -n $NS get cm answers >/dev/null 2>&1; then
  ok "configmap answers exists"
  get() { k -n $NS get cm answers -o jsonpath="{.data.$1}" 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d ' '; }
  eq "nodes"         "3"              "$(get nodes)"
  eq "apiserver"     "kube-apiserver" "$(get apiserver)"
  eq "cni"           "kindnet"        "$(get cni)"
  eq "desired-state" "spec"           "$(get 'desired-state')"
else
  bad "configmap 'answers' not found in $NS"
fi
finish
