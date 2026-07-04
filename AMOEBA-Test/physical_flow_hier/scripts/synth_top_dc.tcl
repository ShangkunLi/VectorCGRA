# Stage 2: synthesize the 4x4 multi-CGRA top around the mapped core block.

source scripts/flow_config.tcl
source $MODULE_NAMES_TCL
set CLK_PERIOD $CLK_PERIOD_PS

foreach dir [list $REPORT_DIR $RESULT_DIR $HANDOFF_DIR] {
    file mkdir $dir
}

if {![file exists $TOP_ONLY_RTL]} {
    puts stderr "Top-only RTL not found: $TOP_ONLY_RTL. Run scripts/run_dc_hier.sh from the flow directory."
    exit 1
}
if {![file exists $CORE_DDC]} {
    puts stderr "Core DDC not found: $CORE_DDC. Run the core stage first."
    exit 1
}
foreach db_file $DC_DB_FILES {
    if {![file exists $db_file]} {
        puts stderr "DC .db file not found: $db_file"
        exit 1
    }
}

set_app_var search_path [concat [list . [file dirname $TOP_ONLY_RTL]] [file dirname [lindex $DC_DB_FILES 0]]]
set_app_var target_library $DC_DB_FILES
set_app_var link_library [concat [list "*" $CORE_DDC] $DC_DB_FILES dw_foundation.sldb]
set_app_var synthetic_library dw_foundation.sldb
set_host_options -max_cores $DC_CORES

set_units -time ps -resistance kOhm -capacitance pF -voltage V -current mA

define_design_lib WORK -path ./WORK_top

# Load the mapped core first, then elaborate top RTL without the core module
# definition. The top's cgra__* instances resolve to this DDC design.
read_ddc $CORE_DDC
set_dont_touch [get_designs $CORE_MODULE] true

analyze -format sverilog $TOP_ONLY_RTL
elaborate $TOP_MODULE
current_design $TOP_MODULE
link
uniquify

set_ungroup [get_designs *] false
set core_cells [get_cells -hierarchical -quiet -filter "ref_name == $CORE_MODULE"]
if {[sizeof_collection $core_cells] == 0} {
    puts stderr "No core cells with ref_name $CORE_MODULE were found after link."
    exit 1
}
set_dont_touch $core_cells true

create_clock [get_ports $CLK_PORT] -name sys_clk -period $CLK_PERIOD -waveform [list 0 [expr {$CLK_PERIOD / 2}]]
if {[sizeof_collection [get_ports -quiet $RESET_PORT]] > 0} {
    set_false_path -from [get_ports $RESET_PORT]
}

# The repeated core is already mapped. Keep top synthesis modest so DC mainly
# maps inter-core NoC and top-level glue instead of re-optimizing the full chip.
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
    report_area $cells -hierarchy > $report_file
}

report_area -hierarchy > ${REPORT_DIR}/dc_area.rpt
report_area $core_cells -hierarchy > ${REPORT_DIR}/dc_area_core_instances.rpt
write_area_report_for_pattern "*cgra__*" ${REPORT_DIR}/dc_area_cgra_cells.rpt
write_area_report_for_pattern "*routers*" ${REPORT_DIR}/dc_area_inter_core_noc.rpt
report_timing -delay_type max -max_paths 50 > ${REPORT_DIR}/dc_timing.rpt
report_power -hierarchy > ${REPORT_DIR}/dc_power.rpt
report_qor > ${REPORT_DIR}/dc_qor.rpt

write -format verilog -hierarchy -output $NETLIST
write -format ddc -hierarchy -output ${RESULT_DIR}/${DESIGN}.ddc
write_sdc $SDC_FILE

exit
