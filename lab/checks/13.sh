source "$(dirname "$0")/_lib.sh"
NS=lesson-13

eq "headless service 'db' has no ClusterIP" "None" "$(k -n $NS get svc db -o jsonpath='{.spec.clusterIP}' 2>/dev/null)"

if ! k -n $NS get sts db >/dev/null 2>&1; then bad "statefulset 'db' missing in $NS"; finish; fi
ok "statefulset 'db' exists"
S() { k -n $NS get sts db -o jsonpath="$1" 2>/dev/null; }
eq "serviceName points at the headless Service" "db" "$(S '{.spec.serviceName}')"
eq "3 replicas Ready" "3" "$(S '{.status.readyReplicas}')"
eq "the claim template is named 'data'" "data" "$(S '{.spec.volumeClaimTemplates[0].metadata.name}')"

for i in 0 1 2; do
  if k -n $NS get pod db-$i >/dev/null 2>&1; then ok "pod db-$i exists (ordinal identity)"; else bad "pod db-$i missing"; fi
  if k -n $NS get pvc data-db-$i >/dev/null 2>&1; then ok "pvc data-db-$i exists (its own disk)"; else bad "pvc data-db-$i missing"; fi
done

# busybox nslookup exits non-zero once any search-domain permutation misses, so judge it
# on the answer it printed, not on its exit code.
# Use the FQDN: these images are Alpine, and musl only applies the resolv.conf search list
# to names with no dot at all - so "db-1.db" fails there while the full name works.
ADDRS="$(k -n $NS exec db-0 -- nslookup db-1.db.$NS.svc.cluster.local 2>/dev/null | awk '/^Name:/{f=1} f&&/Address/{c++} END{print c+0}')"
if [ "${ADDRS:-0}" -ge 1 ]; then
  ok "db-1.db resolves from inside db-0 (per-Pod DNS)"
else
  bad "db-1.db does not resolve - check spec.serviceName and the headless Service"
fi

# Prove all three guarantees at once. This check deletes db-1 on purpose.
BEFORE="$(k -n $NS exec db-1 -- wget -qO- --timeout=5 http://127.0.0.1:8080/data 2>/dev/null)"
FIRST="$(echo "$BEFORE" | head -1)"
if [ -z "$FIRST" ]; then bad "db-1 could not write to /data - check the volumeClaimTemplate mount"; finish; fi
ok "db-1 wrote to its own volume"

k -n $NS delete pod db-1 --wait=true >/dev/null 2>&1
k -n $NS wait --for=condition=Ready pod/db-1 --timeout=180s >/dev/null 2>&1
if k -n $NS get pod db-1 >/dev/null 2>&1; then
  ok "the replacement Pod is called db-1 again (stable identity)"
else
  bad "db-1 did not come back"; finish
fi

AFTER="$(k -n $NS exec db-1 -- wget -qO- --timeout=5 http://127.0.0.1:8080/data 2>/dev/null)"
if echo "$AFTER" | grep -qF "$FIRST"; then
  ok "db-1 re-attached data-db-1 with its data intact"
else
  bad "db-1's data is gone - the claim template is not being reused"
fi
OTHERS="$(echo "$AFTER" | awk '{print $2}' | sort -u | grep -vc '^db-1$' || true)"
if [ "${OTHERS:-0}" -eq 0 ]; then
  ok "the volume holds only db-1's writes (three separate disks, not one shared)"
else
  bad "db-1's volume contains another Pod's writes - that should be impossible here"
fi
finish
