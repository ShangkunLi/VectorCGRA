# Shared Innovus placement helpers for the hierarchical AMOEBA flow.

proc amoeba_append_unique {var_name items} {
    upvar 1 $var_name result
    foreach item $items {
        if {$item ne "" && $item ne "0x0" &&
            [lsearch -exact $result $item] < 0} {
            lappend result $item
        }
    }
}

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

proc amoeba_core_id_from_inst_name {inst_name} {
    if {[regexp {cgra__([0-9]+)$} $inst_name -> core_id]} {
        return $core_id
    }
    if {[regexp {cgra_+([0-9]+)$} $inst_name -> core_id]} {
        return $core_id
    }
    return -1
}

proc amoeba_collect_core_macro_instances {core_module} {
    set candidates [list]

    foreach pattern [list "cgra__*" "cgra_*"] {
        if {![catch {set matches [dbGet top.insts.name $pattern]}]} {
            amoeba_append_unique candidates $matches
        }
    }

    if {[llength $candidates] == 0 && $core_module ne ""} {
        foreach inst [dbGet top.insts.name] {
            if {$inst eq "" || $inst eq "0x0"} {
                continue
            }
            if {[catch {set inst_ptr [dbGet -p top.insts.name $inst]}]} {
                continue
            }
            if {[catch {set cell_name [lindex [dbGet $inst_ptr.cell.name] 0]}]} {
                continue
            }
            if {$cell_name eq $core_module} {
                lappend candidates $inst
            }
        }
    }

    set ordered_pairs [list]
    foreach inst $candidates {
        set core_id [amoeba_core_id_from_inst_name $inst]
        if {$core_id >= 0} {
            lappend ordered_pairs [list $core_id $inst]
        }
    }

    set ordered_pairs [lsort -integer -index 0 $ordered_pairs]
    set ordered [list]
    foreach pair $ordered_pairs {
        lappend ordered [lindex $pair 1]
    }
    return $ordered
}

proc amoeba_get_core_area_box {} {
    foreach prefix [list "top.fplan" "top.fPlan"] {
        if {![catch {set llx [lindex [dbGet ${prefix}.coreBox_llx] 0]}] &&
            ![catch {set lly [lindex [dbGet ${prefix}.coreBox_lly] 0]}] &&
            ![catch {set urx [lindex [dbGet ${prefix}.coreBox_urx] 0]}] &&
            ![catch {set ury [lindex [dbGet ${prefix}.coreBox_ury] 0]}]} {
            return [list $llx $lly $urx $ury]
        }
    }

    if {![catch {set box [dbGet top.fplan.box]}] && [llength $box] >= 4} {
        return [lrange $box 0 3]
    }
    if {![catch {set box [dbGet top.fPlan.box]}] && [llength $box] >= 4} {
        return [lrange $box 0 3]
    }

    error "Could not query Innovus core area box for macro placement."
}

proc amoeba_create_box_constraint {mode group_name box} {
    lassign $box llx lly urx ury
    if {$mode eq "fence"} {
        set attempts [list \
            [list createFence $group_name $box] \
            [list createFence $group_name $llx $lly $urx $ury] \
        ]
    } else {
        set attempts [list \
            [list createRegion $group_name $box] \
            [list createRegion $group_name $llx $lly $urx $ury] \
        ]
    }

    set last_error ""
    foreach cmd $attempts {
        if {![catch {uplevel #0 $cmd} result]} {
            return
        }
        set last_error $result
    }

    error "Failed to create ${mode} ${group_name}: ${last_error}"
}

proc amoeba_get_inst_size {inst_name} {
    if {[catch {set inst_ptr [dbGet -p top.insts.name $inst_name]}]} {
        return [list 0.0 0.0]
    }
    if {[catch {set width [lindex [dbGet $inst_ptr.cell.size.x] 0]}]} {
        set width 0.0
    }
    if {[catch {set height [lindex [dbGet $inst_ptr.cell.size.y] 0]}]} {
        set height 0.0
    }
    return [list $width $height]
}

proc amoeba_place_instance_fixed {inst_name x y} {
    set attempts [list \
        [list placeInstance $inst_name $x $y R0 -fixed] \
        [list placeInstance $inst_name $x $y R0] \
    ]

    set placed 0
    set last_error ""
    foreach cmd $attempts {
        if {![catch {uplevel #0 $cmd} result]} {
            set placed 1
            break
        }
        set last_error $result
    }

    if {!$placed} {
        puts stderr "Warning: could not explicitly place $inst_name: $last_error"
        return
    }

    catch {setInstancePlacementStatus $inst_name fixed}
    catch {set_db [get_db insts $inst_name] .place_status fixed}
}

proc amoeba_apply_core_macro_grid {core_module} {
    set macro_insts [amoeba_collect_core_macro_instances $core_module]
    if {[llength $macro_insts] != 16} {
        error "Expected 16 CGRA core macro instances, found [llength $macro_insts]: $macro_insts"
    }

    lassign [amoeba_get_core_area_box] core_llx core_lly core_urx core_ury
    set rows 4
    set cols 4
    set core_w [expr {$core_urx - $core_llx}]
    set core_h [expr {$core_ury - $core_lly}]
    set cell_w [expr {$core_w / double($cols)}]
    set cell_h [expr {$core_h / double($rows)}]

    puts ""
    puts "Applying fixed 4x4 CGRA core macro placement."
    puts [format "Top core box: {%.3f %.3f %.3f %.3f}" \
              $core_llx $core_lly $core_urx $core_ury]
    puts [format "Grid cell: width=%.3f height=%.3f" $cell_w $cell_h]

    set report [open "reports/core_macro_grid_regions.rpt" "w"]
    puts $report "core_id,instance,group,llx,lly,urx,ury,place_x,place_y"

    foreach inst $macro_insts {
        set core_id [amoeba_core_id_from_inst_name $inst]
        set row [expr {$core_id / $cols}]
        set col [expr {$core_id % $cols}]

        set llx [expr {$core_llx + $col * $cell_w}]
        set lly [expr {$core_lly + $row * $cell_h}]
        set urx [expr {$llx + $cell_w}]
        set ury [expr {$lly + $cell_h}]
        set box [list $llx $lly $urx $ury]
        set group_name [format "cgra_core_%02d" $core_id]

        catch {deleteInstGroup $group_name}
        createInstGroup $group_name
        addInstToInstGroup $group_name $inst
        amoeba_create_box_constraint region $group_name $box

        lassign [amoeba_get_inst_size $inst] inst_w inst_h
        set place_x [expr {$llx + ($cell_w - $inst_w) / 2.0}]
        set place_y [expr {$lly + ($cell_h - $inst_h) / 2.0}]
        if {$place_x < $llx} { set place_x $llx }
        if {$place_y < $lly} { set place_y $lly }

        amoeba_place_instance_fixed $inst $place_x $place_y

        puts [format "%-12s core=%2d -> {%.3f %.3f %.3f %.3f}, placed at {%.3f %.3f}" \
                  $inst $core_id $llx $lly $urx $ury $place_x $place_y]
        puts $report [format "%d,%s,%s,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f" \
                          $core_id $inst $group_name \
                          $llx $lly $urx $ury $place_x $place_y]
    }

    close $report
    puts "Wrote reports/core_macro_grid_regions.rpt"
    puts ""
}
