#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${FLOW_DIR}"

mkdir -p log reports summaryReport timingReports enc def

INNOVUS_BIN="${INNOVUS_BIN:-}"
if [ -z "${INNOVUS_BIN}" ]; then
  if command -v innovus >/dev/null 2>&1; then
    INNOVUS_BIN="$(command -v innovus)"
  else
    echo "Cannot find innovus. Source the Innovus environment first." >&2
    exit 1
  fi
fi

"${INNOVUS_BIN}" -64 -overwrite -log log/innovus.log -files scripts/run_innovus.tcl

if [ -f def/amoeba.def ]; then
  python3 scripts/export_def_layout_svg.py \
    --def-file def/amoeba.def \
    --output reports/amoeba_layout.svg \
    --title "AMOEBA 4x4 Multi-CGRA Post-Route Layout"
fi

