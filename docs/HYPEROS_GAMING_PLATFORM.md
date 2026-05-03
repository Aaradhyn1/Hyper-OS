# HyperOS Unified Gaming Optimization Platform

## A. Architecture

HyperOS gaming stack is split into three lightweight components:

1. **hyperos-gamed** (`/usr/local/bin/hyperos-gamed` + `hyperos-gamed.service`)
   - Polls running processes and auto-applies a matching game profile.
   - Applies reversible system-level tweaks (CPU governor, I/O scheduler, optional IRQ rebalance).
   - Restores previous values when no matching game process is active.

2. **hyperos-game-launch** (`/usr/local/bin/hyperos-game-launch`)
   - Steam/Lutris wrapper for per-launch environment setup.
   - Applies profile-defined env vars, optional `gamemoderun`, process nice level, and NVIDIA offload flags.

3. **HyperOS Gaming UI** (`/usr/local/bin/hyperos-gaming-ui`)
   - Lightweight Tk GUI for toggling daemon/service and selecting default profile.
   - Displays simple CPU/RAM telemetry from `/proc`.

## B. Game Profile System

Profiles are stored in:

- `/etc/hyperos/game-profiles/*.conf`

Each profile is shell-style key/value config and may include:

- `PROFILE_NAME`
- `PROCESS_MATCH` (regex used by daemon with `pgrep -f`)
- `CPU_GOVERNOR` (`schedutil`, `performance`)
- `IO_SCHEDULER` (`bfq`, `mq-deadline`)
- `ENABLE_GAMEMODE` (`0|1`)
- `ENV_VARS` (space-separated `KEY=VALUE` list)
- `NICE_LEVEL` (e.g. `-4`)
- `NVIDIA_OFFLOAD` (`0|1`)
- `IRQBALANCE_ONESHOT` (`0|1`)

## C. Kernel & Scheduler Tuning

Default gaming sysctl file:

- `/etc/sysctl.d/99-hyperos-gaming.conf`

Contains conservative, reversible low-latency settings:

- raised `vm.max_map_count`
- moderate `vm.swappiness`
- tighter dirty memory ratios
- `kernel.sched_autogroup_enabled=1`

For lowest latency on specific systems, optional low-latency kernels can be offered as an install-time choice; default stays on standard Arch kernel for stability.

## D. Integration

Service:

- `hyperos-gamed.service` enabled by default in image customization.

Steam launch option example:

```bash
hyperos-game-launch --profile steam-default -- %command%
```

Lutris command prefix example:

```bash
hyperos-game-launch --profile lutris-default --
```

## E. Validation

```bash
systemctl status hyperos-gamed.service
journalctl -u hyperos-gamed.service -f
pgrep -fa steam_app_
```

Simulate launch:

```bash
PROFILE_DIR=/etc/hyperos/game-profiles hyperos-game-launch --profile steam-default -- /usr/bin/env | rg 'MANGOHUD|WINE|DXVK|NV_'
```

Verify governor/scheduler switching:

```bash
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
cat /sys/block/nvme0n1/queue/scheduler
```

## F. Limitations

- Anti-cheat protected titles can reject custom wrappers or env vars.
- Some DRM launchers ignore external process wrappers.
- Per-game GPU power management differs by vendor/driver stack.
- On systems without writable cpufreq/scheduler sysfs nodes, daemon degrades gracefully.

## G. Future Improvements

- Profile recommendation via telemetry/AI-assisted scoring.
- Wayland-native integration and Gamescope session mode.
- Per-GPU optimization modules (NVIDIA, AMD, Intel profiles).
- Event-based process detection (eBPF/inotify) to replace polling.
