# Hyper OS Gaming + Windows Compatibility

## Architecture
- Compatibility stack:
  - Wine + Winetricks for direct Windows app execution
  - Steam + Proton for game compatibility
  - Lutris for runner/library management
  - DXVK + VKD3D for DirectX translation via Vulkan
- Monitoring/tuning:
  - GameMode (`gamemoderun`) for temporary performance boosts
  - MangoHud for telemetry overlay

## Packages
Core:
- `hyperos-gaming`
- `steam`, `lutris`, `wine`, `winetricks`, `dxvk`, `vkd3d`
- `gamemode`, `mangohud`, `vulkan-tools`
- `lib32-vulkan-icd-loader`, `lib32-mesa`, `lib32-gamemode`, `lib32-mangohud`

Vendor-specific Vulkan drivers:
- Intel: `vulkan-intel`
- AMD: `vulkan-radeon`
- NVIDIA: `nvidia nvidia-utils lib32-nvidia-utils`

## Config
- `/etc/environment.d/90-hyperos-gaming.conf`
  - enables `WINEESYNC=1`, `WINEFSYNC=1`
- `/etc/security/limits.d/90-hyperos-gaming.conf`
  - raises file descriptor limits for Wine/Proton prefixes
- optional GameMode config in `configs/gaming/gamemode.ini`

## Validation
Use `scripts/gaming-validate.sh` and manual smoke checks:
- `vulkaninfo --summary`
- `glxinfo -B`
- `WINEDEBUG=-all wine --version`
- `gamemoderun mangohud glxgears`

Sample Windows app run:
1. `WINEPREFIX=$HOME/.wine-test winecfg`
2. `WINEPREFIX=$HOME/.wine-test wine notepad`

Steam Proton:
1. Steam → Settings → Compatibility
2. Enable Steam Play for supported and all titles
3. Select latest stable Proton

## Limitations
- Anti-cheat protected titles may still fail (EAC/Battleye policies vary).
- Some launchers/drivers require manual per-game tweaks.
- NVIDIA laptops with hybrid graphics may need PRIME setup beyond defaults.
