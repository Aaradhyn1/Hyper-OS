# Hyper OS Gaming Orchestration Platform

## Architecture
- `hyperos-gamed` daemon monitors running game processes and applies per-profile settings.
- `hyperos-game-wrapper` is an explicit launch wrapper for Steam/Lutris custom launch options.
- Profiles live in `/etc/hyperos/game-profiles/*.profile` and are plain shell key/value files.
- `hyperos-gaming-ui` provides a zenity GTK control panel for toggles and profile selection.

## Profile format
Required keys:
- `PROFILE_NAME`
- `CPU_GOVERNOR` (`schedutil`/`performance`)
- `USE_GAMEMODE` (`0`/`1`)
- `NICE_LEVEL` (`-20..19`)
- `GPU_OFFLOAD` (`auto`/`nvidia`)
- `PROCESS_MATCH` (regex for `pgrep -f`)

Optional environment keys:
- Any `ENV_*` variables are exported by wrapper/daemon context.

## Integration
- systemd service: `hyperos-gamed.service`
- logs: `/var/log/hyperos-gamed.log`
- state: `/run/hyperos-gamed/`

## Steam/Lutris launch commands
- Steam launch option example:
  - `/usr/local/bin/hyperos-game-wrapper %command%`
- Lutris command prefix example:
  - `/usr/local/bin/hyperos-game-wrapper`

## Kernel/scheduler tuning
- Safe gaming sysctl: `/etc/sysctl.d/99-hyperos-gaming-latency.conf`
- Apply/restore helper:
  - `scripts/gaming/apply-kernel-tuning.sh apply`
  - `scripts/gaming/apply-kernel-tuning.sh restore`

## Validation quick checks
- `systemctl status hyperos-gamed.service`
- `tail -f /var/log/hyperos-gamed.log`
- `pgrep -af 'steam_app_|wine|lutris'`
- `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor`

## Constraints / limitations
- Process-name matching can miss custom launchers.
- Anti-cheat/DRM restrictions are title-specific and not automatically bypassable.
- Wayland-specific tuning is out of scope (Xorg/Openbox baseline).
