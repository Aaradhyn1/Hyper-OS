#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_NAME="${REPO_NAME:-hyperos}"
REPO_DIR="${REPO_DIR:-$ROOT_DIR/repo/x86_64}"
GPG_KEY_ID="${GPG_KEY_ID:-}"
SIGN_REPO="${SIGN_REPO:-1}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }
}

main() {
  require_cmd repo-add
  mkdir -p "$REPO_DIR"

  shopt -s nullglob
  pkgs=("$REPO_DIR"/*.pkg.tar.zst)
  [[ ${#pkgs[@]} -gt 0 ]] || { echo "no packages found in $REPO_DIR" >&2; exit 1; }

  repo_db="$REPO_DIR/$REPO_NAME.db.tar.gz"

  if [[ "$SIGN_REPO" == "1" ]]; then
    require_cmd gpg
    [[ -n "$GPG_KEY_ID" ]] || { echo "GPG_KEY_ID must be set when SIGN_REPO=1" >&2; exit 1; }
    repo-add --verify --sign --key "$GPG_KEY_ID" "$repo_db" "${pkgs[@]}"

    for pkg in "${pkgs[@]}"; do
      gpg --batch --yes --local-user "$GPG_KEY_ID" --detach-sign --armor "$pkg"
    done
  else
    repo-add "$repo_db" "${pkgs[@]}"
  fi

  ln -sfn "$REPO_NAME.db.tar.gz" "$REPO_DIR/$REPO_NAME.db"
  ln -sfn "$REPO_NAME.files.tar.gz" "$REPO_DIR/$REPO_NAME.files"
  echo "[repo-publish] updated repo metadata in $REPO_DIR"
}

main "$@"
