#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/build-common.sh
source "$SCRIPT_DIR/lib/build-common.sh"

USERNAME="${USERNAME:-hyper}"
USER_PASSWORD="${HYPER_PASSWORD:-hyper}"
ROOT_PASSWORD="${ROOT_PASSWORD:-}"
ROOT_LOCK="${ROOT_LOCK:-1}"
HOSTNAME="${HOSTNAME:-hyperos}"
LIVE_AUTOLOGIN="${LIVE_AUTOLOGIN:-0}"
DEBUG_MODE=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--debug]
USAGE
}

cleanup_and_report() {
  local code="$1"
  cleanup_mounts
  if [[ "$code" -ne 0 ]]; then
    log ERROR "System configuration failed with exit code $code"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --debug)
        DEBUG_MODE=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  [[ "$DEBUG_MODE" -eq 1 ]] && set -x

  use_shared_logging
  require_root
  require_cmds chroot mount umount apt-get
  [[ -d "$ROOTFS_DIR" ]] || die "Rootfs missing: $ROOTFS_DIR (run build-rootfs.sh first)"

  trap 'cleanup_and_report $?' EXIT

  log INFO "Mounting chroot filesystems"
  mount_chroot_fs

  log INFO "Installing kernel, live runtime, and networking packages"
  if ! chroot "$ROOTFS_DIR" /bin/bash -eux <<CHROOT
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  linux-image-amd64 \
  systemd-sysv \
  live-boot \
  live-config \
  live-tools \
  squashfs-tools \
  initramfs-tools \
  ca-certificates \
  sudo \
  network-manager \
  systemd-resolved \
  grub-pc-bin

# WHY: live-boot expects this path to exist for runtime hooks and writable state.
install -d -m 0755 /lib/live

# WHY: predictable hostname/hosts prevents resolver delays and login warnings.
cat > /etc/hostname <<HOSTNAMEFILE
$HOSTNAME
HOSTNAMEFILE
cat > /etc/hosts <<'HOSTS'
127.0.0.1 localhost
127.0.1.1 hyperos
::1 localhost ip6-localhost ip6-loopback
HOSTS
sed -i "s/^127.0.1.1 .*/127.0.1.1 $HOSTNAME/" /etc/hosts

# WHY: machine-id must exist but be empty in images so each booted system gets unique identity.
: > /etc/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

# WHY: force DNS through systemd-resolved to avoid stale resolver state in live media.
install -d -m 0755 /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/10-dns-systemd-resolved.conf <<'NMCONF'
[main]
dns=systemd-resolved
NMCONF
rm -f /etc/resolv.conf
ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# WHY: retry networking early in boot if DHCP or carrier race occurs.
cat > /usr/local/sbin/hyperos-network-retry <<'NETRETRY'
#!/usr/bin/env bash
set -Eeuo pipefail
for _ in 1 2 3 4 5; do
  nmcli networking on || true
  nmcli connection reload || true
  nmcli connection up id "Wired connection 1" || true
  getent hosts deb.debian.org >/dev/null 2>&1 && exit 0
  sleep 3
done
exit 0
NETRETRY
chmod 0755 /usr/local/sbin/hyperos-network-retry

cat > /etc/systemd/system/hyperos-network-retry.service <<'NETSRV'
[Unit]
Description=Hyper OS network retry and DNS validation
After=NetworkManager.service
Wants=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/hyperos-network-retry

[Install]
WantedBy=multi-user.target
NETSRV

install -d -m 0755 /etc/systemd/system/NetworkManager.service.d
cat > /etc/systemd/system/NetworkManager.service.d/restart.conf <<'NMDROPIN'
[Service]
Restart=on-failure
RestartSec=2
NMDROPIN

if ! id -u "$USERNAME" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$USERNAME"
fi
usermod -aG sudo "$USERNAME"
printf '%s:%s\n' "$USERNAME" "$USER_PASSWORD" | chpasswd

# WHY: lock direct root login on live media unless explicitly requested.
if [[ "$ROOT_LOCK" == "1" ]]; then
  passwd -l root
elif [[ -n "$ROOT_PASSWORD" ]]; then
  printf 'root:%s\n' "$ROOT_PASSWORD" | chpasswd
fi

# WHY: boot diagnostics aid field debugging from TTY without extra packages.
cat > /usr/local/sbin/hyperos-debug <<'DEBUGSCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
mkdir -p /var/log/hyperos
{
  echo "==== date ===="
  date -Is
  echo "==== system state ===="
  systemctl is-system-running || true
  echo "==== dmesg ===="
  dmesg || true
  echo "==== journal ===="
  journalctl -b --no-pager || true
} | tee -a /var/log/hyperos/boot.log
DEBUGSCRIPT
chmod 0755 /usr/local/sbin/hyperos-debug

install -d -m 0755 /var/log/hyperos

cat > /etc/systemd/system/hyperos-bootlog.service <<'BOOTLOG'
[Unit]
Description=Persist Hyper OS boot diagnostics
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/hyperos-debug

[Install]
WantedBy=multi-user.target
BOOTLOG

cat > /etc/systemd/system/hyperos-boot-failure.service <<'BOOTFAIL'
[Unit]
Description=Dump diagnostics on degraded boot
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'state="$(systemctl is-system-running || true)"; if [[ "$state" != "running" ]]; then /usr/local/sbin/hyperos-debug; fi'

[Install]
WantedBy=multi-user.target
BOOTFAIL

# WHY: friendly first-boot UX without persistent overhead.
cat > /usr/local/sbin/hyperos-welcome <<'WELCOME'
#!/usr/bin/env bash
set -Eeuo pipefail
MARKER=/var/lib/hyperos/welcome.done
if [[ ! -f "$MARKER" ]]; then
  mkdir -p /var/lib/hyperos
  cat >/etc/motd <<'MOTD'
Welcome to Hyper OS live session.
Use: sudo /usr/local/sbin/hyperos-debug
MOTD
  touch "$MARKER"
fi
WELCOME
chmod 0755 /usr/local/sbin/hyperos-welcome

cat > /etc/systemd/system/hyperos-welcome.service <<'WELCOMESVC'
[Unit]
Description=Hyper OS first boot welcome
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/hyperos-welcome

[Install]
WantedBy=multi-user.target
WELCOMESVC

# WHY: optional autologin for kiosk/demo use-cases.
if [[ "$LIVE_AUTOLOGIN" == "1" ]]; then
  install -d -m 0755 /etc/systemd/system/getty@tty1.service.d
  cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<AUTOLOGIN
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USERNAME --noclear %I \$TERM
AUTOLOGIN
else
  rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf
fi

# WHY: dynamic hostname allows per-boot override via kernel cmdline hostname=.
cat > /usr/local/sbin/hyperos-hostname <<'HOSTNAMESCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
name="$(sed -n 's/.*\<hostname=\([^ ]*\).*/\1/p' /proc/cmdline | tail -n1)"
if [[ -n "$name" ]]; then
  hostnamectl set-hostname "$name" || true
fi
HOSTNAMESCRIPT
chmod 0755 /usr/local/sbin/hyperos-hostname

cat > /etc/systemd/system/hyperos-hostname.service <<'HOSTNAMESVC'
[Unit]
Description=Hyper OS dynamic hostname from kernel cmdline
After=systemd-remount-fs.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/hyperos-hostname

[Install]
WantedBy=multi-user.target
HOSTNAMESVC

systemctl enable NetworkManager
systemctl enable systemd-resolved
systemctl enable hyperos-network-retry.service
systemctl enable hyperos-bootlog.service
systemctl enable hyperos-boot-failure.service
systemctl enable hyperos-welcome.service
systemctl enable hyperos-hostname.service
systemctl set-default multi-user.target

# WHY: live-boot hooks and fsck behavior must be embedded into initramfs for robust live booting.
install -d -m 0755 /etc/initramfs-tools/conf.d
cat > /etc/initramfs-tools/conf.d/hyperos-live.conf <<'INITRAMFSCONF'
COMPRESS=zstd
MODULES=most
INITRAMFSCONF

update-initramfs -u -k all

latest_initrd="$(ls -1 /boot/initrd.img-* | sort -V | tail -n1)"
if [[ -z "$latest_initrd" ]]; then
  echo "ERROR: No initrd found after update-initramfs" >&2
  exit 11
fi
if ! lsinitramfs "$latest_initrd" | grep -Eq '^scripts/live|^usr/lib/live'; then
  echo "ERROR: live-boot hooks missing from $latest_initrd" >&2
  exit 12
fi

apt-get clean
rm -rf /var/lib/apt/lists/*
CHROOT
  then
    die "Chroot package/configuration stage failed"
  fi

  trap - EXIT
  cleanup_and_report 0
  log INFO "System configuration complete"
}

main "$@"
