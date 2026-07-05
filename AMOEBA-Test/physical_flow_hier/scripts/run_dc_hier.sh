#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${FLOW_DIR}"

mkdir -p log reports results block_handoff syn_handoff work WORK_core WORK_top

require_file() {
  local path="$1"
  local producer="$2"
  if [ ! -s "$path" ]; then
    echo "Expected ${producer} to produce ${path}, but it is missing or empty." >&2
    exit 1
  fi
}

DC_BIN="${DC_BIN:-}"
if [ -z "${DC_BIN}" ]; then
  if command -v dc_shell >/dev/null 2>&1; then
    DC_BIN="$(command -v dc_shell)"
  else
    echo "Cannot find dc_shell. Source the Design Compiler environment first." >&2
    exit 1
  fi
fi

python3 scripts/prepare_hier_rtl.py \
  --rtl ../generated/AmoebaMultiCgra4x4Cgra2x2RTL.v \
  --work-dir ./work \
  --top-only-rtl ./work/amoeba_top_without_core.v \
  --module-names-tcl ./work/module_names.tcl

"${DC_BIN}" -64bit -f scripts/synth_core_dc.tcl | tee log/dc_core.log
require_file ./block_handoff/amoeba_cgra_core.v "core DC"
require_file ./block_handoff/amoeba_cgra_core.ddc "core DC"
require_file ./block_handoff/amoeba_cgra_core.sdc "core DC"
require_file ./reports/core_area_hier.rpt "core DC"
require_file ./reports/core_timing.rpt "core DC"

"${DC_BIN}" -64bit -f scripts/synth_top_dc.tcl  | tee log/dc_top.log
require_file ./syn_handoff/amoeba.v "top DC"
require_file ./syn_handoff/amoeba.sdc "top DC"
require_file ./results/amoeba.ddc "top DC"
require_file ./reports/dc_area.rpt "top DC"
require_file ./reports/dc_timing.rpt "top DC"

echo "Hierarchical DC handoff is ready: syn_handoff/amoeba.v and syn_handoff/amoeba.sdc"
