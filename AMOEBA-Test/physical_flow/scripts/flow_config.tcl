# Central configuration for the AMOEBA physical flow.
#
# Keep design, timing, and technology choices here instead of passing them
# through shell environment variables. If the VDI technology path differs,
# edit this file only.

set DESIGN "amoeba"
set TOP_MODULE "AmoebaMultiCgra4x4Cgra2x2RTL"
set RTL_FILE "../generated/AmoebaMultiCgra4x4Cgra2x2RTL.v"

set CLK_PORT "clk"
set RESET_PORT "reset"

# 800 MHz = 1.25 ns = 1250 ps.
set CLK_PERIOD_PS 1250

set DC_CORES 16
set INNOVUS_CPUS 16

set HANDOFF_DIR "./syn_handoff"
set NETLIST "${HANDOFF_DIR}/${DESIGN}.v"
set SDC_FILE "${HANDOFF_DIR}/${DESIGN}.sdc"

# TSMC22 ULL library available in the ELEC6910 EDA environment.
set TECH_ROOT "/usr/eelocal/tsmc_icdc/tsmc022/tsmc022_ULL"
set TSMC22_STD_CELL "tcbn22ullbwp30p140lvt"
set TSMC22_REV "Rev110b"
set TSMC22_NLDM_DIR "${TECH_ROOT}/SC/${TSMC22_STD_CELL}/${TSMC22_REV}/Front_End/timing_power_noise/NLDM/${TSMC22_STD_CELL}_110b"

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
set INNOVUS_QRC_FILE ""
set TSMC22_ROUTING_STACK "5x2z"

# This site name must match the SITE declared in the technology LEF. TSMC
# standard-cell LEFs commonly use "unit"; change here if Innovus reports an
# unknown site.
set SITE "unit"

set TOP_ROUTING_LAYER 9
set FP_UTIL 0.55
set FP_MARGIN 5
set PIN_SPREAD_FRACTION 0.98
