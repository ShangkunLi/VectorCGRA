#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${FLOW_DIR}"

mkdir -p log reports summaryReport timingReports enc def block_handoff syn_handoff

INNOVUS_BIN="${INNOVUS_BIN:-}"
if [ -z "${INNOVUS_BIN}" ]; then
  if command -v innovus >/dev/null 2>&1; then
    INNOVUS_BIN="$(command -v innovus)"
  else
    echo "Cannot find innovus. Source the Innovus environment first." >&2
    exit 1
  fi
fi

python3 scripts/write_blackbox_top_netlist.py \
  --netlist ./syn_handoff/amoeba.v \
  --module-names-tcl ./work/module_names.tcl \
  --output ./syn_handoff/amoeba_top_macro.v

"${INNOVUS_BIN}" -64 -overwrite -log log/innovus_core.log -files scripts/run_core_innovus.tcl
"${INNOVUS_BIN}" -64 -overwrite -log log/innovus_top_macro.log -files scripts/run_top_macro_innovus.tcl

if [ -f def/top_macro/amoeba.def ]; then
  python3 scripts/export_def_layout_svg.py \
    --def-file def/top_macro/amoeba.def \
    --output reports/amoeba_macro_layout.svg \
    --title "AMOEBA 4x4 Multi-CGRA Macro-Level Post-Route Layout"
fi
