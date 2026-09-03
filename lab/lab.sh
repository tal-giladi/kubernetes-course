#!/usr/bin/env bash
# k8s-lab driver -- the interactive half of the course.
#
#   bash lab/lab.sh              where you are, what's next
#   bash lab/lab.sh up           create the kind cluster
#   bash lab/lab.sh check NN     grade exercise NN
#   bash lab/lab.sh hint NN      a nudge, not the answer
#   bash lab/lab.sh solve NN     print the solution manifests
#   bash lab/lab.sh reset NN     delete exercise NN's namespace, start it over
#   bash lab/lab.sh down         delete the cluster (keeps the course files)
#
# Every exercise lives in its own namespace, lesson-NN, so nothing you do in one
# can break another.
set -uo pipefail

LAB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$LAB/.." && pwd)"
PROGRESS="$LAB/.progress"
MANIFEST="$LAB/manifest.tsv"
CLUSTER=k8s-lab
CTX="kind-$CLUSTER"
touch "$PROGRESS"

# Never grade against whatever context happens to be current - a kubeconfig with a work
# cluster in it is exactly how accidents happen. Prefer the lab's own kubeconfig, and
# pin the context on every call regardless.
[ -f "$LAB/.kubeconfig" ] && export KUBECONFIG="$LAB/.kubeconfig"

k() { kubectl --context "$CTX" "$@"; }
pad() { printf "%02d" "$((10#$1))"; }

# field <NN> <col>   -> column from manifest.tsv (1=nn 2=module 3=lesson 4=title)
field() { awk -F'\t' -v n="$1" -v c="$2" '$1==n {print $c}' "$MANIFEST"; }
lesson_path() {
  local n="$1"
  echo "lessons/module-$(field "$n" 2)/lesson-$(field "$n" 3).md"
}

cluster_up() { k cluster-info >/dev/null 2>&1; }

cmd_up() {
  if ! cluster_up; then
    kind create cluster --config "$LAB/cluster/kind-config.yaml" --wait 180s || return 1
  else
    echo "cluster '$CLUSTER' is already up"
  fi
  kind export kubeconfig --name "$CLUSTER" --kubeconfig "$LAB/.kubeconfig" >/dev/null 2>&1
  echo
  echo "Now isolate your shell from any other cluster in your kubeconfig:"
  echo "    source lab/env.sh"
}

cmd_down() { kind delete cluster --name "$CLUSTER"; }

cmd_status() {
  echo
  echo "  Kubernetes, from Docker to mastery -- lab progress"
  echo
  if cluster_up; then
    printf "  cluster: UP   (%s nodes, context %s)\n" \
      "$(k get nodes --no-headers 2>/dev/null | grep -c .)" "$CTX"
  else
    echo "  cluster: DOWN -- run: bash lab/lab.sh up"
  fi
  echo

  local next="" done_count=0 total=0 lastmod=""
  while IFS=$'\t' read -r nn mod les title; do
    [ -z "${nn:-}" ] && continue
    total=$((total + 1))
    if [ "$mod" != "$lastmod" ]; then
      printf "\n  Module %s\n" "$mod"
      lastmod="$mod"
    fi
    local mark="[ ]"
    if grep -qx "$nn" "$PROGRESS"; then
      mark="[x]"; done_count=$((done_count + 1))
    elif [ -z "$next" ]; then next="$nn"; fi
    printf "    %s %s  %s\n" "$mark" "$nn" "$title"
  done < "$MANIFEST"

  echo
  printf "  %d of %d exercises complete\n\n" "$done_count" "$total"
  if [ -n "$next" ]; then
    echo "  next up: $(lesson_path "$next")"
    echo "  read it, do it, then:  bash lab/lab.sh check $next"
  else
    echo "  Every exercise is complete. That is the whole course."
    echo "  Tear the cluster down with: bash lab/lab.sh down"
  fi
  echo
}

cmd_check() {
  local n; n=$(pad "$1")
  local script="$LAB/checks/$n.sh"
  if [ ! -f "$script" ]; then echo "no checker for exercise $n"; exit 1; fi
  if ! cluster_up; then echo "cluster is down -- run: bash lab/lab.sh up"; exit 1; fi
  echo
  echo "  exercise $n -- $(field "$n" 4)"
  echo "  --------------------------------------------------------------"
  if bash "$script"; then
    grep -qx "$n" "$PROGRESS" || echo "$n" >> "$PROGRESS"
    echo "  --------------------------------------------------------------"
    echo "  PASS -- exercise $n complete."
    echo
    return 0
  else
    echo "  --------------------------------------------------------------"
    echo "  Not yet. Fix the FAIL lines above and run this again."
    echo "  Nudge: bash lab/lab.sh hint $n     Answer: bash lab/lab.sh solve $n"
    echo
    return 1
  fi
}

cmd_hint() {
  local n; n=$(pad "$1")
  local f="$ROOT/$(lesson_path "$n")"
  [ -f "$f" ] || { echo "lesson file not found: $f"; exit 1; }
  awk '/^## Hints/{p=1} p&&/^## Solution/{exit} p' "$f"
}

cmd_solve() {
  local n; n=$(pad "$1")
  if [ -d "$LAB/solutions/$n" ]; then
    for f in "$LAB/solutions/$n"/*; do
      echo "===== ${f#$ROOT/} ====="
      cat "$f"; echo
    done
  fi
  local f="$ROOT/$(lesson_path "$n")"
  [ -f "$f" ] && awk '/^## Solution/{p=1} p' "$f"
}

cmd_reset() {
  local n; n=$(pad "$1")
  k delete namespace "lesson-$n" --ignore-not-found
  grep -vx "$n" "$PROGRESS" > "$PROGRESS.tmp" 2>/dev/null || true
  mv "$PROGRESS.tmp" "$PROGRESS" 2>/dev/null || true
  echo "exercise $n reset"
}

case "${1:-status}" in
  ""|status) cmd_status ;;
  up)        cmd_up ;;
  down)      cmd_down ;;
  check)     cmd_check "${2:?usage: lab.sh check NN}" ;;
  hint)      cmd_hint  "${2:?usage: lab.sh hint NN}" ;;
  solve)     cmd_solve "${2:?usage: lab.sh solve NN}" ;;
  reset)     cmd_reset "${2:?usage: lab.sh reset NN}" ;;
  *) echo "usage: lab.sh [status|up|down|check NN|hint NN|solve NN|reset NN]" ;;
esac
