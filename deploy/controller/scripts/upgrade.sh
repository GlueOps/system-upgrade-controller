#!/bin/sh
set -eu
# Per-client settings come from the Plan's upgrade.envs (chroot keeps the environment).
PATCH_MODE="${PATCH_MODE:-security}"   # security: -security pocket only.  full: apt-get dist-upgrade
HOLD_PACKAGES="${HOLD_PACKAGES:-}"     # extra packages to freeze, space-separated
STATE=/var/lib/system-upgrade
MARK="$STATE/done-${SYSTEM_UPGRADE_PLAN_NAME}-${SYSTEM_UPGRADE_PLAN_LATEST_HASH}"
BASE_HOLDS="kubeadm kubelet kubectl containerd.io docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin"
mkdir -p "$STATE"

# Run after the reboot: report success so SUC labels and uncordons the node and moves on.
if [ -f "$MARK" ]; then
  echo "already patched for this plan hash ($MARK), node is back: done"
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
# needrestart: only list services using outdated libraries, never restart them (containerd and
# kubelet included). A reboot, when one is required, picks up the new libraries instead.
export NEEDRESTART_MODE=l
APT="-o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef"

# Finish anything an interrupted earlier run left half-configured.
dpkg --configure -a

# Client holds: release packages dropped from the list (never GlueKube's own), hold the rest.
touch "$STATE/client-holds"
for p in $(cat "$STATE/client-holds"); do
  case " $HOLD_PACKAGES $BASE_HOLDS " in
    *" $p "*) ;;
    *) apt-mark unhold "$p" || true ;;
  esac
done
for p in $HOLD_PACKAGES; do
  apt-mark hold "$p" || echo "warning: could not hold $p"
done
echo "$HOLD_PACKAGES" > "$STATE/client-holds"

apt-get $APT update

case "$PATCH_MODE" in
  security)
    # Upgradable packages offered by the -security pocket, minus held ones (asking apt-get
    # install for a held package fails the whole run).
    apt-mark showhold > "$STATE/held"
    pkgs=$(apt list --upgradable 2>/dev/null | awk -F/ '/-security/ {print $1}' \
           | grep -vxF -f "$STATE/held" || true)
    if [ -n "$pkgs" ]; then
      echo "security updates: $pkgs"
      apt-get -y $APT install --only-upgrade $pkgs
    else
      echo "no security updates"
    fi
    ;;
  full)
    apt-get -y $APT dist-upgrade
    ;;
  *)
    echo "unknown PATCH_MODE '$PATCH_MODE' (security|full)"
    exit 1
    ;;
esac
apt-get -y $APT autoremove

touch "$MARK"
sync
if [ -f /var/run/reboot-required ]; then
  echo "reboot required:"; cat /var/run/reboot-required.pkgs 2>/dev/null || true
  reboot
  # Don't exit: a finished Job would let SUC start the next node while this one goes down.
  sleep infinity
fi
echo "no reboot required"
exit 0

