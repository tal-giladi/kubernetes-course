source "$(dirname "$0")/_lib.sh"
NS=lesson-15

qos() { k -n $NS get pods -l app="$1" -o jsonpath='{.items[0].status.qosClass}' 2>/dev/null; }
eq "'guaranteed' has QoS Guaranteed" "Guaranteed" "$(qos guaranteed)"
eq "'burstable' has QoS Burstable"   "Burstable"  "$(qos burstable)"
eq "'besteffort' has QoS BestEffort" "BestEffort" "$(qos besteffort)"

G() { k -n $NS get deploy guaranteed -o jsonpath="{.spec.template.spec.containers[0].resources.$1}" 2>/dev/null; }
eq "guaranteed requests cpu 100m"   "100m"  "$(G 'requests.cpu')"
eq "guaranteed limits cpu 100m"     "100m"  "$(G 'limits.cpu')"
eq "guaranteed requests memory 128Mi" "128Mi" "$(G 'requests.memory')"

if ! k -n $NS get pod hungry >/dev/null 2>&1; then bad "pod 'hungry' missing"; else
  ok "pod 'hungry' exists"
  REASON="$(k -n $NS get pod hungry -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null)"
  [ -z "$REASON" ] && REASON="$(k -n $NS get pod hungry -o jsonpath='{.status.containerStatuses[0].state.terminated.reason}' 2>/dev/null)"
  eq "hungry was OOMKilled" "OOMKilled" "$REASON"
  eq "hungry's memory limit is 32Mi" "32Mi" "$(k -n $NS get pod hungry -o jsonpath='{.spec.containers[0].resources.limits.memory}' 2>/dev/null)"
fi

if ! k -n $NS get pod toobig >/dev/null 2>&1; then bad "pod 'toobig' missing"; else
  ok "pod 'toobig' exists"
  eq "toobig is Pending" "Pending" "$(k -n $NS get pod toobig -o jsonpath='{.status.phase}' 2>/dev/null)"
  eq "…because it is Unschedulable" "Unschedulable" \
     "$(k -n $NS get pod toobig -o jsonpath="{.status.conditions[?(@.type=='PodScheduled')].reason}" 2>/dev/null)"
fi
finish
