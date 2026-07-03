# DC synthesis flow for generated AMOEBA RTL.

source scripts/flow_config.tcl
set CLK_PERIOD $CLK_PERIOD_PS

set REPORT_DIR  "reports"
set RESULT_DIR  "results"

file mkdir $REPORT_DIR
file mkdir $RESULT_DIR
file mkdir $HANDOFF_DIR

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

define_design_lib WORK -path ./WORK

analyze -format sverilog $RTL_FILE
elaborate $TOP_MODULE
current_design $TOP_MODULE
link

uniquify
# check_design > ${REPORT_DIR}/dc_check_design.rpt

# Keep the architectural hierarchy visible in reports and in the Innovus
# handoff. This makes tile, regular-controller, and loop-controller area
# breakdowns inspectable after synthesis and physical implementation.
set_app_var compile_ultra_ungroup_dw false
set_ungroup [get_designs *] false

set_units -time ps -resistance kOhm -capacitance pF -voltage V -current mA
create_clock [get_ports $CLK_PORT] -name sys_clk -period $CLK_PERIOD -waveform [list 0 [expr {$CLK_PERIOD / 2}]]

if {[sizeof_collection [get_ports -quiet $RESET_PORT]] > 0} {
    set_false_path -from [get_ports $RESET_PORT]
    set_dont_touch_network [get_ports $RESET_PORT]
}
set_dont_touch_network [get_ports $CLK_PORT]

compile -map_effort medium -area_effort medium

change_names -rules verilog -hierarchy

proc write_area_report_for_pattern {pattern report_file} {
    set cells [get_cells -hierarchical -quiet $pattern]
    if {[sizeof_collection $cells] == 0} {
        set fp [open $report_file w]
        puts $fp "No cells matched pattern: $pattern"
        close $fp
        return
    }
    report_area -hierarchy $cells > $report_file
}

report_area  -hierarchy > ${REPORT_DIR}/dc_area.rpt
write_area_report_for_pattern "*TileRTL*" ${REPORT_DIR}/dc_area_tiles.rpt
write_area_report_for_pattern "*ControllerRTL*" ${REPORT_DIR}/dc_area_regular_controllers.rpt
write_area_report_for_pattern "*LoopController*" ${REPORT_DIR}/dc_area_loop_controllers.rpt
write_area_report_for_pattern "*CgraWithLoopController*" ${REPORT_DIR}/dc_area_cgras.rpt
report_timing -delay_type max -max_paths 50 > ${REPORT_DIR}/dc_timing.rpt
report_power -hierarchy > ${REPORT_DIR}/dc_power.rpt
report_qor > ${REPORT_DIR}/dc_qor.rpt

write -format verilog -hierarchy -output ${HANDOFF_DIR}/${DESIGN}.v
write -format ddc     -hierarchy -output ${RESULT_DIR}/${DESIGN}.ddc
write_sdc ${HANDOFF_DIR}/${DESIGN}.sdc

exit
