#!/bin/sh
# Starts one 5-minute Job on every worker. Each logs every 10s and logs SIGTERM if it is killed,
# so the logs show whether the node waited for it ("finished OK") or drained it early ("got SIGTERM").
set -e
kubectl create namespace os-patch-test --dry-run=client -o yaml | kubectl apply -f -
for NODE in $(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o name | cut -d/ -f2); do
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: long-job-$NODE
  namespace: os-patch-test
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      nodeSelector:
        kubernetes.io/hostname: $NODE
      terminationGracePeriodSeconds: 30
      containers:
        - name: work
          image: busybox:1.36
          command: ["sh", "-c"]
          args:
            - |
              trap 'echo "\$(date -u +%T) got SIGTERM: killed before finishing"; exit 143' TERM
              echo "\$(date -u +%T) start on $NODE"
              for i in \$(seq 1 30); do sleep 10 & wait \$!; echo "\$(date -u +%T) working \$((i*10))s"; done
              echo "\$(date -u +%T) finished OK"
EOF
done
