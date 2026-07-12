#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${FLOW_DIR}"

mkdir -p log reports/layout

if [ -z "${DISPLAY:-}" ]; then
  echo "DISPLAY is not set; Innovus cannot create its GUI." >&2
  echo "Run this command from your VNC/X11 desktop terminal." >&2
  exit 1
fi

INNOVUS_BIN="${INNOVUS_BIN:-}"
if [ -z "${INNOVUS_BIN}" ]; then
  if type -P innovus >/dev/null 2>&1; then
    # Resolve the executable path so a shell function/alias cannot silently
    # inject -nowin or -no_gui into this interactive export.
    INNOVUS_BIN="$(type -P innovus)"
  else
    echo "Cannot find innovus. Source the Innovus environment first." >&2
    exit 1
  fi
fi

echo "Opening the routed design in Innovus GUI for interactive high-resolution export."
echo "DISPLAY=${DISPLAY}"
echo "Maximize the layout canvas, then run: amoeba_export_multicore_layout"
# Do not add -nowin or -no_gui here. The startup Tcl explicitly executes `win`
# (with a gui_show fallback) to create and raise the Innovus main window.
"${INNOVUS_BIN}" -64 -overwrite -log log/export_layout_image.log -files scripts/export_layout_image.tcl

if [ "${POSTPROCESS_LAYOUT:-1}" = "1" ]; then
  DESIGN=amoeba_grid scripts/postprocess_layout_image.sh
fi
