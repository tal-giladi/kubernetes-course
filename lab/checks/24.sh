source "$(dirname "$0")/_lib.sh"
NS=lesson-24

if ! k get crd greetings.k8slab.dev >/dev/null 2>&1; then bad "CRD 'greetings.k8slab.dev' is not installed"; finish; fi
ok "CRD 'greetings.k8slab.dev' exists"
C() { k get crd greetings.k8slab.dev -o jsonpath="$1" 2>/dev/null; }
eq "it is Established" "True" "$(C "{.status.conditions[?(@.type=='Established')].status}")"
eq "group is k8slab.dev" "k8slab.dev" "$(C '{.spec.group}')"
eq "kind is Greeting"    "Greeting"   "$(C '{.spec.names.kind}')"
if [ -n "$(C '{.spec.versions[0].subresources.status}')" ]; then ok "the status subresource is enabled"; else bad "no status subresource on the CRD"; fi
if [ -n "$(C '{.spec.versions[0].additionalPrinterColumns[0].name}')" ]; then ok "custom printer columns are defined"; else bad "no additionalPrinterColumns"; fi

# The schema must actually reject something.
if k -n $NS create -f - >/dev/null 2>&1 <<'EOF'
apiVersion: k8slab.dev/v1alpha1
kind: Greeting
metadata: { name: schema-probe, namespace: lesson-24 }
spec: { replicas: 99 }
EOF
then
  bad "a Greeting with replicas=99 and no message was ACCEPTED - the schema is not constraining anything"
  k -n $NS delete greeting schema-probe --ignore-not-found >/dev/null 2>&1
else
  ok "the schema rejects an invalid Greeting"
fi

for g in shalom boker-tov; do
  if ! k -n $NS get greeting $g >/dev/null 2>&1; then bad "greeting '$g' missing"; continue; fi
  ok "greeting '$g' exists"
  MSG="$(k -n $NS get greeting $g -o jsonpath='{.spec.message}' 2>/dev/null)"
  CM="$(k -n $NS get greeting $g -o jsonpath='{.status.configMapName}' 2>/dev/null)"
  if [ -z "$CM" ]; then bad "  $g has no status.configMapName - the controller has not reconciled it"; continue; fi
  ok "  its status names configmap '$CM'"
  if ! k -n $NS get cm "$CM" >/dev/null 2>&1; then bad "  configmap '$CM' does not exist"; continue; fi
  eq "  $CM carries the Greeting's message" "$MSG" "$(k -n $NS get cm "$CM" -o jsonpath='{.data.message}' 2>/dev/null)"
  OWNER="$(k -n $NS get cm "$CM" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null)"
  ONAME="$(k -n $NS get cm "$CM" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null)"
  if [ "$OWNER" = "Greeting" ] && [ "$ONAME" = "$g" ]; then
    ok "  it is owned by greeting/$g (so the GC will clean it up)"
  else
    bad "  no ownerReference back to greeting/$g - deleting the Greeting would orphan it"
  fi
done
finish
