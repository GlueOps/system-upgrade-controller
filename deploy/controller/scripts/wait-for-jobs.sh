#!/bin/sh
set -u
DIR=$(dirname "$0")
NODE="$SYSTEM_UPGRADE_NODE_NAME"
# Per-client settings come from the Plan's prepare.envs.
WAIT_TIMEOUT_HOURS="${WAIT_TIMEOUT_HOURS:-40}"   # give up (node stays cordoned) after this
POLL_SECONDS="${POLL_SECONDS:-300}"
BLOCKING_LABEL="${BLOCKING_LABEL:-gluekube.io/drain-blocking}"   # non-Job pods with <label>=true block too
SUC_NAMESPACE="${SUC_NAMESPACE:-system-upgrade}"  # SUC's own pods never block

# Stop new pods landing here while we wait. A no-op on the run after the reboot.
kubectl cordon "$NODE" || exit 1

# kubectl jsonpath needs the dots in a label key escaped: gluekube\.io/drain-blocking
LABEL_PATH=$(printf '%s' "$BLOCKING_LABEL" | sed 's/\./\\./g')

deadline=$(( $(date +%s) + WAIT_TIMEOUT_HOURS * 3600 ))
while :; do
  # namespace|owner kinds|blocking label, one line per pod still running or pending here.
  # The kubectl call must succeed: an API error must not look like "no blocking pods".
  if ! list=$(kubectl get pods -A \
      --field-selector "spec.nodeName=$NODE,status.phase!=Succeeded,status.phase!=Failed" \
      -o jsonpath="{range .items[*]}{.metadata.namespace}|{.metadata.ownerReferences[*].kind}|{.metadata.labels.${LABEL_PATH}}{\"\n\"}{end}"); then
    echo "could not list pods on $NODE, retrying in 60s"
    sleep 60
    continue
  fi
  n=$(printf '%s\n' "$list" | awk -F'|' -v ns="$SUC_NAMESPACE" '
    $1 != ns && ($2 ~ /(^| )Job( |$)/ || $3 == "true") { c++ }
    END { print c + 0 }')

  [ "$n" -eq 0 ] && break
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "$n blocking pods still on $NODE after ${WAIT_TIMEOUT_HOURS}h; leaving it cordoned"
    exit 1
  fi
  echo "$n blocking pods on $NODE, next check in ${POLL_SECONDS}s"
  sleep "$POLL_SECONDS"
done

echo "no blocking pods left on $NODE"
exec sh "$DIR/check-etcd.sh"

