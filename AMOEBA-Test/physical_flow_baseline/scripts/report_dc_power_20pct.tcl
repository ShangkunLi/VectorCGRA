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

# Use the timing library's native ns unit explicitly. CLK_PERIOD_PS is retained
# as the user-facing flow setting, then converted to ns before create_clock.
# This prevents a fresh dc_shell session from interpreting 2000 as 2000 ns.
set_units -time ns -resistance kOhm -capacitance pF -voltage V -current mA
set expected_clock_period_ns [expr {double($CLK_PERIOD_PS) / 1000.0}]

set clock_port [get_ports -quiet $CLK_PORT]
if {[sizeof_collection $clock_port] != 1} {
    puts stderr "Expected exactly one clock port named '$CLK_PORT'."
    exit 1
}

set existing_clock [get_clocks -quiet $EXPECTED_CLOCK]
if {[sizeof_collection $existing_clock] > 0} {
    remove_clock $existing_clock
}

create_clock $clock_port \
    -name $EXPECTED_CLOCK \
    -period $expected_clock_period_ns \
    -waveform [list 0 [expr {$expected_clock_period_ns / 2.0}]]

set base_clock [get_clocks -quiet $EXPECTED_CLOCK]
set clock_period_ns [get_attribute $base_clock period]
set clock_frequency_mhz [expr {1000.0 / double($clock_period_ns)}]

if {[expr {abs(double($clock_period_ns) - $expected_clock_period_ns)}] > 0.000001} {
    puts stderr "Clock recreation failed: actual=$clock_period_ns ns, expected=$expected_clock_period_ns ns."
    exit 1
}

puts "Power analysis clock: $clock_period_ns ns ($clock_frequency_mhz MHz)"

# Innovus reports Primary Input Activity=0.2 and Sequential Element
# Activity=0.2. The clock itself is excluded because create_clock already
# models its two edges per cycle. Reset remains in the primary-input
# collection, matching Innovus's uniform default-primary-input assumption.
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

# DC does not automatically propagate user annotations through all
# combinational logic before report_power.  Innovus performs this propagation
# explicitly during its vectorless power analysis, so do the same here.
propagate_switching_activity

set metadata_file "${REPORT_DIR}/dc_power_20pct_metadata.txt"
set metadata [open $metadata_file w]
puts $metadata "design=$TOP_MODULE"
puts $metadata "ddc=$DDC_FILE"
puts $metadata "clock=$base_clock_name"
puts $metadata "clock_period_ps=$CLK_PERIOD_PS"
puts $metadata "clock_period_ns=$clock_period_ns"
puts $metadata "clock_frequency_mhz=$clock_frequency_mhz"
puts $metadata "toggle_rate_per_cycle=$ACTIVITY"
puts $metadata "static_probability=$STATIC_PROBABILITY"
puts $metadata "annotated_primary_inputs=[sizeof_collection $activity_inputs]"
puts $metadata "annotated_register_outputs=[sizeof_collection $register_outputs]"
puts $metadata "switching_activity_propagated=1"
puts $metadata "clock_input_excluded=1"
puts $metadata "reset_uses_primary_input_default=1"
close $metadata

report_timing -delay_type max -max_paths 1 > ${REPORT_DIR}/dc_power_20pct_clock_check.rpt
report_power > ${REPORT_DIR}/dc_power_20pct_summary.rpt
report_power -hierarchy > ${REPORT_DIR}/dc_power_20pct_hierarchy.rpt

puts "Wrote ${REPORT_DIR}/dc_power_20pct_clock_check.rpt"
puts "Wrote ${REPORT_DIR}/dc_power_20pct_summary.rpt"
puts "Wrote ${REPORT_DIR}/dc_power_20pct_hierarchy.rpt"
puts "Wrote $metadata_file"

exit
