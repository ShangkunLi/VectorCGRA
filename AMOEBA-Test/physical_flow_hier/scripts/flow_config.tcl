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

# 700 MHz = 1.428571 ns = 1428.571 ps.
set CLK_PERIOD_PS 1428.571

set DC_CORES 16

# The current ELEC6910 Innovus license reports 8 allowed CPU jobs. Keeping this
# at the licensed limit avoids noisy tool-side capping while matching the
# reference physical flow.
set INNOVUS_CPUS 8

# The top-level macro flow reuses a post-route CGRA core macro. Keep CTS
# inside the core flow; otherwise Innovus tries to rebuild the internal core
# clock tree from the top macro level.
set TOP_MACRO_RUN_CTS 0

set WORK_DIR "./work"
set REPORT_DIR "./reports"
set RESULT_DIR "./results"
set BLOCK_HANDOFF_DIR "./block_handoff"
set HANDOFF_DIR "./syn_handoff"

set MODULE_NAMES_TCL "${WORK_DIR}/module_names.tcl"
set TOP_ONLY_RTL "${WORK_DIR}/amoeba_top_without_core.v"
set CORE_DDC "${BLOCK_HANDOFF_DIR}/${CORE_DESIGN}.ddc"
set CORE_NETLIST "${BLOCK_HANDOFF_DIR}/${CORE_DESIGN}.v"
set CORE_SDC "${BLOCK_HANDOFF_DIR}/${CORE_DESIGN}.sdc"
set CORE_LEF "${BLOCK_HANDOFF_DIR}/${CORE_DESIGN}.lef"
set CORE_DEF "${BLOCK_HANDOFF_DIR}/${CORE_DESIGN}.def"
set NETLIST "${HANDOFF_DIR}/${DESIGN}.v"
set TOP_MACRO_NETLIST "${HANDOFF_DIR}/${DESIGN}_top_macro.v"
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

# Innovus technology files follow the reference flow style: one matched tuple of
# timing library, technology LEF, standard-cell LEF, and QRC techfile. The QRC
# below is the 1P8M/5x2z stack, so the technology LEF must expose exactly the
# matching route stack. Mixing it with a 9M LEF produces NREX-94 during RC
# extraction.
set INNOVUS_LIB_FILES [list]
set INNOVUS_LEF_FILES [list]
set INNOVUS_TECH_LEF_FILES [list]
set INNOVUS_CELL_LEF_FILES [list]
set INNOVUS_QRC_FILE "/usr/eelocal/tsmc_icdc/tsmc022/tsmc022_ULL/RC_Extraction/Cadence/RC_QRC_cln22ulp_1p8m_5x2z_ut-alrdl_9corners_shrink_1.0p1a/RC_QRC_cln22ulp_1p08m+ut-alrdl_5x2z_typical/qrcTechFile"
set TSMC22_ROUTING_STACK "5x2z"
set TSMC22_TECH_LEF_TOKENS [list "8M" "5X2Z"]
set TSMC22_EXPECTED_ROUTING_LAYER_COUNT 9

# Preferred placement row site. If this site is unavailable after init_design,
# the Innovus scripts fall back to the SITE used by the loaded standard-cell LEF.
set SITE "unit"
set TOP_ROUTING_LAYER 9
set FP_UTIL 0.55
set FP_MARGIN 5
set PIN_SPREAD_FRACTION 0.98
