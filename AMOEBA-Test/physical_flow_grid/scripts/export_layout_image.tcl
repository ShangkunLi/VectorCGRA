# Restore the routed AMOEBA grid design and export a paper-friendly layout.

source scripts/flow_config.tcl

proc amoeba_open_innovus_gui {} {
    if {![info exists ::env(DISPLAY)] || [string trim $::env(DISPLAY)] eq ""} {
        error "DISPLAY is not set. Run this script from a VNC/X11 desktop session."
    }

    set errors [list]

    # The classic Innovus UI uses `win` to create or raise the main window.
    # Some newer Cadence Common UI releases expose `gui_show` instead.
    foreach gui_command {win gui_show} {
        if {[llength [info commands $gui_command]] == 0} {
            continue
        }
        if {![catch {uplevel #0 [list $gui_command]} gui_error]} {
            catch {update idletasks}
            catch {update}
            puts "Opened Innovus GUI with '$gui_command' on DISPLAY=$::env(DISPLAY)."
            return
        }
        lappend errors "$gui_command: $gui_error"
    }

    error "Could not open the Innovus GUI. Ensure Innovus was started without -nowin/-no_gui. Attempts: $errors"
}

proc amoeba_restore_saved_grid_design {} {
    global DESIGN TOP_MODULE

    if {![catch {set top_name [dbGet top.name]}] &&
        $top_name ne "" && $top_name ne "0x0"} {
        puts "Design is already loaded: $top_name"
        return
    }

    set candidates [list \
        "enc/${DESIGN}.enc.dat" \
        "enc/${DESIGN}.enc" \
        "enc/${DESIGN}_route.enc.dat" \
        "enc/${DESIGN}_route.enc" \
    ]

    foreach db_path $candidates {
        if {[file exists $db_path]} {
            puts "Restoring Innovus database: $db_path"
            restoreDesign $db_path $TOP_MODULE
            return
        }
    }

    error "Could not find a saved Innovus database. Tried: $candidates"
}

amoeba_open_innovus_gui
amoeba_restore_saved_grid_design

# Define the display/export procedures without dumping the startup-size canvas.
# Returning from this file lets the Innovus GUI finish opening and keeps it
# available for the user to maximize before exporting.
set ::amoeba_layout_auto_export 0
source scripts/export_multicore_layout.tcl
amoeba_layout_prepare_multicore_view

puts ""
puts "Interactive layout export is ready."
puts "1. Maximize the Innovus window (and enlarge the main layout canvas)."
puts "2. Run this command in the Innovus Console:"
puts ""
puts "     amoeba_export_multicore_layout"
puts ""
puts "3. Close Innovus after the GIF/PDF/PS files are written."
puts "The shell wrapper will then create the high-resolution PNG."
