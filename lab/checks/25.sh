source "$(dirname "$0")/_lib.sh"
NS=lesson-25
H='Host: shop25.localtest.me'

eq "the namespace enforces 'restricted'" "restricted" \
   "$(k get ns $NS -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)"

# --- stateless tier ---------------------------------------------------------
if ! k -n $NS get deploy api >/dev/null 2>&1; then bad "deployment 'api' missing"; finish; fi
ok "deployment 'api' exists"
D() { k -n $NS get deploy api -o jsonpath="$1" 2>/dev/null; }
C() { D "{.spec.template.spec.containers[0].$1}"; }
R="$(D '{.status.readyReplicas}')"
if [ "${R:-0}" -ge 2 ]; then ok "api has $R replicas Ready"; else bad "api has ${R:-0} Ready, expected at least 2"; fi
eq "runs as the 'shop' ServiceAccount" "shop"  "$(D '{.spec.template.spec.serviceAccountName}')"
eq "no API token is mounted"           "false" "$(D '{.spec.template.spec.automountServiceAccountToken}')"
for probe in startupProbe readinessProbe livenessProbe; do
  if [ -n "$(C "$probe.httpGet.path")" ]; then ok "api has a $probe"; else bad "api has no $probe"; fi
done
if [ -n "$(C 'resources.requests.cpu')" ] && [ -n "$(C 'resources.limits.memory')" ]; then
  ok "api declares requests and limits"
else
  bad "api is missing CPU requests or memory limits"
fi
eq "readOnlyRootFilesystem"      "true"           "$(C 'securityContext.readOnlyRootFilesystem')"
eq "capabilities dropped"        "ALL"            "$(C 'securityContext.capabilities.drop[0]')"
eq "seccompProfile"              "RuntimeDefault" "$(D '{.spec.template.spec.securityContext.seccompProfile.type}')"
if [ -n "$(D '{.spec.template.spec.topologySpreadConstraints[0].topologyKey}')" ]; then
  ok "api spreads across nodes"
else
  bad "api has no topologySpreadConstraints"
fi
if [ -n "$(C 'lifecycle.preStop')" ]; then ok "api has a preStop hook"; else bad "api has no preStop hook"; fi
if k -n $NS get svc api >/dev/null 2>&1; then ok "service 'api' exists"; else bad "service 'api' missing"; fi

CFG="$(k -n $NS exec deploy/api -- wget -qO- --timeout=5 http://127.0.0.1:8080/config 2>/dev/null)"
case "$CFG" in *"GREETING=shop"*)      ok "the ConfigMap value reached the container" ;; *) bad "GREETING did not reach the container" ;; esac
case "$CFG" in *"DB_PASSWORD="*)       ok "the Secret value reached the container"    ;; *) bad "DB_PASSWORD did not reach the container" ;; esac
case "$CFG" in *"/etc/hello/app.conf"*) ok "the ConfigMap is mounted at /etc/hello"   ;; *) bad "app.conf is not mounted" ;; esac

# --- stateful tier ----------------------------------------------------------
if ! k -n $NS get sts db >/dev/null 2>&1; then bad "statefulset 'db' missing"; else
  ok "statefulset 'db' exists"
  eq "db has 2 Ready replicas" "2"    "$(k -n $NS get sts db -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
  eq "db is fronted by a headless Service" "None" "$(k -n $NS get svc db -o jsonpath='{.spec.clusterIP}' 2>/dev/null)"
  for i in 0 1; do
    if k -n $NS get pvc data-db-$i >/dev/null 2>&1; then ok "pvc data-db-$i exists"; else bad "pvc data-db-$i missing"; fi
  done
fi

# --- elasticity and safety --------------------------------------------------
if k -n $NS get hpa api >/dev/null 2>&1; then
  ok "hpa 'api' exists"
  eq "min 2"  "2"  "$(k -n $NS get hpa api -o jsonpath='{.spec.minReplicas}' 2>/dev/null)"
  eq "max 6"  "6"  "$(k -n $NS get hpa api -o jsonpath='{.spec.maxReplicas}' 2>/dev/null)"
  eq "60% CPU target" "60" "$(k -n $NS get hpa api -o jsonpath='{.spec.metrics[0].resource.target.averageUtilization}' 2>/dev/null)"
else
  bad "hpa 'api' missing"
fi
if k -n $NS get pdb api >/dev/null 2>&1; then
  ok "poddisruptionbudget 'api' exists"
  eq "minAvailable 2" "2" "$(k -n $NS get pdb api -o jsonpath='{.spec.minAvailable}' 2>/dev/null)"
else
  bad "poddisruptionbudget 'api' missing"
fi
for p in default-deny-ingress allow-ingress-to-api allow-api-to-db; do
  if k -n $NS get netpol $p >/dev/null 2>&1; then ok "networkpolicy '$p' exists"; else bad "networkpolicy '$p' missing"; fi
done

# --- end to end -------------------------------------------------------------
if ! k -n $NS get ingress shop25 >/dev/null 2>&1; then bad "ingress 'shop25' missing"; finish; fi
ok "ingress 'shop25' exists"
eq "TLS secret is shop25-tls" "shop25-tls" "$(k -n $NS get ingress shop25 -o jsonpath='{.spec.tls[0].secretName}' 2>/dev/null)"
eq "shop25-tls is a TLS secret" "kubernetes.io/tls" "$(k -n $NS get secret shop25-tls -o jsonpath='{.type}' 2>/dev/null)"

BODY="$(curl -s --max-time 10 -H "$H" http://localhost/ 2>/dev/null)"
case "$BODY" in *"shop from"*) ok "http://shop25.localtest.me/ serves the app end to end" ;; *) bad "HTTP through the ingress returned: $(echo "$BODY" | head -1)" ;; esac
TLSB="$(curl -sk --max-time 10 -H "$H" https://localhost/ 2>/dev/null)"
case "$TLSB" in *"shop from"*) ok "HTTPS works through the ingress" ;; *) bad "HTTPS through the ingress returned: $(echo "$TLSB" | head -1)" ;; esac

# an unlabelled Pod in the same namespace must be blocked by default-deny
if k -n $NS get pod netprobe >/dev/null 2>&1; then k -n $NS delete pod netprobe --ignore-not-found >/dev/null 2>&1; fi
k -n $NS run netprobe --image=busybox:1.37 --restart=Never --command \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":65532,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"netprobe","image":"busybox:1.37","command":["sh","-c","wget -qO- -T5 http://api:8080/ >/dev/null 2>&1 && echo REACHED || echo BLOCKED"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}' >/dev/null 2>&1
k -n $NS wait --for=jsonpath='{.status.phase}'=Succeeded pod/netprobe --timeout=90s >/dev/null 2>&1
VERDICT="$(k -n $NS logs netprobe 2>/dev/null | tr -d '\r\n')"
k -n $NS delete pod netprobe --ignore-not-found >/dev/null 2>&1
case "$VERDICT" in
  BLOCKED) ok "an unlabelled Pod cannot reach the api - default-deny is in force" ;;
  REACHED) bad "an unlabelled Pod reached the api - the default-deny policy is not working" ;;
  *)       bad "could not run the network probe (got '$VERDICT')" ;;
esac
finish
