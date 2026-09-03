source "$(dirname "$0")/_lib.sh"
NS=lesson-02
if ! k get ns $NS >/dev/null 2>&1; then bad "namespace $NS exists"; finish; fi
ok "namespace $NS exists"

L() { k -n $NS get cm "$1" -o jsonpath="{.metadata.labels.$2}" 2>/dev/null; }
A() { k -n $NS get cm "$1" -o jsonpath="{.metadata.annotations.$2}" 2>/dev/null; }

check_cm() { # name tier env
  if ! k -n $NS get cm "$1" >/dev/null 2>&1; then bad "configmap '$1' missing"; return; fi
  eq "$1 label tier=$2" "$2" "$(L "$1" tier)"
  eq "$1 label env=$3"  "$3" "$(L "$1" env)"
}
check_cm cm-a frontend prod
check_cm cm-b frontend dev
check_cm cm-c backend  prod
check_cm cm-d backend  dev

SEL="$(k -n $NS get cm -l 'env=prod,tier=backend' -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)"
eq "selector env=prod,tier=backend matches only cm-c" "cm-c" "$SEL"

eq "cm-a annotated reviewed=true" "true" "$(A cm-a reviewed)"
eq "cm-c annotated reviewed=true" "true" "$(A cm-c reviewed)"
for n in cm-b cm-d; do
  if [ -z "$(A $n reviewed)" ]; then ok "$n was NOT annotated (selector was scoped)"; else bad "$n has reviewed=$(A $n reviewed) - the annotate hit dev too"; fi
done

eq "cm-d is immutable" "true" "$(k -n $NS get cm cm-d -o jsonpath='{.immutable}' 2>/dev/null)"
finish
