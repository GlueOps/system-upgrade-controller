# system-upgrade-controller

Ubuntu OS patching for GlueKube clusters, run inside the cluster by
[rancher/system-upgrade-controller](https://github.com/rancher/system-upgrade-controller) (SUC).

Masters go one at a time, and only while etcd and every control plane are healthy. Each worker is
cordoned first, then waits for its Job pods to finish (up to 40h by default) before it is drained.
Then apt runs on the host, and the node reboots only if Ubuntu asks for it.

## Layout

| Path | What | Applied by |
|---|---|---|
| `deploy/controller/` | SUC from its GitHub release (plus GlueKube patches), the `os-patch-scripts` Secret built from `scripts/`, and the RBAC the scripts need. The same for every client. | Argo CD (`kustomize`) |
| `plans/example-client.yaml` | The two Plans (masters and workers) with the client's settings: patch mode, holds, window, wait timeout. | `kubectl apply`, per client |
| `deploy/argocd/example-client.yaml` | Example Argo CD Application for the controller. | Argo CD |
| `test/` | `long-jobs.sh` starts a 5-minute Job on each worker; `watch.sh` follows a round. | by hand |

## Install

```sh
kubectl apply -k deploy/controller           # or via Argo CD, pinned to a tag
cp plans/example-client.yaml <client>-plans.yaml   # edit the "# client:" fields
kubectl apply -f <client>-plans.yaml
```

## Day to day

- **Start a round:** bump `spec.version` in both Plans. Any other change to a Plan's spec, or to
  `scripts/`, also starts a round. Jobs only start inside the Plan's `window`.
- **Pause a node:** `kubectl label node <node> gluekube.io/os-patch=disabled`. Remove the label to resume.
- **Make a worker wait for a non-Job pod too:** label the pod `gluekube.io/drain-blocking=true`.
- **Watch:** `test/watch.sh workers` (or `masters`).
- **Don't** delete a Plan, or the scripts Secret, while a Job runs: that kills it, possibly mid-apt.

## Rolling out changes

- **Scripts:** a change re-hashes the Plans on every cluster that syncs it, so every node patches
  again at its next window. Pin each client's Argo CD `targetRevision` to a tag and move them one
  by one.
- **Upgrade SUC:** change the version in both release URLs in `deploy/controller/kustomization.yaml`.
- **Controller settings** (`default-controller-env`): the controller reads them only at start. Bump
  `gluekube.io/env-rev` in the same patch so it restarts.
- **Keep `SYSTEM_UPGRADE_JOB_ACTIVE_DEADLINE_SECONDS_MAX` at `0`:** the workers Plan needs 42h.
  Also keep `jobActiveDeadlineSecs` above `WAIT_TIMEOUT_HOURS`.
