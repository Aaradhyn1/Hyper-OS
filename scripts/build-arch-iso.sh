#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE_DIR="$ROOT_DIR/hyperos"

command -v mkarchiso >/dev/null 2>&1 || { echo "mkarchiso is required" >&2; exit 1; }
command -v pacstrap >/dev/null 2>&1 || { echo "pacstrap is required" >&2; exit 1; }

cd "$ROOT_DIR"
mkarchiso -v -w work -o out "$PROFILE_DIR"
