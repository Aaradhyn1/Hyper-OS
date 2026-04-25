#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "[release-build] failed at line $LINENO" >&2' ERR

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROFILE_SRC="${PROFILE_SRC:-$ROOT_DIR/hyperos}"
REPO_SRC="${REPO_SRC:-$ROOT_DIR/repo}"
RELEASE_ROOT="${RELEASE_ROOT:-$ROOT_DIR/releases}"
WORK_ROOT="${WORK_ROOT:-$ROOT_DIR/work/release}"

VERSION="${HYPER_VERSION:-$(date -u +%Y.%m.%d)}"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$ROOT_DIR" log -1 --pretty=%ct 2>/dev/null || date -u +%s)}"
GIT_SHA="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo "nogit")"
BUILD_ID="${VERSION}-${GIT_SHA}"

RELEASE_DIR="$RELEASE_ROOT/$VERSION"
WORK_DIR="$WORK_ROOT/$BUILD_ID"
PROFILE_DIR="$WORK_DIR/profile"
ARCHISO_WORK="$WORK_DIR/archiso-work"
LOG_DIR="$RELEASE_DIR/logs"
LOG_FILE="$LOG_DIR/build-${BUILD_ID}.log"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing dependency: $1" >&2; exit 1; }
}

prepare_profile() {
  mkdir -p "$RELEASE_DIR" "$WORK_DIR" "$LOG_DIR"
  rm -rf "$PROFILE_DIR" "$ARCHISO_WORK"
  cp -a "$PROFILE_SRC" "$PROFILE_DIR"
  mkdir -p "$PROFILE_DIR/repo"
  if [[ -d "$REPO_SRC/x86_64" ]]; then
    cp -a "$REPO_SRC/x86_64" "$PROFILE_DIR/repo/"
  fi

  cat > "$PROFILE_DIR/airootfs/etc/hyper-release" <<META
HYPER_VERSION=$VERSION
HYPER_BUILD_ID=$BUILD_ID
HYPER_GIT_SHA=$GIT_SHA
HYPER_SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH
META

  cat > "$PROFILE_DIR/airootfs/etc/motd" <<MOTD
Hyper OS $VERSION
Build: $BUILD_ID
MOTD
}

build_iso() {
  echo "[release-build] building Hyper OS $BUILD_ID"
  mkarchiso -v \
    -C "$PROFILE_DIR/pacman.conf" \
    -w "$ARCHISO_WORK" \
    -o "$RELEASE_DIR" \
    "$PROFILE_DIR" \
    2>&1 | tee "$LOG_FILE"
}

write_metadata() {
  local iso_path
  iso_path="$(find "$RELEASE_DIR" -maxdepth 1 -type f -name '*.iso' | sort | tail -n1)"
  [[ -n "$iso_path" ]] || { echo "no ISO produced" >&2; exit 1; }

  sha256sum "$iso_path" > "$iso_path.sha256"

  jq -n \
    --arg version "$VERSION" \
    --arg build_id "$BUILD_ID" \
    --arg git_sha "$GIT_SHA" \
    --arg iso "$(basename "$iso_path")" \
    --arg sha256 "$(awk '{print $1}' "$iso_path.sha256")" \
    --arg profile_checksum "$(sha256sum "$PROFILE_DIR/packages.x86_64" | awk '{print $1}')" \
    --argjson source_date_epoch "$SOURCE_DATE_EPOCH" \
    --arg built_at "$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      version: $version,
      build_id: $build_id,
      git_sha: $git_sha,
      iso: $iso,
      sha256: $sha256,
      source_date_epoch: $source_date_epoch,
      built_at: $built_at,
      package_manifest_sha256: $profile_checksum
    }' > "$RELEASE_DIR/build-meta.json"

  ln -sfn "$VERSION" "$RELEASE_ROOT/latest"

  echo "[release-build] artifact: $iso_path"
  echo "[release-build] metadata: $RELEASE_DIR/build-meta.json"
}

main() {
  require_cmd mkarchiso
  require_cmd sha256sum
  require_cmd jq

  export SOURCE_DATE_EPOCH
  export TZ=UTC
  export LC_ALL=C
  umask 022

  prepare_profile
  build_iso
  write_metadata
}

main "$@"
