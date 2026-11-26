#!/bin/sh
# Prints a timeline every 20s until every selected node carries the plan's "done" label (or 60 min).
# Usage: test/watch.sh [workers|masters] [namespace]
ROLE=${1:-workers}
NS=${2:-system-upgrade}
PLAN=ubuntu-upgrade-$ROLE
if [ "$ROLE" = masters ]; then SEL='node-role.kubernetes.io/control-plane'; else SEL='!node-role.kubernetes.io/control-plane'; fi
end=$(( $(date +%s) + 3600 ))
while [ "$(date +%s)" -lt "$end" ]; do
  echo "===== $(date -u +%T)"
  kubectl get nodes -l "$SEL" --no-headers \
    -o "custom-columns=NODE:.metadata.name,SCHED:.spec.unschedulable,DONE:.metadata.labels.plan\.upgrade\.cattle\.io/$PLAN,BOOT:.status.nodeInfo.bootID" \
    | awk '{printf "  %-28s cordoned=%-5s plan-hash=%-12.12s boot=%.8s\n", $1, ($2=="true"?"yes":"no"), $3, $4}'
  kubectl -n "$NS" get pods --no-headers -o "custom-columns=POD:.metadata.name,NODE:.spec.nodeName,STATUS:.status.phase,INIT:.status.initContainerStatuses[*].state" 2>/dev/null \
    | awk '{print "  suc:", $1, $2, $3}' | sed 's/map\[[^]]*\]//g'
  kubectl -n os-patch-test get pods --no-headers -o "custom-columns=POD:.metadata.name,NODE:.spec.nodeName,STATUS:.status.phase" 2>/dev/null \
    | awk '{print "  test:", $1, $2, $3}'
  hash=$(kubectl -n "$NS" get plan "$PLAN" -o jsonpath='{.status.latestHash}' 2>/dev/null)
  total=$(kubectl get nodes -l "$SEL" --no-headers | wc -l)
  done_n=$(kubectl get nodes -l "plan.upgrade.cattle.io/$PLAN=$hash" --no-headers 2>/dev/null | wc -l)
  echo "  plan: $done_n/$total $ROLE done"
  if [ -n "$hash" ] && [ "$done_n" -eq "$total" ]; then echo "ALL $ROLE DONE"; exit 0; fi
  sleep 20
done
echo "TIMEOUT"; exit 1
