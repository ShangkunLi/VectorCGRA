# Create logical 4x4 CGRA-core placement constraints for the flattened AMOEBA
# netlist. Each core contains a 2x2 tile array, so these constraints group by
# top-level cgra__N hierarchy fragments, not by local tile__N names.

proc amoeba_collect_core_instances {core_id} {
    set patterns [list \
        "*cgra__${core_id}*" \
        "*cgra_${core_id}*" \
    ]

    set inst_names {}
    foreach pattern $patterns {
        set raw_names [dbGet top.insts.name $pattern]
        foreach inst_name $raw_names {
            if {$inst_name ne "" && $inst_name ne "0x0" &&
                [lsearch -exact $inst_names $inst_name] < 0} {
                lappend inst_names $inst_name
            }
        }
    }
    return [lsort -unique $inst_names]
}

proc amoeba_create_core_box_constraint {mode group_name box} {
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

    error "Failed to create ${mode} for ${group_name}: ${last_error}"
}

proc amoeba_delete_place_blockage_if_exists {name} {
    catch {deletePlaceBlockage $name}
}

proc amoeba_delete_route_blockage_if_exists {name} {
    catch {deleteRouteBlk $name}
}

proc amoeba_create_core_boundary_place_blockages {core_id box width} {
    lassign $box llx lly urx ury
    if {$width <= 0.0} {
        return
    }

    set x1 [expr {$llx + $width}]
    set y1 [expr {$lly + $width}]
    set x2 [expr {$urx - $width}]
    set y2 [expr {$ury - $width}]

    if {$x1 >= $x2 || $y1 >= $y2} {
        puts "core_${core_id}: boundary placement blockage width is too large, skipping"
        return
    }

    set core_tag [format "%02d" $core_id]
    foreach {suffix blk_box} [list \
        l [list $llx $lly $x1 $ury] \
        r [list $x2 $lly $urx $ury] \
        b [list $x1 $lly $x2 $y1] \
        t [list $x1 $y2 $x2 $ury] \
    ] {
        set name [format "amoeba_core_box_%s_%s" $core_tag $suffix]
        amoeba_delete_place_blockage_if_exists $name
        createPlaceBlockage -type soft -box $blk_box -name $name
    }
}

proc amoeba_create_global_grid_channel_blockages {rows cols core_llx core_lly core_urx core_ury cell_w cell_h channel} {
    if {$channel <= 0.0} {
        return
    }

    for {set col 0} {$col < ($cols - 1)} {incr col} {
        set x0 [expr {$core_llx + ($col + 1) * $cell_w + $col * $channel}]
        set x1 [expr {$x0 + $channel}]
        set name [format "amoeba_core_grid_v_%d" $col]
        amoeba_delete_place_blockage_if_exists $name
        createPlaceBlockage -type soft -box [list $x0 $core_lly $x1 $core_ury] -name $name
    }

    for {set row 0} {$row < ($rows - 1)} {incr row} {
        set y0 [expr {$core_lly + ($row + 1) * $cell_h + $row * $channel}]
        set y1 [expr {$y0 + $channel}]
        set name [format "amoeba_core_grid_h_%d" $row]
        amoeba_delete_place_blockage_if_exists $name
        createPlaceBlockage -type soft -box [list $core_llx $y0 $core_urx $y1] -name $name
    }
}

proc amoeba_create_core_boundary_route_blockages {core_id box width layer_names} {
    lassign $box llx lly urx ury
    if {$width <= 0.0 || [llength $layer_names] == 0} {
        return
    }

    set x1 [expr {$llx + $width}]
    set y1 [expr {$lly + $width}]
    set x2 [expr {$urx - $width}]
    set y2 [expr {$ury - $width}]

    if {$x1 >= $x2 || $y1 >= $y2} {
        puts "core_${core_id}: boundary route blockage width is too large, skipping"
        return
    }

    set core_tag [format "%02d" $core_id]
    foreach {suffix blk_box} [list \
        l [list $llx $lly $x1 $ury] \
        r [list $x2 $lly $urx $ury] \
        b [list $x1 $lly $x2 $y1] \
        t [list $x1 $y2 $x2 $ury] \
    ] {
        set name [format "amoeba_core_route_%s_%s" $core_tag $suffix]
        amoeba_delete_route_blockage_if_exists $name
        createRouteBlk -box $blk_box -layer $layer_names -name $name
    }
}

proc amoeba_apply_core_grid_constraints {} {
    global CORE_GRID_ROWS CORE_GRID_COLS CORE_GRID_MODE CORE_GRID_CHANNEL
    global CORE_GRID_BOUNDARY_PLACE_BLKG CORE_GRID_BOUNDARY_PLACE_BLKG_WIDTH
    global CORE_GRID_BOUNDARY_ROUTE_BLKG CORE_GRID_BOUNDARY_ROUTE_BLKG_WIDTH
    global CORE_GRID_BOUNDARY_ROUTE_LAYERS

    set mode [string tolower $CORE_GRID_MODE]
    if {$mode ni {"region" "fence"}} {
        error "CORE_GRID_MODE must be either \"region\" or \"fence\""
    }

    set rows $CORE_GRID_ROWS
    set cols $CORE_GRID_COLS
    set channel $CORE_GRID_CHANNEL

    set add_place_blk [expr {[info exists CORE_GRID_BOUNDARY_PLACE_BLKG] && $CORE_GRID_BOUNDARY_PLACE_BLKG}]
    set place_blk_w 0.0
    if {$add_place_blk && [info exists CORE_GRID_BOUNDARY_PLACE_BLKG_WIDTH]} {
        set place_blk_w $CORE_GRID_BOUNDARY_PLACE_BLKG_WIDTH
    }

    set add_route_blk [expr {[info exists CORE_GRID_BOUNDARY_ROUTE_BLKG] && $CORE_GRID_BOUNDARY_ROUTE_BLKG}]
    set route_blk_w 0.0
    if {$add_route_blk && [info exists CORE_GRID_BOUNDARY_ROUTE_BLKG_WIDTH]} {
        set route_blk_w $CORE_GRID_BOUNDARY_ROUTE_BLKG_WIDTH
    }
    set route_blk_layers {}
    if {$add_route_blk && [info exists CORE_GRID_BOUNDARY_ROUTE_LAYERS]} {
        set route_blk_layers $CORE_GRID_BOUNDARY_ROUTE_LAYERS
    }

    set core_llx [dbGet top.fplan.coreBox_llx]
    set core_lly [dbGet top.fplan.coreBox_lly]
    set core_urx [dbGet top.fplan.coreBox_urx]
    set core_ury [dbGet top.fplan.coreBox_ury]
    set core_w [expr {$core_urx - $core_llx}]
    set core_h [expr {$core_ury - $core_lly}]

    set cell_w [expr {($core_w - ($cols - 1) * $channel) / double($cols)}]
    set cell_h [expr {($core_h - ($rows - 1) * $channel) / double($rows)}]
    if {$cell_w <= 0.0 || $cell_h <= 0.0} {
        error "Core grid geometry is invalid. Check CORE_GRID_CHANNEL / rows / cols."
    }

    puts ""
    puts [format "Applying %s constraints for logical %dx%d AMOEBA CGRA-core grid" $mode $rows $cols]
    puts [format "Core box : {%.3f %.3f %.3f %.3f}" $core_llx $core_lly $core_urx $core_ury]
    puts [format "Grid cell: width=%.3f height=%.3f channel=%.3f" $cell_w $cell_h $channel]

    set rpt [open "core_grid_regions.rpt" "w"]
    puts $rpt "core_id,group_name,mode,inst_count,llx,lly,urx,ury"

    if {$add_place_blk} {
        amoeba_create_global_grid_channel_blockages \
            $rows $cols $core_llx $core_lly $core_urx $core_ury $cell_w $cell_h $channel
    }

    for {set row 0} {$row < $rows} {incr row} {
        for {set col 0} {$col < $cols} {incr col} {
            set core_id [expr {$row * $cols + $col}]
            set group_name [format "core_%d" $core_id]
            set inst_names [amoeba_collect_core_instances $core_id]
            set inst_count [llength $inst_names]

            if {$inst_count == 0} {
                puts "core_${core_id}: no instances found, skipping"
                continue
            }

            set llx [expr {$core_llx + $col * ($cell_w + $channel)}]
            set lly [expr {$core_lly + $row * ($cell_h + $channel)}]
            set urx [expr {$llx + $cell_w}]
            set ury [expr {$lly + $cell_h}]
            set box [list $llx $lly $urx $ury]

            createInstGroup $group_name
            foreach inst_name $inst_names {
                addInstToInstGroup $group_name $inst_name
            }

            amoeba_create_core_box_constraint $mode $group_name $box

            if {$add_place_blk} {
                amoeba_create_core_boundary_place_blockages $core_id $box $place_blk_w
            }
            if {$add_route_blk} {
                amoeba_create_core_boundary_route_blockages $core_id $box $route_blk_w $route_blk_layers
            }

            puts [format "%-7s : %6d insts -> {%.3f %.3f %.3f %.3f}" \
                $group_name $inst_count $llx $lly $urx $ury]
            puts $rpt [format "%d,%s,%s,%d,%.3f,%.3f,%.3f,%.3f" \
                $core_id $group_name $mode $inst_count $llx $lly $urx $ury]
        }
    }

    close $rpt
    puts "Wrote core_grid_regions.rpt"
}

if {[info exists CORE_GRID_ENABLE] && $CORE_GRID_ENABLE} {
    amoeba_apply_core_grid_constraints
}
