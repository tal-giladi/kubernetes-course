source "$(dirname "$0")/_lib.sh"
NS=lesson-12

if ! k -n $NS get pvc data >/dev/null 2>&1; then bad "pvc 'data' missing in $NS"; finish; fi
ok "pvc 'data' exists"
P() { k -n $NS get pvc data -o jsonpath="$1" 2>/dev/null; }
eq "pvc is Bound"          "Bound"         "$(P '{.status.phase}')"
eq "access mode is RWO"    "ReadWriteOnce" "$(P '{.spec.accessModes[0]}')"
eq "capacity is 1Gi"       "1Gi"           "$(P '{.status.capacity.storage}')"
if [ -n "$(P '{.spec.volumeName}')" ]; then ok "it is bound to PV $(P '{.spec.volumeName}')"; else bad "no PV bound"; fi

if ! k -n $NS get deploy writer >/dev/null 2>&1; then bad "deployment 'writer' missing"; finish; fi
ok "deployment 'writer' exists"
eq "writer has 1 Ready replica" "1" "$(k -n $NS get deploy writer -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
eq "writer mounts the claim" "data" \
   "$(k -n $NS get deploy writer -o jsonpath='{.spec.template.spec.volumes[0].persistentVolumeClaim.claimName}' 2>/dev/null)"

# Prove persistence rather than trust it: write, destroy the Pod, and check the earlier
# line is still there afterwards. This check deletes the writer Pod on purpose.
BEFORE="$(k -n $NS exec deploy/writer -- wget -qO- --timeout=5 http://127.0.0.1:8080/data 2>/dev/null)"
FIRST="$(echo "$BEFORE" | head -1)"
N_BEFORE="$(echo "$BEFORE" | grep -c .)"
if [ -z "$FIRST" ]; then bad "the app could not write to /data - check the mount and the DATA_DIR env var"; finish; fi
ok "wrote to /data ($N_BEFORE line(s) so far)"

OLD_POD="$(k -n $NS get pod -l app=writer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
k -n $NS delete pod "$OLD_POD" --wait=true >/dev/null 2>&1
k -n $NS wait --for=condition=Available deploy/writer --timeout=180s >/dev/null 2>&1
NEW_POD="$(k -n $NS get pod -l app=writer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
if [ -n "$NEW_POD" ] && [ "$NEW_POD" != "$OLD_POD" ]; then
  ok "deleted $OLD_POD; the ReplicaSet made $NEW_POD"
else
  bad "the writer Pod did not come back - cannot test persistence"; finish
fi

AFTER="$(k -n $NS exec deploy/writer -- wget -qO- --timeout=5 http://127.0.0.1:8080/data 2>/dev/null)"
N_AFTER="$(echo "$AFTER" | grep -c .)"
if echo "$AFTER" | grep -qF "$FIRST"; then
  ok "the line written by the old Pod is still there - the volume outlived it"
else
  bad "the data written before the delete is gone - that is an emptyDir, not a PVC"
fi
if [ "${N_AFTER:-0}" -gt "${N_BEFORE:-0}" ]; then
  ok "the new Pod appended to the same file ($N_BEFORE -> $N_AFTER lines)"
else
  bad "the new Pod did not append to the existing file"
fi

if ! k -n $NS get deploy scratch >/dev/null 2>&1; then bad "deployment 'scratch' missing"; finish; fi
ok "deployment 'scratch' exists"
if [ -n "$(k -n $NS get deploy scratch -o jsonpath='{.spec.template.spec.volumes[?(@.emptyDir)].name}' 2>/dev/null)" ]; then
  ok "scratch uses an emptyDir for the same mount path"
else
  bad "scratch should back /data with an emptyDir, for the contrast"
fi
finish
