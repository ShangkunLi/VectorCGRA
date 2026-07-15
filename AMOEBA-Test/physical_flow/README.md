# AMOEBA Physical Evaluation Flow

This folder contains a small DC + Innovus handoff flow for the generated
AMOEBA 4x4 multi-CGRA RTL.

The flow is intentionally configured through one Tcl file:

```text
scripts/flow_config.tcl
```

Do not pass design or technology settings through shell environment variables.
If the RTL path, clock frequency, top module, or technology files change, edit
`scripts/flow_config.tcl`.

## What DC and Innovus do

Design Compiler (DC) is the logic synthesis step. It reads the AMOEBA RTL
SystemVerilog, the timing library, and the clock constraint, then emits a
technology-mapped gate-level netlist plus reports for area, timing, and power.

Innovus is the physical implementation step. It reads the synthesized netlist,
LEF/QRC/Liberty technology files, and the SDC constraint, then runs floorplan,
placement, clock tree synthesis, routing, DRC/connectivity checks, and
post-route reports.

In short:

```text
AMOEBA RTL -> DC -> gate netlist -> Innovus -> placed/routed layout + PPA
```

The reference package in `../reference-cgra-evaluation.zip` starts from a
synthesized netlist (`inputs/cgra_netlist.v`). This flow adds the missing DC
stage for our generated AMOEBA RTL.

## Expected input

The default RTL path, configured in `scripts/flow_config.tcl`, is:

```text
../generated/AmoebaMultiCgra4x4Cgra2x2RTL.v
```

The default top module is:

```text
AmoebaMultiCgra4x4Cgra2x2RTL
```

## Run on ECE LAB7 VDI

After logging into ECE LAB7, first source the EDA environment provided by the
course. If the lab package has `setup.sh`, prefer:

```bash
source setup.sh
```

Otherwise source DC and Innovus manually according to the lab handout.

Then check the configuration:

```bash
cd /dfs/usrhome/slifd/VectorCGRA/AMOEBA-Test/physical_flow
vim scripts/flow_config.tcl
```

The checked-in default targets the TSMC22 ULL library and 500 MHz:

```tcl
set CLK_PERIOD_PS 2000
set TECH_ROOT "/usr/eelocal/tsmc_icdc/tsmc022/tsmc022_ULL"
set DC_DB_FILES [list \
    "${TSMC22_NLDM_DIR}/tcbn22ullbwp30p140lvtffg0p88v0c.db" \
]
```

Run synthesis and physical implementation:

```bash
./scripts/run_dc.sh
./scripts/run_innovus.sh
```

Recompute synthesis power with the same vectorless 20% activity used by the
Innovus reports, without rerunning `compile_ultra`:

```bash
./scripts/run_dc_power_20pct.sh
```

This requires the mapped `results/amoeba.ddc` produced by `run_dc.sh`. It sets
all non-clock primary inputs and all sequential output pins to 0.2 transitions
per `sys_clk` cycle with static probability 0.5. This matches the Innovus
report fields `Primary Input Activity: 0.200000` and
`Sequential Element Activity: 0.200000`. The generated reports are:

```text
reports/dc_power_20pct_summary.rpt
reports/dc_power_20pct_hierarchy.rpt
reports/dc_power_20pct_clock_check.rpt
reports/dc_power_20pct_metadata.txt
log/dc_power_20pct.log
```

Useful outputs:

```text
syn_handoff/amoeba.v          synthesized netlist from DC
syn_handoff/amoeba.sdc        SDC emitted by DC
reports/dc_area.rpt           DC area report
reports/dc_timing.rpt         DC timing report
reports/dc_power.rpt          DC power report
summaryReport/post_route.sum  Innovus post-route summary
amoeba_DETAILS.rpt            compact Innovus PPA table by stage
reports/innovus_area_breakdown.csv
                              top-level post-route physical area breakdown
reports/innovus_tile_area_breakdown.csv
                              tile-internal post-route physical area breakdown
def/amoeba.def                routed DEF
enc/amoeba.enc                final Innovus database
```

## Configuration

All design and technology settings are centralized in:

```text
scripts/flow_config.tcl
```

The current default is:

```text
clock: 500 MHz, 2000 ps period
top:   AmoebaMultiCgra4x4Cgra2x2RTL
tech:  /usr/eelocal/tsmc_icdc/tsmc022/tsmc022_ULL
DC db: tcbn22ullbwp30p140lvtffg0p88v0c.db
```

For the library shown in the ELEC6910 setup screenshot, this is the DC library
used by `scripts/flow_config.tcl`:

```text
/usr/eelocal/tsmc_icdc/tsmc022/tsmc022_ULL/SC/tcbn22ullbwp30p140lvt/Rev110b/Front_End/timing_power_noise/NLDM/tcbn22ullbwp30p140lvt_110b/tcbn22ullbwp30p140lvtffg0p88v0c.db
```

If Innovus cannot auto-discover LEF/QRC files under the same TSMC22 root, run
these on ECE LAB7:

```bash
find /usr/eelocal/tsmc_icdc/tsmc022/tsmc022_ULL -name '*.lef'
find /usr/eelocal/tsmc_icdc/tsmc022/tsmc022_ULL -name '*.tch'
```

Then put the exact files into `INNOVUS_TECH_LEF_FILES`,
`INNOVUS_CELL_LEF_FILES`, and `INNOVUS_QRC_FILE` inside
`scripts/flow_config.tcl`. The technology LEF must be loaded before the
standard-cell LEF; otherwise Innovus sees cell pins on layers like `M1` before
those layers are defined.

For example:

```tcl
set INNOVUS_TECH_LEF_FILES [list \
    "/path/to/tech.lef" \
]
set INNOVUS_CELL_LEF_FILES [list \
    "/path/to/stdcell.lef" \
]
set INNOVUS_QRC_FILE "/path/to/qrc.tch"
```

Use `INNOVUS_LEF_FILES` only when you want to override the complete ordered LEF
list yourself.

Do the same for `INNOVUS_LIB_FILES` only if automatic `.lib` discovery under
`TECH_ROOT` selects the wrong corner files.

## Common edits

Change the target frequency:

```tcl
# 500 MHz
set CLK_PERIOD_PS 2000

# 1 GHz
set CLK_PERIOD_PS 1000
```

Change the RTL or top module:

```tcl
set TOP_MODULE "AmoebaMultiCgra4x4Cgra2x2RTL"
set RTL_FILE "../generated/AmoebaMultiCgra4x4Cgra2x2RTL.v"
```

Change floorplan density:

```tcl
set FP_UTIL 0.55
set FP_MARGIN 5
```

If Innovus reports an unknown site, inspect the technology LEF for `SITE ...`
and update:

```tcl
set SITE "unit"
```

## Area Breakdown

After `./scripts/run_innovus.sh`, the flow writes two CSV files from the final
Innovus database:

```text
reports/innovus_area_breakdown.csv
reports/innovus_tile_area_breakdown.csv
```

`innovus_area_breakdown.csv` is the top-level physical breakdown:

```text
Tiles (x64)
Core Controllers (x16)
Loop Controllers (x16)
Inter-Core NoC
Other
Total
```

The current RTL does not instantiate real SPM/SRAM macros. Any placeholder data
memory/interface logic is folded into `Other`; do not report it as SPM area.

`innovus_tile_area_breakdown.csv` is the tile-internal physical breakdown:

```text
DCUs
Other FUs
Register File
Crossbar
Configuration Memories
Other Tile Logic
Tiles (x64)
```

If a category is zero, inspect the preserved instance names in Innovus and
adjust the matching patterns in `scripts/report_utils.tcl`.

For paper figures, describe this as a post-route logic-area breakdown. Add SPM
macro area only after the RTL flow instantiates actual memory macros.
