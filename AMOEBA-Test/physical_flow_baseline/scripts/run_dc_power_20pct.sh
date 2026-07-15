#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${FLOW_DIR}"

mkdir -p log reports

DC_BIN="${DC_BIN:-}"
if [ -z "${DC_BIN}" ]; then
  if command -v dc_shell >/dev/null 2>&1; then
    DC_BIN="$(command -v dc_shell)"
  else
    echo "Cannot find dc_shell. Source the Design Compiler environment first." >&2
    exit 1
  fi
fi

"${DC_BIN}" -64bit -f scripts/report_dc_power_20pct.tcl \
  | tee log/dc_power_20pct.log
