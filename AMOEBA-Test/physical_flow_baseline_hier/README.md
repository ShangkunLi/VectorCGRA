# Baseline Hierarchical Physical Flow

This flow is copied from `physical_flow_hier`, but evaluates the baseline
physical design instead of the full AMOEBA design. The baseline top is still a
4x4 multi-CGRA system and each CGRA is still a 2x2 tile array, but:

- the per-CGRA loop controller is removed,
- counter/predicate extraction FUs are removed from the tile FU list, and
- direct boundary-tile data links between neighboring CGRAs are tied off.

The inter-CGRA packet mesh and regular controller path remain, so the design is
still a real multi-CGRA baseline rather than a single-core simplification.

## Generate RTL

From `AMOEBA-Test`:

```bash
python3 generate_baseline_4x4_rtl.py \
  --output-dir ./generated \
  --module-name BaselineMultiCgra4x4Cgra2x2RTL \
  --output-file BaselineMultiCgra4x4Cgra2x2RTL.v
```

## Run Physical Flow

From this directory on the ECE LAB7 VDI:

```bash
./scripts/run_dc_hier.sh
./scripts/run_innovus_macro.sh
```

Useful outputs:

```text
block_handoff/baseline_cgra_core.v      mapped baseline core netlist
block_handoff/baseline_cgra_core.ddc    mapped baseline core DDC
syn_handoff/baseline.v                  DC top netlist before macro abstraction
syn_handoff/baseline_top_macro.v        top netlist with core implementation removed
syn_handoff/baseline.sdc                final top SDC
block_handoff/baseline_cgra_core.lef    Innovus core macro abstract
block_handoff/baseline_cgra_core.def    routed core DEF
reports/core_area_hier.rpt              core area before flattening
reports/dc_area.rpt                     final top area report
reports/dc_timing.rpt                   final top timing report
reports/baseline_macro_layout.svg       vector macro-level layout figure
summaryReport/core/post_route.sum       core macro post-route summary
summaryReport/top_macro/post_route.sum  macro-top post-route summary
def/top_macro/baseline.def              routed macro-top DEF
enc/top_macro/baseline.enc              final macro-top Innovus database
```
