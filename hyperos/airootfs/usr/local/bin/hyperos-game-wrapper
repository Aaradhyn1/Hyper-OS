#!/usr/bin/env bash
set -Eeuo pipefail

PROFILE="${HYPEROS_GAME_PROFILE:-/etc/hyperos/game-profiles/default.profile}"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <command> [args...]" >&2
  exit 1
fi

if [[ -f "$PROFILE" ]]; then
  # shellcheck disable=SC1090
  source "$PROFILE"
fi

if [[ "${GPU_OFFLOAD:-auto}" == "nvidia" ]]; then
  export __NV_PRIME_RENDER_OFFLOAD=1
  export __GLX_VENDOR_LIBRARY_NAME=nvidia
  export __VK_LAYER_NV_optimus=NVIDIA_only
fi

for kv in $(env | grep '^ENV_' || true); do
  key="${kv%%=*}"
  val="${kv#*=}"
  export "${key#ENV_}=$val"
done

if [[ "${USE_GAMEMODE:-0}" == "1" ]] && command -v gamemoderun >/dev/null 2>&1; then
  exec gamemoderun "$@"
else
  exec "$@"
fi
