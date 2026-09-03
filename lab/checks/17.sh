source "$(dirname "$0")/_lib.sh"
NS=lesson-17

if k top nodes >/dev/null 2>&1; then ok "metrics-server is serving metrics.k8s.io"; else bad "kubectl top nodes failed - metrics-server is missing or unhealthy"; fi

if ! k -n $NS get deploy hello >/dev/null 2>&1; then bad "deployment 'hello' missing in $NS"; finish; fi
ok "deployment 'hello' exists"
eq "the container has a CPU request" "100m" \
   "$(k -n $NS get deploy hello -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null)"

if ! k -n $NS get hpa hello >/dev/null 2>&1; then bad "hpa 'hello' missing"; finish; fi
ok "hpa 'hello' exists"
H() { k -n $NS get hpa hello -o jsonpath="$1" 2>/dev/null; }
eq "minReplicas 1"          "1"     "$(H '{.spec.minReplicas}')"
eq "maxReplicas 5"          "5"     "$(H '{.spec.maxReplicas}')"
eq "targets 50% CPU"        "50"    "$(H '{.spec.metrics[0].resource.target.averageUtilization}')"
eq "it targets the Deployment" "hello" "$(H '{.spec.scaleTargetRef.name}')"

ACTIVE="$(H "{.status.conditions[?(@.type=='ScalingActive')].status}")"
if [ "$ACTIVE" = "True" ]; then
  ok "ScalingActive=True - the HPA is reading real CPU metrics"
else
  bad "ScalingActive=$ACTIVE - the HPA cannot compute utilisation (metrics-server, or a missing CPU request)"
fi

if ! k -n $NS get pdb hello >/dev/null 2>&1; then bad "poddisruptionbudget 'hello' missing"; finish; fi
ok "poddisruptionbudget 'hello' exists"
eq "minAvailable is 1" "1" "$(k -n $NS get pdb hello -o jsonpath='{.spec.minAvailable}' 2>/dev/null)"
HEALTHY="$(k -n $NS get pdb hello -o jsonpath='{.status.currentHealthy}' 2>/dev/null)"
if [ "${HEALTHY:-0}" -ge 1 ]; then ok "the PDB sees $HEALTHY healthy Pod(s)"; else bad "the PDB matches no healthy Pods - check its selector"; fi
finish
