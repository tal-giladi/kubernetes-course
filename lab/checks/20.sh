source "$(dirname "$0")/_lib.sh"
NS=lesson-20

eq "the namespace enforces the restricted profile" "restricted" \
   "$(k get ns $NS -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)"

if ! k -n $NS get deploy hello >/dev/null 2>&1; then bad "deployment 'hello' missing in $NS"; finish; fi
ok "deployment 'hello' exists"
eq "2 replicas Ready" "2" "$(k -n $NS get deploy hello -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
P() { k -n $NS get deploy hello -o jsonpath="{.spec.template.spec.securityContext.$1}" 2>/dev/null; }
C() { k -n $NS get deploy hello -o jsonpath="{.spec.template.spec.containers[0].securityContext.$1}" 2>/dev/null; }
eq "runAsNonRoot: true"                "true"           "$(P 'runAsNonRoot')"
eq "seccompProfile RuntimeDefault"     "RuntimeDefault" "$(P 'seccompProfile.type')"
eq "allowPrivilegeEscalation: false"   "false"          "$(C 'allowPrivilegeEscalation')"
eq "readOnlyRootFilesystem: true"      "true"           "$(C 'readOnlyRootFilesystem')"
eq "all capabilities dropped"          "ALL"            "$(C 'capabilities.drop[0]')"

# A Pod that breaks the profile must be refused at admission.
if k -n $NS run psa-probe --image=nginx:1.29-alpine --restart=Never >/dev/null 2>&1; then
  bad "a default nginx Pod was ACCEPTED - the restricted profile is not being enforced"
  k -n $NS delete pod psa-probe --ignore-not-found >/dev/null 2>&1
else
  ok "a non-compliant Pod is rejected at admission"
fi

for p in default-deny-ingress allow-client; do
  if k -n $NS get netpol $p >/dev/null 2>&1; then ok "networkpolicy '$p' exists"; else bad "networkpolicy '$p' missing"; fi
done

if k -n $NS exec deploy/client-allowed -- wget -qO- -T5 http://hello:8080/ 2>/dev/null | grep -q .; then
  ok "client-allowed (role=client) can reach hello:8080"
else
  bad "client-allowed cannot reach hello:8080 - the allow rule is not matching"
fi

if k -n $NS exec deploy/client-denied -- wget -qO- -T5 http://hello:8080/ 2>/dev/null | grep -q .; then
  bad "client-denied (role=other) CAN reach hello:8080 - the default-deny is not in effect"
else
  ok "client-denied (role=other) is blocked, as intended"
fi
finish
