# Re-generate top-level DC area reports from an existing synthesized DDC.
# Use this when synthesis already completed but one of the auxiliary area
# reports failed due to collection/report command syntax.

source scripts/flow_config.tcl
if {[file exists $MODULE_NAMES_TCL]} {
    source $MODULE_NAMES_TCL
}

file mkdir $REPORT_DIR

set TOP_DDC "${RESULT_DIR}/${DESIGN}.ddc"
if {![file exists $TOP_DDC]} {
    puts stderr "Top DDC not found: $TOP_DDC. Run scripts/run_dc_hier.sh first."
    exit 1
}

foreach db_file $DC_DB_FILES {
    if {![file exists $db_file]} {
        puts stderr "DC .db file not found: $db_file"
        exit 1
    }
}

set_app_var search_path [concat [list .] [file dirname [lindex $DC_DB_FILES 0]]]
set_app_var target_library $DC_DB_FILES
set_app_var link_library [concat [list "*"] $DC_DB_FILES dw_foundation.sldb]
set_app_var synthetic_library dw_foundation.sldb
set_units -time ps -resistance kOhm -capacitance pF -voltage V -current mA

read_ddc $TOP_DDC
current_design $TOP_MODULE
link

proc write_area_report_for_collection {cells report_file} {
    if {[sizeof_collection $cells] == 0} {
        set fp [open $report_file w]
        puts $fp "No cells matched this collection."
        close $fp
        return
    }
    report_area $cells -hierarchy > $report_file
}

proc write_area_report_for_pattern {pattern report_file} {
    set cells [get_cells -hierarchical -quiet $pattern]
    write_area_report_for_collection $cells $report_file
}

report_area -hierarchy > ${REPORT_DIR}/dc_area.rpt

if {[info exists CORE_MODULE]} {
    set core_cells [get_cells -hierarchical -quiet -filter "ref_name == $CORE_MODULE"]
    write_area_report_for_collection $core_cells ${REPORT_DIR}/dc_area_core_instances.rpt
} else {
    set fp [open ${REPORT_DIR}/dc_area_core_instances.rpt w]
    puts $fp "CORE_MODULE is not available because $MODULE_NAMES_TCL was not found."
    close $fp
}

write_area_report_for_pattern "*cgra__*" ${REPORT_DIR}/dc_area_cgra_cells.rpt
write_area_report_for_pattern "*routers*" ${REPORT_DIR}/dc_area_inter_core_noc.rpt

exit
