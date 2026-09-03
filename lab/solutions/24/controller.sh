#!/usr/bin/env bash
# A controller, in as few lines as the idea allows.
#
#   bash controller.sh --once     one reconcile pass
#   bash controller.sh            loop for ever, every 5s (Ctrl-C to stop)
#
# It is level-triggered: it never looks at events, only at current state. Run it twice and
# nothing changes; delete what it made and it rebuilds it. Real controllers are Go
# programs with informer caches and work queues, but this is the shape they all have.
set -u
NS="${NS:-lesson-24}"
ONCE=0; [ "${1:-}" = "--once" ] && ONCE=1

reconcile_one() {
  local name="$1"
  # --- observe desired state -------------------------------------------------
  local msg uid cm
  msg="$(kubectl -n "$NS" get greeting "$name" -o jsonpath='{.spec.message}')"
  uid="$(kubectl -n "$NS" get greeting "$name" -o jsonpath='{.metadata.uid}')"
  cm="greeting-$name"

  # --- converge actual state to it -------------------------------------------
  # `create --dry-run=client | apply` is the shell version of "create or update":
  # idempotent, and safe to run on every pass.
  kubectl -n "$NS" create configmap "$cm" \
      --from-literal=message="$msg" \
      --dry-run=client -o yaml | kubectl -n "$NS" apply -f - >/dev/null

  # Ownership, not cleanup code: the garbage collector deletes this ConfigMap when the
  # Greeting is deleted, with nothing else to write.
  kubectl -n "$NS" patch configmap "$cm" --type=merge -p "$(cat <<JSON
{"metadata":{"ownerReferences":[{"apiVersion":"k8slab.dev/v1alpha1","kind":"Greeting","name":"$name","uid":"$uid","controller":true,"blockOwnerDeletion":true}]}}
JSON
)" >/dev/null

  # --- report what is true ----------------------------------------------------
  kubectl -n "$NS" patch greeting "$name" --subresource=status --type=merge \
    -p "{\"status\":{\"configMapName\":\"$cm\"}}" >/dev/null

  echo "  reconciled greeting/$name -> configmap/$cm"
}

pass() {
  echo "reconcile pass at $(date +%H:%M:%S)"
  local names
  names="$(kubectl -n "$NS" get greetings -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)"
  [ -z "$names" ] && { echo "  no Greetings in $NS"; return; }
  for n in $names; do reconcile_one "$n"; done
}

if [ "$ONCE" = "1" ]; then
  pass
else
  while true; do pass; sleep 5; done
fi
