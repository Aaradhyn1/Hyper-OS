# Hyper OS Automatic GPU Driver Provisioning

## Detection logic
`/usr/local/sbin/hyperos-driver-setup.sh` inspects:
- `lspci -nnk` (GPU vendor and class)
- `lsmod` (currently loaded GPU modules)
- `/sys/class/drm/card*` (DRM device presence)

It detects Intel, AMD, NVIDIA, and hybrid systems (e.g., Intel+NVIDIA).

## Mapping table
- Intel:
  - `mesa`, `vulkan-intel`, `lib32-vulkan-intel`
- AMD:
  - `mesa`, `vulkan-radeon`, `lib32-vulkan-radeon`
- NVIDIA:
  - `nvidia`, `nvidia-utils`, `nvidia-settings`, `lib32-nvidia-utils`
  - blacklist nouveau + rebuild initramfs
- Generic fallback:
  - `mesa`, Vulkan loader/tools only

Common runtime installed for compatibility:
- `wine`, `winetricks`, `dxvk`, `vkd3d`, `steam`, `lutris`
- `gamemode`, `mangohud`

## PRIME offload
If NVIDIA + Intel/AMD hybrid is detected, create `/etc/profile.d/hyperos-prime.sh`:
- `__NV_PRIME_RENDER_OFFLOAD=1`
- `__GLX_VENDOR_LIBRARY_NAME=nvidia`
- `__VK_LAYER_NV_optimus=NVIDIA_only`
- `prime-run` alias

## Service integration
One-shot systemd unit:
- `hyperos-driver-setup.service`
- Runs once on first boot via `ConditionPathExists=!/var/lib/hyperos/driver-setup.done`
- Logs to `/var/log/hyperos-driver-setup.log`

## Validation commands
- `lspci -nnk | grep -E "VGA|3D|Display" -A3`
- `lsmod | grep -E "nvidia|nouveau|amdgpu|i915"`
- `vulkaninfo --summary`
- `glxinfo -B`
- `WINEDEBUG=-all wine --version`

## Limitations
- Does not support legacy NVIDIA branch selection automatically.
- External GPU hotplug is not dynamically reprovisioned.
- Wayland-specific PRIME quirks are out of scope (current stack is Xorg/Openbox).
