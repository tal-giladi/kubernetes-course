#!/usr/bin/env bash
# Remove this course from the machine.
#
#   bash lab/cleanup.sh          delete the cluster and every image it pulled
#   bash lab/cleanup.sh --all    the above, plus the kind and helm binaries and the PATH entry
#
# Nothing here touches Docker itself, your other containers, your other images, or your
# real kubeconfig. Deleting the kind cluster removes all 25 lesson namespaces with it -
# there is no need to clean those up first.
set -uo pipefail
CLUSTER=k8s-lab
BIN_DIR="C:/Users/TalGiladi/bin"
LAB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> deleting the kind cluster (its 3 node containers, and everything running in them)"
kind delete cluster --name "$CLUSTER" || true

echo "==> removing the lab kubeconfig and progress file"
rm -f "$LAB/.kubeconfig" "$LAB/.progress"

echo "==> removing the context from your real kubeconfig, if kind left one behind"
kubectl config delete-context "kind-$CLUSTER" 2>/dev/null || true
kubectl config delete-cluster "kind-$CLUSTER" 2>/dev/null || true
kubectl config delete-user    "kind-$CLUSTER" 2>/dev/null || true

echo "==> removing the images this course pulled or built"
for img in $(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -E \
  '^(kindest/node|hello|nginx:1\.2[79]-alpine|busybox:1\.37|registry\.k8s\.io/ingress-nginx|registry\.k8s\.io/metrics-server|mcr\.microsoft\.com/dotnet)'); do
  echo "    $img"
  docker rmi -f "$img" >/dev/null 2>&1 || true
done
docker image prune -f >/dev/null 2>&1 || true
docker builder prune -f >/dev/null 2>&1 || true

if [ "${1:-}" = "--all" ]; then
  echo "==> removing the kind and helm binaries"
  rm -f "$BIN_DIR/kind.exe" "$BIN_DIR/helm.exe"
  rmdir "$BIN_DIR" 2>/dev/null || true

  echo "==> removing $BIN_DIR from the user PATH"
  powershell -NoProfile -Command '
    $p = [Environment]::GetEnvironmentVariable("Path","User")
    $new = ($p -split ";" | Where-Object { $_ -and $_ -ne "C:\Users\TalGiladi\bin" }) -join ";"
    [Environment]::SetEnvironmentVariable("Path", $new, "User")
    "    PATH cleaned"
  '
  echo
  echo "Helm also keeps a small cache; remove it if you want nothing left:"
  echo "  rm -rf \"\$LOCALAPPDATA/helm\" \"\$APPDATA/helm\""
  echo
  echo "And the course itself, if you are done with it:"
  echo "  rm -rf \"C:/Users/TalGiladi/OneDrive/repos/course-creator/kubernetes\""
fi

echo
echo "What is left of the lab:"
docker ps -a --filter "name=$CLUSTER" --format '  container: {{.Names}}'
docker images 'kindest/node' --format '  image: {{.Repository}}:{{.Tag}}'
docker images 'hello'        --format '  image: {{.Repository}}:{{.Tag}}'
echo "  (nothing listed above means nothing is left)"
