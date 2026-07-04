# Hierarchical AMOEBA DC/Innovus flow configuration.
#
# This flow synthesizes one 2x2-CGRA core first, then reuses the mapped core
# when assembling the 4x4 multi-CGRA top. Keep all design and technology choices
# here; do not pass them through shell environment variables.

set DESIGN "amoeba"
set CORE_DESIGN "amoeba_cgra_core"
set TOP_MODULE "AmoebaMultiCgra4x4Cgra2x2RTL"
set RTL_FILE "../generated/AmoebaMultiCgra4x4Cgra2x2RTL.v"

set CLK_PORT "clk"
set RESET_PORT "reset"

# 800 MHz = 1.25 ns = 1250 ps.
set CLK_PERIOD_PS 1250

set DC_CORES 16
set INNOVUS_CPUS 8

set WORK_DIR "./work"
set REPORT_DIR "./reports"
set RESULT_DIR "./results"
set BLOCK_HANDOFF_DIR "./block_handoff"
set HANDOFF_DIR "./syn_handoff"

set MODULE_NAMES_TCL "${WORK_DIR}/module_names.tcl"
set TOP_ONLY_RTL "${WORK_DIR}/amoeba_top_without_core.v"
set CORE_DDC "${BLOCK_HANDOFF_DIR}/${CORE_DESIGN}.ddc"
set CORE_NETLIST "${BLOCK_HANDOFF_DIR}/${CORE_DESIGN}.v"
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
# explicit paths.
set INNOVUS_LIB_FILES [list]
set INNOVUS_LEF_FILES [list]
set INNOVUS_QRC_FILE "/usr/eelocal/tsmc_icdc/tsmc022/tsmc022_ULL/RC_Extraction/Cadence/RC_QRC_cln22ulp_1p8m_5x2z_ut-alrdl_9corners_shrink_1.0p1a/RC_QRC_cln22ulp_1p08m+ut-alrdl_5x2z_typical/qrcTechFile"

set SITE "unit"
set TOP_ROUTING_LAYER 9
set FP_UTIL 0.55
set FP_MARGIN 5
set PIN_SPREAD_FRACTION 0.98
