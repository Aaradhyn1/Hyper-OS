# Hyper OS Cloud Game Profiles

## A. Architecture

Hyper OS cloud profiles use a simple offline-first flow:

1. Remote JSON feed (`index.json` + per-game JSON files)
2. Local cache in `/var/lib/hyperos/profiles/`
3. Launcher merge/apply in `hyperos-game-launch`
4. Automatic updates via systemd timer

If the network or server is unavailable, local cached profiles remain active.

## B. JSON Profile Format

```json
{
  "version": 1,
  "game_name": "Counter-Strike 2",
  "launcher": "steam",
  "proton_version": "native",
  "environment_variables": { "MANGOHUD": "0", "WINEESYNC": "1" },
  "dxvk_config": { "DXVK_HUD": "0", "DXVK_ASYNC": "1" },
  "vkd3d_config": { "VKD3D_CONFIG": "" },
  "gamemode": true,
  "notes": "Competitive low-latency baseline"
}
```

Required keys validated locally:
- `version`, `game_name`, `launcher`

## C. Update Script

- Script: `/usr/local/bin/hyperos-profile-update`
- Config: `/etc/hyperos/cloud-profiles.conf`
- Cache: `/var/lib/hyperos/profiles/`

Behavior:
- Downloads `index.json`
- Validates schema with `jq`
- Downloads listed profiles
- Rejects invalid JSON files
- Keeps existing cache when offline

## D. Integration

`hyperos-game-launch` behavior:

1. Loads local profile from `/etc/hyperos/game-profiles/<name>.conf`
2. If `/var/lib/hyperos/profiles/<name>.json` exists and validates, cloud fields override local launch env
3. Falls back to local-only profile if cloud JSON is invalid
4. Falls back to raw command if local profile is missing

## E. systemd Timer

- `hyperos-profile-update.service` (oneshot updater)
- `hyperos-profile-update.timer` (boot + 24h periodic)

Manual update command:

```bash
sudo hyperos-profile-update
```

## F. Validation

```bash
sudo systemctl start hyperos-profile-update.service
systemctl status hyperos-profile-update.service
ls -lah /var/lib/hyperos/profiles/
jq . /var/lib/hyperos/profiles/cs2.json
PROFILE_DIR=/etc/hyperos/game-profiles CLOUD_PROFILE_DIR=/var/lib/hyperos/profiles hyperos-game-launch --profile cs2 -- /usr/bin/env | rg 'MANGOHUD|WINE|DXVK|HYPEROS_PROTON_VERSION'
```

## G. Limitations

- Requires `curl` + `jq` locally.
- Remote feed authenticity should be strengthened with signatures in future.
- Cloud profile naming convention must match local profile names.

## H. Future Improvements

- Signed profile manifests (Ed25519)
- Profile channel selection (`stable`, `beta`, `community`)
- Optional, consent-only anonymous telemetry (frame-time buckets + crash counts only)
