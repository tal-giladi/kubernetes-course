# Source this at the start of every lab session:
#
#     source lab/env.sh
#
# It points KUBECONFIG at a file that contains ONLY this course's kind cluster, so a
# stray `kubectl delete` cannot possibly land on a work cluster. Your normal kubeconfig
# is untouched, and a new shell goes back to it.
#
# If you would rather use your ordinary kubeconfig, that works too - just run
# `kubectl config use-context kind-k8s-lab` and check `kubectl config current-context`
# before anything destructive. The isolated file is the version that cannot bite you.

_LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$_LAB_DIR/.kubeconfig" ]; then
  kind export kubeconfig --name k8s-lab --kubeconfig "$_LAB_DIR/.kubeconfig" || {
    echo "could not export the kind kubeconfig - is the cluster up? (bash lab/lab.sh up)"
    return 1 2>/dev/null || exit 1
  }
fi

export KUBECONFIG="$_LAB_DIR/.kubeconfig"
echo "KUBECONFIG -> $KUBECONFIG"
kubectl config current-context
