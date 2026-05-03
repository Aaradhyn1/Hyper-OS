#!/usr/bin/env bash
set -Eeuo pipefail

OUT_DIR="${OUT_DIR:-./out/benchmarks}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
REPORT="$OUT_DIR/benchmark-$STAMP.txt"

mkdir -p "$OUT_DIR"

{
  echo "# Hyper OS Benchmark Snapshot ($STAMP UTC)"
  echo
  echo "## Boot"
  systemd-analyze || true
  systemd-analyze blame | head -n 20 || true
  systemd-analyze critical-chain || true

  echo
  echo "## CPU / load"
  uptime || true
  top -b -n1 | head -n 20 || true

  echo
  echo "## Memory"
  free -h || true
  command -v smem >/dev/null 2>&1 && smem -rtk | head -n 20 || true

  echo
  echo "## Disk IO"
  command -v iostat >/dev/null 2>&1 && iostat -xz 1 3 || true

  echo
  echo "## Services"
  systemctl --failed || true
} > "$REPORT"

echo "benchmark written: $REPORT"
