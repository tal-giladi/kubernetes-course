source "$(dirname "$0")/_lib.sh"
NS=lesson-10

READY="$(k -n ingress-nginx get pods -l app.kubernetes.io/component=controller -o jsonpath='{.items[*].status.containerStatuses[0].ready}' 2>/dev/null)"
case "$READY" in
  *true*) ok "the ingress-nginx controller is running" ;;
  *)      bad "no ready ingress-nginx controller Pod - install it first"; finish ;;
esac

for d in web api; do
  R="$(k -n $NS get deploy $d -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
  if [ "${R:-0}" -ge 2 ]; then ok "deployment '$d' has $R replicas Ready"; else bad "deployment '$d' has ${R:-0} Ready, expected 2"; fi
  if k -n $NS get svc $d >/dev/null 2>&1; then ok "service '$d' exists"; else bad "service '$d' missing"; fi
done

if ! k -n $NS get ingress shop >/dev/null 2>&1; then bad "ingress 'shop' missing"; finish; fi
ok "ingress 'shop' exists"
I() { k -n $NS get ingress shop -o jsonpath="$1" 2>/dev/null; }
eq "ingressClassName is nginx"   "nginx"             "$(I '{.spec.ingressClassName}')"
eq "host is shop.localtest.me"   "shop.localtest.me" "$(I '{.spec.rules[0].host}')"
eq "TLS uses the shop-tls secret" "shop-tls"         "$(I '{.spec.tls[0].secretName}')"

PATHS="$(I '{.spec.rules[0].http.paths[*].path}')"
case "$PATHS" in
  *"/api"*) ok "there is a /api rule" ;;
  *)        bad "no /api path rule (found: $PATHS)" ;;
esac

eq "shop-tls is a TLS secret" "kubernetes.io/tls" "$(k -n $NS get secret shop-tls -o jsonpath='{.type}' 2>/dev/null)"

H='Host: shop.localtest.me'
BODY_WEB="$(curl -s --max-time 10 -H "$H" http://localhost/ 2>/dev/null)"
BODY_API="$(curl -s --max-time 10 -H "$H" http://localhost/api 2>/dev/null)"
case "$BODY_WEB" in *"web from"*) ok "http://localhost/ routes to the web backend" ;; *) bad "GET / returned: $(echo "$BODY_WEB" | head -1)" ;; esac
case "$BODY_API" in *"api from"*) ok "http://localhost/api routes to the api backend" ;; *) bad "GET /api returned: $(echo "$BODY_API" | head -1)" ;; esac

BODY_TLS="$(curl -sk --max-time 10 -H "$H" https://localhost/ 2>/dev/null)"
case "$BODY_TLS" in *"web from"*) ok "https://localhost/ works (TLS terminated at the ingress)" ;; *) bad "HTTPS returned: $(echo "$BODY_TLS" | head -1)" ;; esac
finish
