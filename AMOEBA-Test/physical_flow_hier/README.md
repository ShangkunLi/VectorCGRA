# AMOEBA Hierarchical Physical Flow

This flow avoids synthesizing the full 4x4 multi-CGRA as one huge flat DC
problem. It uses two DC stages:

1. Synthesize one `CgraWithLoopControllerRTL__*` core with `compile_ultra`.
2. Synthesize the 4x4 top around that mapped core, keeping all 16 core
   instances as pre-synthesized blocks.

The generated PyMTL Verilog has a hash suffix on the core module name. The flow
finds that name automatically and writes it to `work/module_names.tcl`.

## Run

From this directory on the ECE LAB7 VDI:

```bash
./scripts/run_dc_hier.sh
./scripts/run_innovus.sh
```

If Innovus reports that layer `M1` is missing while reading a standard-cell
macro, check `scripts/flow_config.tcl`: the technology LEF must be listed in
`INNOVUS_TECH_LEF_FILES` before the LVT standard-cell LEF in
`INNOVUS_CELL_LEF_FILES`. Leaving both lists empty asks the shared setup script
to discover and order them automatically.

Useful outputs:

```text
block_handoff/amoeba_cgra_core.v      flattened mapped core netlist
block_handoff/amoeba_cgra_core.ddc    flattened mapped core DDC
syn_handoff/amoeba.v                  final top netlist for Innovus
syn_handoff/amoeba.sdc                final top SDC
reports/core_area_hier.rpt            core area before flattening
reports/core_timing.rpt               core timing report
reports/dc_area.rpt                   final top area report
reports/dc_area_core_instances.rpt    area of all 16 mapped core instances
reports/dc_timing.rpt                 final top timing report
reports/dc_power.rpt                  final top power report
reports/amoeba_layout.svg             vector layout figure from post-route DEF
summaryReport/post_route.sum          Innovus post-route summary
def/amoeba.def                        routed DEF
enc/amoeba.enc                        final Innovus database
```

## Why this flow exists

The one-shot `physical_flow` version asks DC to optimize the whole 64-tile
system at once. That can spend many hours in global optimization and leakage
fixing. This flow performs the expensive optimization once on the repeated core
and then assembles the top-level inter-core network around 16 mapped copies.

The final top netlist still contains all 16 cores, so Innovus can place and
route the full 4x4 AMOEBA design. For paper tables, use:

- `reports/core_area_hier.rpt` for tile/controller/loop-controller breakdown
  inside one core.
- `reports/dc_area.rpt` and Innovus post-route reports for the whole chip.
- CACTI-estimated 32KB/core SPM macro area as a separate macro-area add-on.


## Export Layout SVG Only

After Innovus has produced `def/amoeba.def`, regenerate the vector figure with:

```bash
python3 scripts/export_def_layout_svg.py \
  --def-file def/amoeba.def \
  --output reports/amoeba_layout.svg \
  --title "AMOEBA 4x4 Multi-CGRA Post-Route Layout"
```

The SVG is generated from the post-route DEF. It is a paper-friendly vector
layout summary: die outline, standard-cell placement density, and CGRA hierarchy
boxes. The DEF remains the authoritative detailed physical layout database.
