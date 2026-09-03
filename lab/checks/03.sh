source "$(dirname "$0")/_lib.sh"
NS=lesson-03
if ! k get ns $NS >/dev/null 2>&1; then bad "namespace $NS exists"; finish; fi
ok "namespace $NS exists"
if ! k -n $NS get pod web >/dev/null 2>&1; then bad "pod 'web' exists in $NS"; finish; fi
ok "pod 'web' exists"
J() { k -n $NS get pod web -o jsonpath="$1" 2>/dev/null; }
eq "pod is Running"              "Running"           "$(J '{.status.phase}')"
eq "label app=web"               "web"               "$(J '{.metadata.labels.app}')"
eq "container named nginx"       "nginx"             "$(J '{.spec.containers[0].name}')"
eq "image nginx:1.29-alpine"     "nginx:1.29-alpine" "$(J '{.spec.containers[0].image}')"
eq "containerPort 80 declared"   "80"                "$(J '{.spec.containers[0].ports[0].containerPort}')"
eq "init container named seed"   "seed"              "$(J '{.spec.initContainers[0].name}')"
INIT_IMG="$(J '{.spec.initContainers[0].image}')"
case "$INIT_IMG" in busybox*) ok "init container uses busybox ($INIT_IMG)";; *) bad "init container should use busybox, got '$INIT_IMG'";; esac
if [ -n "$(J '{.spec.volumes[?(@.emptyDir)].name}')" ]; then ok "an emptyDir volume is defined"; else bad "no emptyDir volume defined"; fi
BODY="$(k -n $NS exec web -c nginx -- wget -qO- http://127.0.0.1/ 2>/dev/null | tr -d '\r\n')"
eq "nginx serves the init container's file" "hello from init" "$BODY"
finish
