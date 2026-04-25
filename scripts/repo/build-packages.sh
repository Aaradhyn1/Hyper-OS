#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG_ROOT="${PKG_ROOT:-$ROOT_DIR/packaging}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/repo/x86_64}"
USE_CHROOT="${USE_CHROOT:-1}"
CHROOT_DIR="${CHROOT_DIR:-$ROOT_DIR/work/chroot}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }
}

build_with_makepkg() {
  local pkgdir=$1
  (cd "$pkgdir" && makepkg -s --noconfirm --clean --cleanbuild)
}

build_with_chroot() {
  local pkgdir=$1
  require_cmd mkarchroot
  require_cmd makechrootpkg
  mkdir -p "$CHROOT_DIR"
  if [[ ! -d "$CHROOT_DIR/root" ]]; then
    mkarchroot "$CHROOT_DIR/root" base-devel
  fi
  (cd "$pkgdir" && makechrootpkg -c -r "$CHROOT_DIR")
}

collect_artifacts() {
  mkdir -p "$OUT_DIR"
  find "$PKG_ROOT" -maxdepth 2 -type f \( -name '*.pkg.tar.zst' -o -name '*.pkg.tar.zst.sig' \) -exec cp -f {} "$OUT_DIR/" \;
}

main() {
  require_cmd makepkg

  mapfile -t pkgbuilds < <(find "$PKG_ROOT" -mindepth 2 -maxdepth 2 -name PKGBUILD | sort)
  [[ ${#pkgbuilds[@]} -gt 0 ]] || { echo "no packages found" >&2; exit 1; }

  for pkgbuild in "${pkgbuilds[@]}"; do
    pkgdir="$(dirname "$pkgbuild")"
    echo "[repo-build] building $(basename "$pkgdir")"
    if [[ "$USE_CHROOT" == "1" ]]; then
      build_with_chroot "$pkgdir"
    else
      build_with_makepkg "$pkgdir"
    fi
  done

  collect_artifacts
  echo "[repo-build] packages copied to $OUT_DIR"
}

main "$@"
