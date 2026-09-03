source "$(dirname "$0")/_lib.sh"
NS=lesson-07
NODES="$(k get nodes --no-headers 2>/dev/null | grep -c .)"

if k -n $NS get ds node-probe >/dev/null 2>&1; then
  ok "daemonset 'node-probe' exists"
  DS() { k -n $NS get ds node-probe -o jsonpath="$1" 2>/dev/null; }
  eq "scheduled on all $NODES nodes" "$NODES" "$(DS '{.status.desiredNumberScheduled}')"
  eq "all $NODES are Ready"          "$NODES" "$(DS '{.status.numberReady}')"
  if [ -n "$(DS '{.spec.template.spec.tolerations[?(@.effect=="NoSchedule")].key}')" ]; then
    ok "it tolerates the control-plane taint"
  else
    bad "no NoSchedule toleration - the control-plane node is being skipped"
  fi
else
  bad "daemonset 'node-probe' missing"
fi

if k -n $NS get job pi >/dev/null 2>&1; then
  ok "job 'pi' exists"
  J() { k -n $NS get job pi -o jsonpath="$1" 2>/dev/null; }
  eq "completions: 3"       "3"     "$(J '{.spec.completions}')"
  eq "parallelism: 2"       "2"     "$(J '{.spec.parallelism}')"
  eq "3 Pods succeeded"     "3"     "$(J '{.status.succeeded}')"
  eq "restartPolicy Never"  "Never" "$(J '{.spec.template.spec.restartPolicy}')"
else
  bad "job 'pi' missing"
fi

if k -n $NS get cronjob heartbeat >/dev/null 2>&1; then
  ok "cronjob 'heartbeat' exists"
  C() { k -n $NS get cronjob heartbeat -o jsonpath="$1" 2>/dev/null; }
  eq "runs every minute"                "* * * * *" "$(C '{.spec.schedule}')"
  eq "concurrencyPolicy Forbid"         "Forbid"    "$(C '{.spec.concurrencyPolicy}')"
  eq "successfulJobsHistoryLimit 2"     "2"         "$(C '{.spec.successfulJobsHistoryLimit}')"
  SUS="$(C '{.spec.suspend}')"
  if [ "$SUS" = "true" ]; then bad "the cronjob is still suspended - unsuspend it"; else ok "the cronjob is active"; fi
  if [ -n "$(C '{.status.lastScheduleTime}')" ]; then ok "it has fired at least once"; else bad "it has never fired - give it a minute"; fi
else
  bad "cronjob 'heartbeat' missing"
fi
finish
