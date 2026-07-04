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
```

Then run the macro-based Innovus path:

```bash
bash ./scripts/run_innovus_macro.sh
```

This hard-macro path first hardens one CGRA core, removes the core module
implementation from the top netlist, then places/routes the 4x4 top with
16 core macro instances.

Useful outputs:

```text
block_handoff/amoeba_cgra_core.v      flattened mapped core netlist
block_handoff/amoeba_cgra_core.ddc    flattened mapped core DDC
syn_handoff/amoeba.v                  DC top netlist before macro abstraction
syn_handoff/amoeba_top_macro.v        top netlist with core implementation removed
syn_handoff/amoeba.sdc                final top SDC
block_handoff/amoeba_cgra_core.sdc    core-only SDC
block_handoff/amoeba_cgra_core.lef    Innovus core macro abstract
block_handoff/amoeba_cgra_core.def    routed core DEF
reports/core_area_hier.rpt            core area before flattening
reports/core_timing.rpt               core timing report
reports/dc_area.rpt                   final top area report
reports/dc_area_core_instances.rpt    area of all 16 mapped core instances
reports/dc_timing.rpt                 final top timing report
reports/dc_power.rpt                  final top power report
reports/amoeba_macro_layout.svg       vector layout figure from macro-top DEF
summaryReport/core/post_route.sum     core macro post-route summary
summaryReport/top_macro/post_route.sum macro-top post-route summary
def/core/amoeba_cgra_core.def         routed core DEF
def/top_macro/amoeba.def              routed macro-top DEF
enc/core/amoeba_cgra_core.enc         final core Innovus database
enc/top_macro/amoeba.enc              final macro-top Innovus database
```

## Why this flow exists

The one-shot `physical_flow` version asks DC to optimize the whole 64-tile
system at once. That can spend many hours in global optimization and leakage
fixing. This flow performs the expensive optimization once on the repeated core
and then assembles the top-level inter-core network around 16 mapped copies.

The macro flow uses the DC outputs but treats each core as a hardened macro
when placing/routing the 4x4 top. For paper tables, use:

- `reports/core_area_hier.rpt` for tile/controller/loop-controller breakdown
  inside one core.
- `reports/innovus_core_area_breakdown.csv` for the routed core breakdown.
- `reports/innovus_top_macro_area_breakdown.csv` and
  `summaryReport/top_macro/post_route.sum` for top-level macro integration.
- CACTI-estimated 32KB/core SPM macro area as a separate macro-area add-on.


## Export Layout SVG Only

After Innovus has produced `def/top_macro/amoeba.def`, regenerate the vector
figure with:

```bash
python3 scripts/export_def_layout_svg.py \
  --def-file def/top_macro/amoeba.def \
  --output reports/amoeba_macro_layout.svg \
  --title "AMOEBA 4x4 Multi-CGRA Macro-Level Post-Route Layout"
```

The SVG is generated from the post-route DEF. It is a paper-friendly vector
layout summary: die outline, standard-cell placement density, and CGRA hierarchy
boxes. The DEF remains the authoritative detailed physical layout database.
