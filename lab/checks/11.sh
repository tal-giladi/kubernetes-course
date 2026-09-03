source "$(dirname "$0")/_lib.sh"
NS=lesson-11

if ! k -n $NS get cm app-config >/dev/null 2>&1; then bad "configmap 'app-config' missing"; finish; fi
ok "configmap 'app-config' exists"
eq "app-config has GREETING=shalom" "shalom" "$(k -n $NS get cm app-config -o jsonpath='{.data.GREETING}' 2>/dev/null)"
if k -n $NS get cm app-config -o jsonpath='{.data.app\.conf}' 2>/dev/null | grep -q 'timeout'; then
  ok "app-config carries the app.conf file"
else
  bad "app-config has no app.conf key with a timeout setting"
fi

eq "secret 'db-creds' is Opaque" "Opaque" "$(k -n $NS get secret db-creds -o jsonpath='{.type}' 2>/dev/null)"
PW="$(k -n $NS get secret db-creds -o jsonpath='{.data.DB_PASSWORD}' 2>/dev/null | base64 -d 2>/dev/null)"
eq "DB_PASSWORD decodes to hunter2" "hunter2" "$PW"

if ! k -n $NS get deploy hello >/dev/null 2>&1; then bad "deployment 'hello' missing"; finish; fi
ok "deployment 'hello' exists"
D() { k -n $NS get deploy hello -o jsonpath="$1" 2>/dev/null; }
eq "2 replicas Ready" "2" "$(D '{.status.readyReplicas}')"
eq "GREETING comes from the ConfigMap" "app-config" \
   "$(D "{.spec.template.spec.containers[0].env[?(@.name=='GREETING')].valueFrom.configMapKeyRef.name}")"
eq "DB_PASSWORD comes from the Secret" "db-creds" \
   "$(D "{.spec.template.spec.containers[0].env[?(@.name=='DB_PASSWORD')].valueFrom.secretKeyRef.name}")"
eq "the ConfigMap is mounted at /etc/hello" "/etc/hello" \
   "$(D '{.spec.template.spec.containers[0].volumeMounts[?(@.name)].mountPath}' | tr ' ' '\n' | grep -x '/etc/hello')"

OUT="$(k -n $NS exec deploy/hello -- wget -qO- --timeout=5 http://127.0.0.1:8080/config 2>/dev/null)"
case "$OUT" in *"GREETING=shalom"*) ok "the container sees GREETING=shalom" ;; *) bad "GREETING not visible in the container's environment" ;; esac
case "$OUT" in *"DB_PASSWORD=hunter2"*) ok "the container sees DB_PASSWORD" ;; *) bad "DB_PASSWORD not visible in the container's environment" ;; esac
case "$OUT" in *"/etc/hello/app.conf"*) ok "app.conf is mounted as a file" ;; *) bad "no /etc/hello/app.conf inside the container" ;; esac
finish
