#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${FLOW_DIR}"

mkdir -p log reports/layout

INNOVUS_BIN="${INNOVUS_BIN:-}"
if [ -z "${INNOVUS_BIN}" ]; then
  if command -v innovus >/dev/null 2>&1; then
    INNOVUS_BIN="$(command -v innovus)"
  else
    echo "Cannot find innovus. Source the Innovus environment first." >&2
    exit 1
  fi
fi

echo "Opening the routed design in Innovus GUI for interactive high-resolution export."
echo "Maximize the layout canvas, then run: amoeba_export_multicore_layout"
"${INNOVUS_BIN}" -64 -overwrite -log log/export_layout_image.log -files scripts/export_layout_image.tcl

if [ "${POSTPROCESS_LAYOUT:-1}" = "1" ]; then
  DESIGN=amoeba_grid scripts/postprocess_layout_image.sh
fi
