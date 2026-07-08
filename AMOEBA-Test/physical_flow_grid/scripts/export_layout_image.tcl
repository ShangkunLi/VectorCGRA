# Restore the routed AMOEBA grid design and export a paper-friendly layout.

source scripts/flow_config.tcl

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

amoeba_restore_saved_grid_design
source scripts/export_multicore_layout.tcl
exit
