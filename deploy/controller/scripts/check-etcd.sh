#!/bin/sh
set -u
ETCDCTL="etcdctl --command-timeout=30s --dial-timeout=10s \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key"

healthy() {
  notready=$(kubectl get nodes -l node-role.kubernetes.io/control-plane \
    -o jsonpath='{range .items[*]}{.metadata.name}={.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' \
    | grep -v '=True$')
  if [ -n "$notready" ]; then
    echo "control-plane nodes not Ready: $notready"
    return 1
  fi
  # --cluster checks every member in the member list, asked through any running etcd pod.
  for pod in $(kubectl -n kube-system get pods -l component=etcd -o name); do
    if kubectl -n kube-system exec "$pod" -- $ETCDCTL endpoint health --cluster; then
      return 0
    fi
  done
  echo "etcd: not every member is healthy"
  return 1
}

for i in $(seq 1 120); do
  healthy && exit 0
  echo "waiting for etcd and the control plane ($i/120), next check in 60s"
  sleep 60
done
echo "etcd or the control plane still unhealthy after 2h; not touching this node"
exit 1

