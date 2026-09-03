source "$(dirname "$0")/_lib.sh"
NS=lesson-16

eq "k8s-lab-worker is labelled disktype=ssd" "ssd" \
   "$(k get node k8s-lab-worker -o jsonpath='{.metadata.labels.disktype}' 2>/dev/null)"
eq "k8s-lab-worker2 carries the lab=demo taint" "demo" \
   "$(k get node k8s-lab-worker2 -o jsonpath="{.spec.taints[?(@.key=='lab')].value}" 2>/dev/null)"

nodes_of() { k -n $NS get pods -l app="$1" -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | grep -c .; }
uniq_nodes_of() { k -n $NS get pods -l app="$1" -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | sort -u | grep -c .; }

# pinned: every replica on the labelled node
P_TOTAL="$(nodes_of pinned)"
P_ON="$(k -n $NS get pods -l app=pinned -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | grep -cx 'k8s-lab-worker')"
if [ "${P_TOTAL:-0}" -eq 2 ] && [ "${P_ON:-0}" -eq 2 ]; then
  ok "both 'pinned' Pods are on k8s-lab-worker (nodeSelector)"
else
  bad "'pinned' has ${P_TOTAL:-0} Pods, ${P_ON:-0} of them on k8s-lab-worker; expected 2 and 2"
fi

# spread: 4 pods, skew <= 1 across the nodes they landed on
COUNTS="$(k -n $NS get pods -l app=spread -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | sort | uniq -c | awk '{print $1}')"
S_TOTAL="$(nodes_of spread)"; S_UNIQ="$(uniq_nodes_of spread)"
MAX="$(echo "$COUNTS" | sort -n | tail -1)"; MIN="$(echo "$COUNTS" | sort -n | head -1)"
if [ "${S_TOTAL:-0}" -eq 4 ] && [ "${S_UNIQ:-0}" -ge 2 ] && [ $(( ${MAX:-9} - ${MIN:-0} )) -le 1 ]; then
  ok "'spread' balanced 4 Pods over $S_UNIQ nodes with a skew of $(( ${MAX:-0} - ${MIN:-0} ))"
else
  bad "'spread' has ${S_TOTAL:-0} Pods over ${S_UNIQ:-0} node(s), counts [$(echo $COUNTS | tr '\n' ' ')]; expected 4 over 2 with skew <= 1"
fi

# apart: 2 pods, 2 distinct nodes
A_TOTAL="$(nodes_of apart)"; A_UNIQ="$(uniq_nodes_of apart)"
if [ "${A_TOTAL:-0}" -eq 2 ] && [ "${A_UNIQ:-0}" -eq 2 ]; then
  ok "'apart' put its 2 Pods on 2 different nodes (anti-affinity)"
else
  bad "'apart' has ${A_TOTAL:-0} Pods across ${A_UNIQ:-0} node(s); expected 2 across 2"
fi

# tolerant: on the tainted node
T_NODE="$(k -n $NS get pods -l app=tolerant -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)"
eq "'tolerant' runs on the tainted node" "k8s-lab-worker2" "$T_NODE"
if [ -n "$(k -n $NS get deploy tolerant -o jsonpath="{.spec.template.spec.tolerations[?(@.key=='lab')].value}" 2>/dev/null)" ]; then
  ok "'tolerant' carries a matching toleration"
else
  bad "'tolerant' has no toleration for key 'lab'"
fi
finish
