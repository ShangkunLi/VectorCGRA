# Recompute DC power from the existing mapped DDC with the same vectorless
# activity assumptions reported by Innovus: 0.2 transitions per clock cycle
# for primary inputs and sequential elements.

source scripts/flow_config.tcl

set REPORT_DIR "reports"
set DDC_FILE "results/${DESIGN}.ddc"
set ACTIVITY 0.2
set STATIC_PROBABILITY 0.5
set EXPECTED_CLOCK "sys_clk"

file mkdir $REPORT_DIR

if {![file exists $DDC_FILE]} {
    puts stderr "Mapped DDC not found: $DDC_FILE"
    puts stderr "Run ./scripts/run_dc.sh once before this power-only script."
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
set_host_options -max_cores $DC_CORES

read_ddc $DDC_FILE
current_design $TOP_MODULE
link

set base_clock [get_clocks -quiet $EXPECTED_CLOCK]
if {[sizeof_collection $base_clock] != 1} {
    puts stderr "Expected exactly one clock named '$EXPECTED_CLOCK' in $DDC_FILE."
    exit 1
}

set clock_period [get_attribute $base_clock period]
if {[expr {abs(double($clock_period) - double($CLK_PERIOD_PS))}] > 0.001} {
    puts stderr "Clock period mismatch: DDC=$clock_period ps, config=$CLK_PERIOD_PS ps."
    exit 1
}

# Innovus reports Primary Input Activity=0.2 and Sequential Element
# Activity=0.2. The clock itself is excluded because create_clock already
# models its two edges per cycle. Reset remains in the primary-input
# collection, matching Innovus's uniform default-primary-input assumption.
set clock_port [get_ports -quiet $CLK_PORT]
if {[sizeof_collection $clock_port] != 1} {
    puts stderr "Expected exactly one clock port named '$CLK_PORT'."
    exit 1
}

set activity_inputs [remove_from_collection [all_inputs] $clock_port]
set register_outputs [all_registers -output_pins]
set base_clock_name [get_object_name $base_clock]

set_switching_activity \
    -static_probability $STATIC_PROBABILITY \
    -toggle_rate $ACTIVITY \
    -base_clock $base_clock_name \
    $activity_inputs

set_switching_activity \
    -static_probability $STATIC_PROBABILITY \
    -toggle_rate $ACTIVITY \
    -base_clock $base_clock_name \
    $register_outputs

set metadata_file "${REPORT_DIR}/dc_power_20pct_metadata.txt"
set metadata [open $metadata_file w]
puts $metadata "design=$TOP_MODULE"
puts $metadata "ddc=$DDC_FILE"
puts $metadata "clock=$base_clock_name"
puts $metadata "clock_period_ps=$clock_period"
puts $metadata "toggle_rate_per_cycle=$ACTIVITY"
puts $metadata "static_probability=$STATIC_PROBABILITY"
puts $metadata "annotated_primary_inputs=[sizeof_collection $activity_inputs]"
puts $metadata "annotated_register_outputs=[sizeof_collection $register_outputs]"
puts $metadata "clock_input_excluded=1"
puts $metadata "reset_uses_primary_input_default=1"
close $metadata

report_power > ${REPORT_DIR}/dc_power_20pct_summary.rpt
report_power -hierarchy > ${REPORT_DIR}/dc_power_20pct_hierarchy.rpt

puts "Wrote ${REPORT_DIR}/dc_power_20pct_summary.rpt"
puts "Wrote ${REPORT_DIR}/dc_power_20pct_hierarchy.rpt"
puts "Wrote $metadata_file"

exit
