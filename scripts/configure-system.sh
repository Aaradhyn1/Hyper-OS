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

  log INFO "Installing runtime and desktop packages"
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
  network-manager-gnome \
  systemd-resolved \
  policykit-1 \
  udisks2 \
  gvfs \
  gvfs-backends \
  grub-pc-bin \
  xserver-xorg-core \
  xserver-xorg-video-all \
  xinit \
  openbox \
  lightdm \
  lightdm-gtk-greeter \
  xterm \
  pcmanfm \
  pipewire \
  pipewire-pulse \
  wireplumber \
  libspa-0.2-modules \
  alsa-utils

install -d -m 0755 /lib/live

cat > /etc/hostname <<HOSTNAMEFILE
$HOSTNAME
HOSTNAMEFILE
cat > /etc/hosts <<'HOSTS'
127.0.0.1 localhost
127.0.1.1 hyperos
::1 localhost ip6-localhost ip6-loopback
HOSTS
sed -i "s/^127.0.1.1 .*/127.0.1.1 $HOSTNAME/" /etc/hosts

: > /etc/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

install -d -m 0755 /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/10-dns-systemd-resolved.conf <<'NMCONF'
[main]
dns=systemd-resolved
NMCONF
rm -f /etc/resolv.conf
ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

cat > /usr/local/sbin/hyperos-network-retry <<'NETRETRY'
#!/usr/bin/env bash
set -Eeuo pipefail
for _ in 1 2 3 4 5; do
  nmcli networking on || true
  while read -r dev type state _; do
    [[ "$state" == "connected" ]] && continue
    [[ "$type" == "ethernet" || "$type" == "wifi" ]] || continue
    nmcli device connect "$dev" || true
  done < <(nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status | tr ':' ' ')
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
usermod -aG sudo,audio,video,plugdev "$USERNAME"
printf '%s:%s\n' "$USERNAME" "$USER_PASSWORD" | chpasswd

if [[ "$ROOT_LOCK" == "1" ]]; then
  passwd -l root
elif [[ -n "$ROOT_PASSWORD" ]]; then
  printf 'root:%s\n' "$ROOT_PASSWORD" | chpasswd
fi

install -d -m 0755 /etc/xdg/openbox
cat > /etc/xdg/openbox/autostart <<'OPENBOXAUTOSTART'
nm-applet &
pcmanfm --desktop --profile LXDE &
xsetroot -solid "#1e1e1e" &
OPENBOXAUTOSTART

install -d -m 0755 /etc/skel
cat > /etc/skel/.xsession <<'XSESSION'
exec openbox-session
XSESSION
chmod 0644 /etc/skel/.xsession
cp -f /etc/skel/.xsession "/home/$USERNAME/.xsession"
chown "$USERNAME:$USERNAME" "/home/$USERNAME/.xsession"

install -d -m 0755 /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-hyperos.conf <<LIGHTDMCONF
[Seat:*]
user-session=openbox
greeter-session=lightdm-gtk-greeter
greeter-hide-users=false
greeter-show-manual-login=true
LIGHTDMCONF

if [[ "$LIVE_AUTOLOGIN" == "1" ]]; then
  cat >> /etc/lightdm/lightdm.conf.d/50-hyperos.conf <<AUTOLOGIN

autologin-user=$USERNAME
autologin-user-timeout=0
AUTOLOGIN
fi

install -d -m 0755 /etc/systemd/system/lightdm.service.d
cat > /etc/systemd/system/lightdm.service.d/restart.conf <<'LIGHTDMRESTART'
[Service]
Restart=on-failure
RestartSec=2
LIGHTDMRESTART

cat > /usr/local/sbin/hyperos-lightdm-fallback <<'LDMFALLBACK'
#!/usr/bin/env bash
set -Eeuo pipefail
if ! systemctl -q is-active display-manager.service; then
  systemctl restart lightdm.service || true
fi
LDMFALLBACK
chmod 0755 /usr/local/sbin/hyperos-lightdm-fallback

cat > /etc/systemd/system/hyperos-lightdm-fallback.service <<'LDMFALLBACKSVC'
[Unit]
Description=Hyper OS LightDM fallback restart
After=graphical.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/hyperos-lightdm-fallback

[Install]
WantedBy=graphical.target
LDMFALLBACKSVC

rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf

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

install -d -m 0755 /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/10-hyperos.conf <<'JOURNALCONF'
[Journal]
Storage=auto
SystemMaxUse=50M
RuntimeMaxUse=50M
JOURNALCONF

cat > /usr/local/sbin/hyperos-log-persist <<'LOGPERSIST'
#!/usr/bin/env bash
set -Eeuo pipefail
for p in /run/live/persistence/* /media/*/*; do
  [[ -d "$p" && -w "$p" ]] || continue
  install -d -m 0755 "$p/hyperos-logs"
  cp -a /var/log/hyperos/. "$p/hyperos-logs/" 2>/dev/null || true
  journalctl -b --no-pager > "$p/hyperos-logs/journal-boot.log" 2>/dev/null || true
  exit 0
done
exit 0
LOGPERSIST
chmod 0755 /usr/local/sbin/hyperos-log-persist

cat > /etc/systemd/system/hyperos-log-persist.service <<'LOGPERSISTSVC'
[Unit]
Description=Persist Hyper OS logs when writable media exists
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/hyperos-log-persist

[Install]
WantedBy=multi-user.target
LOGPERSISTSVC

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

cat > /usr/local/sbin/hyperos-welcome <<'WELCOME'
#!/usr/bin/env bash
set -Eeuo pipefail
MARKER=/var/lib/hyperos/welcome.done
if [[ ! -f "$MARKER" ]]; then
  mkdir -p /var/lib/hyperos
  cat >/etc/motd <<'MOTD'
Welcome to Hyper OS live session.
Desktop: Openbox + PCManFM + XTerm
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
systemctl enable hyperos-log-persist.service
systemctl enable hyperos-welcome.service
systemctl enable hyperos-hostname.service
systemctl enable hyperos-lightdm-fallback.service
systemctl enable lightdm
systemctl set-default graphical.target

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
