#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${FLOW_DIR}"

mkdir -p log reports summaryReport timingReports enc def block_handoff syn_handoff

require_file() {
  local path="$1"
  local producer="$2"
  if [ ! -s "$path" ]; then
    echo "Expected ${producer} to produce ${path}, but it is missing or empty." >&2
    exit 1
  fi
}

require_file ./syn_handoff/amoeba.v "hierarchical DC"
require_file ./syn_handoff/amoeba.sdc "hierarchical DC"
require_file ./work/module_names.tcl "hierarchical RTL preparation"

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
require_file ./syn_handoff/amoeba_top_macro.v "top macro netlist preparation"

"${INNOVUS_BIN}" -64 -overwrite -log log/innovus_core.log -files scripts/run_core_innovus.tcl
require_file ./block_handoff/amoeba_cgra_core.lef "core Innovus"
require_file ./block_handoff/amoeba_cgra_core.def "core Innovus"
require_file ./summaryReport/core/post_route.sum "core Innovus"

"${INNOVUS_BIN}" -64 -overwrite -log log/innovus_top_macro.log -files scripts/run_top_macro_innovus.tcl
require_file ./def/top_macro/amoeba.def "top macro Innovus"
require_file ./def/top_macro/AmoebaMultiCgra4x4Cgra2x2RTL_post_route.v "top macro Innovus"
require_file ./summaryReport/top_macro/post_route.sum "top macro Innovus"
require_file ./reports/innovus_top_macro_area_breakdown.csv "top macro Innovus"

if [ -f def/top_macro/amoeba.def ]; then
  python3 scripts/export_def_layout_svg.py \
    --def-file def/top_macro/amoeba.def \
    --output reports/amoeba_macro_layout.svg \
    --title "AMOEBA 4x4 Multi-CGRA Macro-Level Post-Route Layout"
fi
require_file ./reports/amoeba_macro_layout.svg "DEF-to-SVG exporter"

echo "Hierarchical Innovus flow is ready: reports/amoeba_macro_layout.svg"
