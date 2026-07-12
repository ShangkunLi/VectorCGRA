# AMOEBA 4x4 Grid Innovus Flow

This flow reuses the DC handoff produced by `../physical_flow` and runs only
Innovus. It adds reference-style 4x4 placement constraints for the AMOEBA
multi-CGRA cores, then exports paper-friendly layout images with a white grid
overlay.

The timing target is inherited from `../physical_flow`; the current shared
target is 500 MHz, so rerun `../physical_flow/scripts/run_dc.sh` before this
flow whenever `CLK_PERIOD_PS` changes.

## Inputs

By default, the flow expects the existing DC outputs:

```text
../physical_flow/syn_handoff/amoeba.v
../physical_flow/syn_handoff/amoeba.sdc
```

Edit `scripts/flow_config.tcl` if your handoff lives somewhere else.

## Run

On the VDI, source the Cadence/TSMC environment first, then run:

```bash
cd AMOEBA-Test/physical_flow
./scripts/run_dc.sh

cd AMOEBA-Test/physical_flow_grid
./scripts/run_innovus_grid.sh
```

The script runs placement, CTS, routing, post-route checks, and a layout export.

Important outputs:

```text
def/amoeba_grid.def
enc/amoeba_grid.enc.dat
reports/core_grid_regions.rpt
reports/layout/amoeba_grid_post_route_layout.gif
reports/layout/amoeba_grid_post_route_layout.pdf
reports/layout/amoeba_grid_post_route_layout.ps
reports/layout/amoeba_grid_post_route_layout.png
summaryReport/post_route.sum
amoeba_grid_DETAILS.rpt
```

If the implementation is already done and you only want to regenerate the
figure, run:

```bash
./scripts/export_layout_image.sh
```

This opens the restored design in the Innovus GUI instead of exporting from
the small startup canvas. Maximize the window, enlarge the main layout canvas,
and run the following command in the Innovus Console:

```tcl
amoeba_export_multicore_layout
```

The GIF resolution follows the visible layout canvas. Close Innovus after the
export finishes; the shell script will then convert the PDF/PS (or GIF
fallback) into the high-resolution PNG.

## Tuning

The main knobs live in `scripts/flow_config.tcl`:

```tcl
set CORE_GRID_MODE "fence"
set CORE_GRID_CHANNEL 6.0
set CORE_GRID_BOUNDARY_PLACE_BLKG_WIDTH 4.0
set LAYOUT_GRID_COLOR white
set LAYOUT_GRID_LINE_WIDTH 1
```

The exported view keeps the native Innovus routed-layout colors used by
`../physical_flow/scripts/export_paper_layout.tcl`. Each core gets its own thin
outline, so the routing channel remains visible between neighboring boxes.

For a cleaner but harder-to-route figure, increase `CORE_GRID_CHANNEL` or the
boundary blockage width. For faster convergence, lower those values or change
`CORE_GRID_MODE` to `"region"`.

The default flow is trimmed for iteration speed: it skips most intermediate
timing/power report extraction and writes the full reports at the end. Set
`RUN_FULL_STAGE_REPORTS` to `1` if you want the slower, stage-by-stage table.
