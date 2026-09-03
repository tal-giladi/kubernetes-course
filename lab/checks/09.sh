source "$(dirname "$0")/_lib.sh"
NS=lesson-09
if ! k -n $NS get deploy web >/dev/null 2>&1; then bad "deployment 'web' exists in $NS"; finish; fi
ok "deployment 'web' exists"
S() { k -n $NS get svc "$1" -o jsonpath="$2" 2>/dev/null; }

eq "3 replicas Ready" "3" "$(k -n $NS get deploy web -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"

for s in web web-headless web-sticky upstream; do
  if k -n $NS get svc $s >/dev/null 2>&1; then ok "service '$s' exists"; else bad "service '$s' missing"; fi
done

eq "web-headless has clusterIP None"  "None"          "$(S web-headless '{.spec.clusterIP}')"
eq "web-sticky pins by ClientIP"      "ClientIP"      "$(S web-sticky '{.spec.sessionAffinity}')"
eq "upstream is an ExternalName"      "ExternalName"  "$(S upstream '{.spec.type}')"
eq "upstream points at example.com"   "example.com"   "$(S upstream '{.spec.externalName}')"

# busybox nslookup prints the resolver first, then a "Name:" block with one Address
# line per record - count only the lines after "Name:".
count_addrs() { k -n $NS exec deploy/web -- nslookup "$1" 2>/dev/null | awk '/^Name:/{f=1} f&&/Address/{c++} END{print c+0}'; }

N="$(count_addrs web-headless)"
if [ "${N:-0}" -ge 3 ]; then
  ok "web-headless resolves to $N addresses (one per Pod)"
else
  bad "web-headless resolved to ${N:-0} addresses, expected 3 - check its selector"
fi

M="$(count_addrs web)"
if [ "${M:-0}" -eq 1 ]; then
  ok "web resolves to a single virtual IP"
else
  bad "web resolved to ${M:-0} addresses, expected exactly 1"
fi
finish
