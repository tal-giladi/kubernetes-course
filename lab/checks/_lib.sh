# shared helpers for lesson checkers
CTX=kind-k8s-lab
FAILED=0
k() { kubectl --context "$CTX" "$@"; }
ok()   { printf "  PASS  %s\n" "$1"; }
bad()  { printf "  FAIL  %s\n" "$1"; FAILED=1; }
# assert <description> <expected> <actual>
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
# truthy <description> <command...>
yes_() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
finish() { exit $FAILED; }
