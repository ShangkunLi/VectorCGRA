# Central configuration for the baseline physical flow.
#
# Keep design, timing, and technology choices here instead of passing them
# through shell environment variables. If the VDI technology path differs,
# edit this file only.

set DESIGN "baseline"
set TOP_MODULE "BaselineMultiCgra4x4Cgra2x2RTL"
set RTL_FILE "../generated/BaselineMultiCgra4x4Cgra2x2RTL.v"

set CLK_PORT "clk"
set RESET_PORT "reset"

# 700 MHz = 1.428571 ns = 1428.571 ps.
set CLK_PERIOD_PS 1428.571

set DC_CORES 16

# The current ELEC6910 Innovus license reports 8 allowed CPU jobs. Keeping this
# at the licensed limit avoids noisy tool-side capping while matching the
# reference physical flow.
set INNOVUS_CPUS 8

set HANDOFF_DIR "./syn_handoff"
set NETLIST "${HANDOFF_DIR}/${DESIGN}.v"
set SDC_FILE "${HANDOFF_DIR}/${DESIGN}.sdc"

# TSMC22 ULL library available in the ELEC6910 EDA environment.
set TECH_ROOT "/usr/eelocal/tsmc_icdc/tsmc022/tsmc022_ULL"
set TSMC22_STD_CELL "tcbn22ullbwp30p140lvt"
set TSMC22_REV "Rev110b"
set TSMC22_NLDM_DIR "${TECH_ROOT}/SC/${TSMC22_STD_CELL}/${TSMC22_REV}/Front_End/timing_power_noise/NLDM/${TSMC22_STD_CELL}_110b"
set TSMC22_LIB_CORNER "ffg0p88v0c"

set DC_DB_FILES [list \
    "${TSMC22_NLDM_DIR}/tcbn22ullbwp30p140lvtffg0p88v0c.db" \
]

# Innovus technology files are discovered under TECH_ROOT by default. If the
# automatic discovery picks the wrong files, replace the empty lists below with
# explicit paths. INNOVUS_LEF_FILES is a complete ordered override; otherwise
# the flow loads INNOVUS_TECH_LEF_FILES first and INNOVUS_CELL_LEF_FILES second.
set INNOVUS_LIB_FILES [list]
set INNOVUS_LEF_FILES [list]
set INNOVUS_TECH_LEF_FILES [list]
set INNOVUS_CELL_LEF_FILES [list]
set INNOVUS_QRC_FILE "/usr/eelocal/tsmc_icdc/tsmc022/tsmc022_ULL/RC_Extraction/Cadence/RC_QRC_cln22ulp_1p8m_5x2z_ut-alrdl_9corners_shrink_1.0p1a/RC_QRC_cln22ulp_1p08m+ut-alrdl_5x2z_typical/qrcTechFile"
set TSMC22_ROUTING_STACK "5x2z"
set TSMC22_TECH_LEF_TOKENS [list "8M" "5X2Z"]
set TSMC22_EXPECTED_ROUTING_LAYER_COUNT 9

# Preferred placement row site. If this site is unavailable after init_design,
# run_innovus.tcl falls back to the SITE used by the loaded standard-cell LEF.
set SITE "unit"

set TOP_ROUTING_LAYER 9
set FP_UTIL 0.38
set FP_MARGIN 3
set PIN_SPREAD_FRACTION 0.98

# Flat Innovus flow: keep the synthesized hierarchy visible, but guide the
# physical placement into a regular 4x4 CGRA-core grid. Each logical core is a
# 2x2 tile array; do not group by local tile__0..tile__3, because those names
# repeat inside every core.
set CORE_GRID_ENABLE 1
set CORE_GRID_ROWS 4
set CORE_GRID_COLS 4
set CORE_GRID_MODE "fence"
set CORE_GRID_CHANNEL 8.0

# Soft boundary blockages make the exported layout visibly tiled while still
# allowing the router to cross tile boundaries when needed.
set CORE_GRID_BOUNDARY_PLACE_BLKG 1
set CORE_GRID_BOUNDARY_PLACE_BLKG_WIDTH 4.0
set CORE_GRID_BOUNDARY_ROUTE_BLKG 0
set CORE_GRID_BOUNDARY_ROUTE_BLKG_WIDTH 2.0
set CORE_GRID_BOUNDARY_ROUTE_LAYERS {M2 M3 M4}
