source "$(dirname "$0")/_lib.sh"
NS=lesson-14

if ! k -n $NS get deploy hello >/dev/null 2>&1; then bad "deployment 'hello' missing in $NS"; finish; fi
ok "deployment 'hello' exists"
C() { k -n $NS get deploy hello -o jsonpath="{.spec.template.spec.containers[0].$1}" 2>/dev/null; }

eq "3 replicas Ready" "3" "$(k -n $NS get deploy hello -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
eq "readinessProbe hits /readyz"  "/readyz"  "$(C 'readinessProbe.httpGet.path')"
eq "livenessProbe hits /healthz"  "/healthz" "$(C 'livenessProbe.httpGet.path')"
eq "startupProbe hits /healthz"   "/healthz" "$(C 'startupProbe.httpGet.path')"
eq "readiness period is 5s"       "5"        "$(C 'readinessProbe.periodSeconds')"

SF="$(C 'startupProbe.failureThreshold')"
if [ "${SF:-0}" -ge 10 ]; then ok "startupProbe allows a real boot budget (failureThreshold $SF)"; else bad "startupProbe failureThreshold is ${SF:-unset}, expected >= 10"; fi

if [ -n "$(C 'lifecycle.preStop.exec.command')" ]; then ok "a preStop hook is configured"; else bad "no preStop hook - deletes will race endpoint removal"; fi
eq "terminationGracePeriodSeconds is 30" "30" "$(k -n $NS get deploy hello -o jsonpath='{.spec.template.spec.terminationGracePeriodSeconds}' 2>/dev/null)"

if ! k -n $NS get deploy flaky >/dev/null 2>&1; then bad "deployment 'flaky' missing"; finish; fi
ok "deployment 'flaky' exists"
R="$(k -n $NS get pods -l app=flaky -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null)"
if [ "${R:-0}" -ge 1 ]; then
  ok "flaky has restarted $R time(s) - the liveness probe is killing it, as designed"
else
  bad "flaky has 0 restarts; give it ~40s, or check FAIL_LIVENESS_AFTER_SECONDS and the probe"
fi
finish
