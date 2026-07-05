# Stage 1: synthesize one baseline 2x2 CGRA core with regular controller only.

source scripts/flow_config.tcl
source $MODULE_NAMES_TCL
set CLK_PERIOD $CLK_PERIOD_PS

foreach dir [list $REPORT_DIR $RESULT_DIR $BLOCK_HANDOFF_DIR] {
    file mkdir $dir
}

if {![file exists $RTL_FILE]} {
    puts stderr "RTL file not found: $RTL_FILE"
    exit 1
}
foreach db_file $DC_DB_FILES {
    if {![file exists $db_file]} {
        puts stderr "DC .db file not found: $db_file"
        exit 1
    }
}

set_app_var search_path [concat [list . [file dirname $RTL_FILE]] [file dirname [lindex $DC_DB_FILES 0]]]
set_app_var target_library $DC_DB_FILES
set_app_var link_library [concat [list "*"] $DC_DB_FILES dw_foundation.sldb]
set_app_var synthetic_library dw_foundation.sldb
set_host_options -max_cores $DC_CORES

set_units -time ps -resistance kOhm -capacitance pF -voltage V -current mA

define_design_lib WORK -path ./WORK_core

analyze -format sverilog $RTL_FILE
elaborate $CORE_MODULE
current_design $CORE_MODULE
link
uniquify

# Keep the useful core hierarchy for the reports written before flattening.
set_app_var compile_ultra_ungroup_dw false
set_ungroup [get_designs *] false

create_clock [get_ports $CLK_PORT] -name sys_clk -period $CLK_PERIOD -waveform [list 0 [expr {$CLK_PERIOD / 2}]]
if {[sizeof_collection [get_ports -quiet $RESET_PORT]] > 0} {
    set_false_path -from [get_ports $RESET_PORT]
}

compile_ultra -no_autoungroup

report_area -hierarchy > ${REPORT_DIR}/core_area_hier.rpt
report_timing -delay_type max -max_paths 50 > ${REPORT_DIR}/core_timing.rpt
report_power -hierarchy > ${REPORT_DIR}/core_power.rpt
report_qor > ${REPORT_DIR}/core_qor.rpt
write -format verilog -hierarchy -output ${BLOCK_HANDOFF_DIR}/${CORE_DESIGN}_hier.v
write -format ddc -hierarchy -output ${RESULT_DIR}/${CORE_DESIGN}_hier.ddc

# Flatten only the handoff copy. This avoids duplicate RTL subdesign names when
# the top stage reads the original top RTL plus this pre-synthesized core.
ungroup -all -flatten
change_names -rules verilog -hierarchy
write -format verilog -hierarchy -output $CORE_NETLIST
write -format ddc -hierarchy -output $CORE_DDC
write_sdc $CORE_SDC

exit
