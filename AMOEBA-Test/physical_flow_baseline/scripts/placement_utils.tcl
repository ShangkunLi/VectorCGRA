# Shared Innovus placement helpers for the flat AMOEBA flow.

proc amoeba_place_pin_group {side layer pins} {
    if {[llength $pins] == 0} {
        return
    }

    puts [format "Placing %d top-level pins on %s using %s" \
              [llength $pins] $side $layer]
    set lower_side [string tolower $side]
    set attempts [list \
        [list editPin -pin $pins -side $side -layer $layer \
             -spreadType CENTER -spacing 2.0] \
        [list editPin -pin $pins -side $lower_side -layer $layer \
             -spreadType CENTER -spacing 2.0] \
        [list editPin -pin $pins -side $side -layer $layer \
             -spreadType SIDE -spacing 2.0] \
        [list editPin -pin $pins -side $lower_side -layer $layer \
             -spreadType SIDE -spacing 2.0] \
        [list editPin -pin $pins -side $side -layer $layer] \
        [list editPin -pin $pins -side $lower_side -layer $layer] \
    ]

    set last_error ""
    foreach cmd $attempts {
        if {![catch {uplevel #0 $cmd} result]} {
            return
        }
        set last_error $result
    }

    error "Failed to place pins on ${side}: ${last_error}"
}

proc amoeba_place_boundary_pins {} {
    if {[catch {set terms [dbGet top.terms.name]} msg]} {
        puts stderr "Could not query top-level terms for pin placement: $msg"
        return
    }

    set north_pins [list]
    set south_pins [list]
    set east_pins [list]
    set west_pins [list]
    set round_robin_side 0

    foreach pin [lsort -dictionary $terms] {
        if {$pin eq "" || $pin eq "0x0"} {
            continue
        }

        set lower_pin [string tolower $pin]
        if {$lower_pin eq "vdd" || $lower_pin eq "vss"} {
            continue
        }

        if {[regexp {(^|[_/])north([_/]|$)} $lower_pin]} {
            lappend north_pins $pin
        } elseif {[regexp {(^|[_/])south([_/]|$)} $lower_pin]} {
            lappend south_pins $pin
        } elseif {[regexp {(^|[_/])east([_/]|$)} $lower_pin]} {
            lappend east_pins $pin
        } elseif {[regexp {(^|[_/])west([_/]|$)} $lower_pin]} {
            lappend west_pins $pin
        } elseif {$lower_pin eq "clk" || $lower_pin eq "reset" ||
                  [string first "clk" $lower_pin] >= 0 ||
                  [string first "reset" $lower_pin] >= 0} {
            lappend south_pins $pin
        } else {
            switch $round_robin_side {
                0 { lappend west_pins $pin }
                1 { lappend north_pins $pin }
                2 { lappend east_pins $pin }
                default { lappend south_pins $pin }
            }
            set round_robin_side [expr {($round_robin_side + 1) % 4}]
        }
    }

    catch {setPinAssignMode -pinEditInBatch true}
    amoeba_place_pin_group TOP M3 $north_pins
    amoeba_place_pin_group BOTTOM M3 $south_pins
    amoeba_place_pin_group LEFT M2 $west_pins
    amoeba_place_pin_group RIGHT M2 $east_pins
    catch {setPinAssignMode -pinEditInBatch false}
}
