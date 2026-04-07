# Hyper OS v0.1

Hyper OS v0.1 is a minimal, performance-focused Debian-based operating system build that produces a bootable x86_64 ISO for virtual machines.

## Design constraints implemented

- Base distro: Debian via `debootstrap`
- Architecture: x86_64 (`amd64`)
- Bootloader: GRUB (BIOS-compatible ISO via `grub-mkrescue`)
- Init system: `systemd` (`systemd-sysv`)
- Userland goal: minimal and debuggable console system

## Project structure

```text
hyper-os/
├── build/
├── rootfs/
├── iso/
├── configs/
├── scripts/
└── README.md
```

## Prerequisites (host)

Use a Debian/Ubuntu-like host (or equivalent packages on your distro):

```bash
sudo apt-get update
sudo apt-get install -y debootstrap grub-pc-bin grub-common xorriso qemu-system-x86
```

## One-command build

```bash
make build
```

This runs:

```bash
./scripts/build-hyperos-iso.sh
```

Output:

- `hyperos.iso`

---

## Full step-by-step reproducible process (exact commands)

### 1) Root filesystem creation (debootstrap)

```bash
sudo debootstrap --arch=amd64 --variant=minbase bookworm ./rootfs http://deb.debian.org/debian
```

Install required packages inside chroot:

```bash
sudo mount --bind /dev ./rootfs/dev
sudo mount --bind /dev/pts ./rootfs/dev/pts
sudo mount -t proc proc ./rootfs/proc
sudo mount -t sysfs sysfs ./rootfs/sys

sudo chroot ./rootfs /bin/bash
apt-get update
apt-get install -y --no-install-recommends linux-image-amd64 systemd-sysv sudo nano network-manager grub-pc-bin
apt-get clean
exit
```

### 2) Base system configuration

Set hostname:

```bash
echo hyperos | sudo tee ./rootfs/etc/hostname
```

Create `/etc/fstab`:

```bash
cat <<'EOF_FSTAB' | sudo tee ./rootfs/etc/fstab
proc  /proc  proc   defaults  0  0
sysfs /sys   sysfs  defaults  0  0
devpts /dev/pts devpts gid=5,mode=620 0 0
EOF_FSTAB
```

Create user and passwords:

```bash
sudo chroot ./rootfs /bin/bash -c "useradd -m -s /bin/bash hyper"
sudo chroot ./rootfs /bin/bash -c "printf 'hyper:hyper\\n' | chpasswd"
sudo chroot ./rootfs /bin/bash -c "printf 'root:root\\n' | chpasswd"
```

Grant sudo to user `hyper`:

```bash
sudo install -d -m 0755 ./rootfs/etc/sudoers.d
cat <<'EOF_SUDO' | sudo tee ./rootfs/etc/sudoers.d/hyper
hyper ALL=(ALL:ALL) ALL
EOF_SUDO
sudo chmod 0440 ./rootfs/etc/sudoers.d/hyper
```

Enable NetworkManager and console target:

```bash
sudo chroot ./rootfs /bin/bash -c "systemctl enable NetworkManager"
sudo chroot ./rootfs /bin/bash -c "systemctl set-default multi-user.target"
```

### 3) Bootloader setup (GRUB BIOS)

Create `configs/grub.cfg` with exact content:

```cfg
set default=0
set timeout=3

menuentry "Hyper OS v0.1 (Debian minimal)" {
    linux /boot/vmlinuz root=/dev/sr0 ro console=tty0 console=ttyS0,115200n8 systemd.unit=multi-user.target
    initrd /boot/initrd.img
}
```

### 4) ISO creation

Copy kernel/initrd from rootfs and build ISO:

```bash
mkdir -p ./iso/boot/grub
sudo cp ./rootfs/boot/vmlinuz-* ./iso/boot/vmlinuz
sudo cp ./rootfs/boot/initrd.img-* ./iso/boot/initrd.img
cp ./configs/grub.cfg ./iso/boot/grub/grub.cfg
grub-mkrescue -o ./hyperos.iso ./iso
```

### 5) VM test (QEMU + serial debugging)

```bash
qemu-system-x86_64 \
  -m 2048 \
  -cdrom ./hyperos.iso \
  -boot d \
  -serial mon:stdio \
  -no-reboot
```

Login credentials for first boot (from this build script):

- user: `hyper` / pass: `hyper`
- root: `root` / pass: `root`

> Change passwords immediately in real usage.

### 6) Debug strategy when boot fails

Identify failure stage quickly:

1. **GRUB stage fails** (no menu / rescue prompt)
   - Verify ISO contains `/boot/grub/grub.cfg`:
     ```bash
     xorriso -indev ./hyperos.iso -find / -type f
     ```
   - Rebuild ISO and ensure `grub-mkrescue` completed without errors.

2. **Kernel stage fails** (panic before init)
   - Ensure kernel/initrd exist and match expected names in ISO (`/boot/vmlinuz`, `/boot/initrd.img`).
   - Add temporary kernel flags in `grub.cfg` for diagnostics:
     - `loglevel=7`
     - `systemd.log_level=debug`

3. **Init/systemd stage fails**
   - Boot with:
     - `systemd.unit=emergency.target`
   - Check logs:
     ```bash
     journalctl -xb
     systemctl --failed
     ```

4. **Root mount failure / kernel panic `unable to mount root fs`**
   - Verify root parameter in grub uses ISO root for this flow:
     - `root=/dev/sr0 ro`
   - Confirm initramfs includes necessary modules:
     ```bash
     lsinitramfs ./rootfs/boot/initrd.img-* | head
     ```

After manual flow, unmount chroot binds:

```bash
sudo umount -lf ./rootfs/dev/pts
sudo umount -lf ./rootfs/dev
sudo umount -lf ./rootfs/proc
sudo umount -lf ./rootfs/sys
```
