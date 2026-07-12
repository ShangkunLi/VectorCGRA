# Configuration for the AMOEBA 4x4 grid Innovus-only flow.
#
# This file intentionally imports the working technology setup from
# ../physical_flow and overrides only the handoff path plus grid/export knobs.

set ::AMOEBA_GRID_SCRIPT_DIR [file dirname [file normalize [info script]]]
set ::AMOEBA_GRID_FLOW_DIR [file dirname $::AMOEBA_GRID_SCRIPT_DIR]
set ::AMOEBA_BASE_FLOW_DIR [file normalize [file join $::AMOEBA_GRID_FLOW_DIR ".." "physical_flow"]]

source [file join $::AMOEBA_BASE_FLOW_DIR "scripts" "flow_config.tcl"]

set DESIGN "amoeba_grid"
set TOP_MODULE "AmoebaMultiCgra4x4Cgra2x2RTL"

# Timing is inherited from ../physical_flow. That base flow must be rerun after
# changing CLK_PERIOD_PS so this grid flow consumes a fresh 500 MHz SDC.

# Reuse DC output from the existing physical_flow directory.
set HANDOFF_DIR [file normalize [file join $::AMOEBA_BASE_FLOW_DIR "syn_handoff"]]
set NETLIST [file join $HANDOFF_DIR "amoeba.v"]
set SDC_FILE [file join $HANDOFF_DIR "amoeba.sdc"]

# Keep the same technology/floorplan defaults as physical_flow unless the user
# overrides them above. These values match the reference-style layout density.
set FP_UTIL 0.38
set FP_MARGIN 3
set PIN_SPREAD_FRACTION 0.98

# 4x4 logical multi-CGRA floorplan constraints. Each box is one 2x2 CGRA core.
set CORE_GRID_ENABLE 1
set CORE_GRID_ROWS 4
set CORE_GRID_COLS 4
set CORE_GRID_MODE "fence"
set CORE_GRID_CHANNEL 6.0
set CORE_GRID_REQUIRE_ALL_CORES 1
set CORE_GRID_INCLUDE_MESH_ROUTERS 1
set CORE_GRID_REPORT "reports/core_grid_regions.rpt"

# Soft blockages make the exported layout visibly tiled while still allowing
# routing across core boundaries.
set CORE_GRID_BOUNDARY_PLACE_BLKG 1
set CORE_GRID_BOUNDARY_PLACE_BLKG_WIDTH 4.0
set CORE_GRID_BOUNDARY_ROUTE_BLKG 0
set CORE_GRID_BOUNDARY_ROUTE_BLKG_WIDTH 2.0
set CORE_GRID_BOUNDARY_ROUTE_LAYERS {M2 M3 M4}

# Runtime/reporting knobs. The default is optimized for faster figure iteration.
set RUN_FULL_STAGE_REPORTS 0
set SAVE_INTERMEDIATE_DBS 0
set WRITE_POST_ROUTE_NETLIST 0
set ROUTE_SI_DRIVEN true
set ROUTE_TIMING_DRIVEN true

# Layout export knobs.
set LAYOUT_EXPORT_DURING_FLOW 1
set LAYOUT_OUTPUT_DIR "reports/layout"
set LAYOUT_OUTPUT_BASENAME "${DESIGN}_post_route_layout"
set LAYOUT_GRID_COLOR white
set LAYOUT_GRID_LINE_WIDTH 1
set LAYOUT_LABEL_ENABLE 0
set LAYOUT_EXPORT_HARDCOPY 1
