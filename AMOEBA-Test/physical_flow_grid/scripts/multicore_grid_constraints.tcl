# Reference-style 4x4 placement constraints for the AMOEBA multi-CGRA top.
#
# The generated top has 16 logical CGRA instances named cgra__0 ... cgra__15.
# DC is configured to preserve hierarchy, but Innovus names can still appear as
# cgra__0/foo or cgra__0_foo. This script indexes all instances once, assigns
# them to core buckets, then creates one region/fence per core.

proc amoeba_grid_lappend_unique {var_name value} {
    upvar 1 $var_name values
    if {$value eq "" || $value eq "0x0"} {
        return
    }
    if {[lsearch -exact $values $value] < 0} {
        lappend values $value
    }
}

proc amoeba_grid_dbget_names {{pattern ""}} {
    set names {}
    if {$pattern eq ""} {
        if {[catch {set raw_names [dbGet top.insts.name]}]} {
            return $names
        }
    } else {
        if {[catch {set raw_names [dbGet top.insts.name $pattern]}]} {
            return $names
        }
    }

    foreach name $raw_names {
        if {$name ne "" && $name ne "0x0"} {
            lappend names $name
        }
    }
    return $names
}

proc amoeba_grid_core_id_from_inst_name {inst_name max_cores include_mesh_routers} {
    set regexps [list \
        {(^|/)cgra__([0-9]+)(/|_|$)} \
        {(^|/)cgra_([0-9]+)(/|_|$)} \
        {(^|_)cgra__([0-9]+)_} \
        {(^|_)cgra_([0-9]+)_} \
    ]

    foreach re $regexps {
        if {[regexp -- $re $inst_name match prefix core_id suffix]} {
            if {$core_id >= 0 && $core_id < $max_cores} {
                return $core_id
            }
        }
    }

    if {$include_mesh_routers} {
        if {[regexp -- {(^|/)mesh(/|_)routers__([0-9]+)(/|_|$)} \
                 $inst_name match prefix sep core_id suffix] ||
            [regexp -- {(^|_)mesh__routers__([0-9]+)_} \
                 $inst_name match prefix core_id] ||
            [regexp -- {(^|/)mesh_routers__([0-9]+)(/|_|$)} \
                 $inst_name match prefix core_id suffix]} {
            if {$core_id >= 0 && $core_id < $max_cores} {
                return $core_id
            }
        }
    }

    return -1
}

proc amoeba_grid_fallback_collect_core_instances {core_id include_mesh_routers} {
    set patterns [list \
        "*cgra__${core_id}/*" \
        "*cgra__${core_id}_*" \
        "*cgra_${core_id}/*" \
        "*cgra_${core_id}_*" \
        "cgra__${core_id}" \
        "cgra_${core_id}" \
    ]
    if {$include_mesh_routers} {
        lappend patterns "*mesh/routers__${core_id}/*"
        lappend patterns "*mesh/routers__${core_id}_*"
        lappend patterns "*mesh__routers__${core_id}_*"
        lappend patterns "*mesh_routers__${core_id}_*"
    }

    set inst_names {}
    foreach pattern $patterns {
        foreach inst_name [amoeba_grid_dbget_names $pattern] {
            amoeba_grid_lappend_unique inst_names $inst_name
        }
    }
    return [lsort -dictionary $inst_names]
}

proc amoeba_grid_collect_instances_by_core {rows cols include_mesh_routers} {
    set max_cores [expr {$rows * $cols}]
    array set buckets {}
    for {set core_id 0} {$core_id < $max_cores} {incr core_id} {
        set buckets($core_id) {}
    }

    puts "Indexing Innovus instances for AMOEBA core ownership..."
    foreach inst_name [amoeba_grid_dbget_names] {
        set core_id [amoeba_grid_core_id_from_inst_name \
            $inst_name $max_cores $include_mesh_routers]
        if {$core_id >= 0} {
            amoeba_grid_lappend_unique buckets($core_id) $inst_name
        }
    }

    for {set core_id 0} {$core_id < $max_cores} {incr core_id} {
        if {[llength $buckets($core_id)] == 0} {
            set buckets($core_id) [amoeba_grid_fallback_collect_core_instances \
                $core_id $include_mesh_routers]
        } else {
            set buckets($core_id) [lsort -dictionary $buckets($core_id)]
        }
    }

    return [array get buckets]
}

proc amoeba_grid_create_box_constraint {mode group_name box} {
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

proc amoeba_grid_delete_place_blockage_if_exists {name} {
    catch {deletePlaceBlockage -name $name}
    catch {deletePlaceBlockage $name}
}

proc amoeba_grid_delete_route_blockage_if_exists {name} {
    catch {deleteRouteBlk -name $name}
    catch {deleteRouteBlk $name}
}

proc amoeba_grid_create_boundary_place_blockages {core_id box width} {
    lassign $box llx lly urx ury
    if {$width <= 0.0} {
        return
    }

    set x1 [expr {$llx + $width}]
    set y1 [expr {$lly + $width}]
    set x2 [expr {$urx - $width}]
    set y2 [expr {$ury - $width}]

    if {$x1 >= $x2 || $y1 >= $y2} {
        puts "core_${core_id}: boundary placement blockage is too wide, skipping"
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
        amoeba_grid_delete_place_blockage_if_exists $name
        createPlaceBlockage -type soft -box $blk_box -name $name
    }
}

proc amoeba_grid_create_channel_place_blockages {rows cols core_llx core_lly core_urx core_ury cell_w cell_h channel} {
    if {$channel <= 0.0} {
        return
    }

    for {set col 0} {$col < ($cols - 1)} {incr col} {
        set x0 [expr {$core_llx + ($col + 1) * $cell_w + $col * $channel}]
        set x1 [expr {$x0 + $channel}]
        set name [format "amoeba_core_grid_v_%d" $col]
        amoeba_grid_delete_place_blockage_if_exists $name
        createPlaceBlockage -type soft -box [list $x0 $core_lly $x1 $core_ury] -name $name
    }

    for {set row 0} {$row < ($rows - 1)} {incr row} {
        set y0 [expr {$core_lly + ($row + 1) * $cell_h + $row * $channel}]
        set y1 [expr {$y0 + $channel}]
        set name [format "amoeba_core_grid_h_%d" $row]
        amoeba_grid_delete_place_blockage_if_exists $name
        createPlaceBlockage -type soft -box [list $core_llx $y0 $core_urx $y1] -name $name
    }
}

proc amoeba_grid_create_boundary_route_blockages {core_id box width layer_names} {
    lassign $box llx lly urx ury
    if {$width <= 0.0 || [llength $layer_names] == 0} {
        return
    }

    set x1 [expr {$llx + $width}]
    set y1 [expr {$lly + $width}]
    set x2 [expr {$urx - $width}]
    set y2 [expr {$ury - $width}]

    if {$x1 >= $x2 || $y1 >= $y2} {
        puts "core_${core_id}: boundary route blockage is too wide, skipping"
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
        amoeba_grid_delete_route_blockage_if_exists $name
        createRouteBlk -box $blk_box -layer $layer_names -name $name
    }
}

proc amoeba_grid_add_group_instances {group_name inst_names} {
    catch {deleteInstGroup $group_name}
    createInstGroup $group_name

    if {![catch {addInstToInstGroup $group_name $inst_names}]} {
        return
    }

    foreach inst_name $inst_names {
        addInstToInstGroup $group_name $inst_name
    }
}

proc amoeba_apply_multicore_grid_constraints {} {
    global CORE_GRID_ROWS CORE_GRID_COLS CORE_GRID_MODE CORE_GRID_CHANNEL
    global CORE_GRID_BOUNDARY_PLACE_BLKG CORE_GRID_BOUNDARY_PLACE_BLKG_WIDTH
    global CORE_GRID_BOUNDARY_ROUTE_BLKG CORE_GRID_BOUNDARY_ROUTE_BLKG_WIDTH
    global CORE_GRID_BOUNDARY_ROUTE_LAYERS CORE_GRID_REPORT
    global CORE_GRID_REQUIRE_ALL_CORES CORE_GRID_INCLUDE_MESH_ROUTERS

    set mode [string tolower $CORE_GRID_MODE]
    if {$mode ni {"region" "fence"}} {
        error "CORE_GRID_MODE must be either \"region\" or \"fence\""
    }

    set rows $CORE_GRID_ROWS
    set cols $CORE_GRID_COLS
    set channel $CORE_GRID_CHANNEL
    set max_cores [expr {$rows * $cols}]
    set require_all [expr {[info exists CORE_GRID_REQUIRE_ALL_CORES] && $CORE_GRID_REQUIRE_ALL_CORES}]
    set include_mesh [expr {[info exists CORE_GRID_INCLUDE_MESH_ROUTERS] && $CORE_GRID_INCLUDE_MESH_ROUTERS}]

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

    array set core_insts [amoeba_grid_collect_instances_by_core $rows $cols $include_mesh]

    puts ""
    puts [format "Applying %s constraints for logical %dx%d AMOEBA multi-core grid" $mode $rows $cols]
    puts [format "Core box : {%.3f %.3f %.3f %.3f}" $core_llx $core_lly $core_urx $core_ury]
    puts [format "Grid cell: width=%.3f height=%.3f channel=%.3f" $cell_w $cell_h $channel]
    puts [format "Boundary placement blockage: %s width=%.3f" $add_place_blk $place_blk_w]
    puts [format "Boundary route blockage    : %s width=%.3f layers=%s" $add_route_blk $route_blk_w $route_blk_layers]
    puts "Logical numbering:"
    puts "12 13 14 15"
    puts " 8  9 10 11"
    puts " 4  5  6  7"
    puts " 0  1  2  3"
    puts ""

    if {![info exists CORE_GRID_REPORT] || $CORE_GRID_REPORT eq ""} {
        set CORE_GRID_REPORT "reports/core_grid_regions.rpt"
    }
    file mkdir [file dirname $CORE_GRID_REPORT]
    set rpt [open $CORE_GRID_REPORT "w"]
    puts $rpt "core_id,group_name,mode,inst_count,llx,lly,urx,ury"

    if {$add_place_blk} {
        amoeba_grid_create_channel_place_blockages \
            $rows $cols $core_llx $core_lly $core_urx $core_ury $cell_w $cell_h $channel
    }

    set missing_cores {}
    for {set row 0} {$row < $rows} {incr row} {
        for {set col 0} {$col < $cols} {incr col} {
            set core_id [expr {$row * $cols + $col}]
            set group_name [format "core_%d" $core_id]
            set inst_names $core_insts($core_id)
            set inst_count [llength $inst_names]

            set llx [expr {$core_llx + $col * ($cell_w + $channel)}]
            set lly [expr {$core_lly + $row * ($cell_h + $channel)}]
            set urx [expr {$llx + $cell_w}]
            set ury [expr {$lly + $cell_h}]
            set box [list $llx $lly $urx $ury]

            if {$inst_count == 0} {
                lappend missing_cores $core_id
                puts "core_${core_id}: no instances found"
                puts $rpt [format "%d,%s,%s,%d,%.3f,%.3f,%.3f,%.3f" \
                    $core_id $group_name $mode 0 $llx $lly $urx $ury]
                continue
            }

            amoeba_grid_add_group_instances $group_name $inst_names
            amoeba_grid_create_box_constraint $mode $group_name $box

            if {$add_place_blk} {
                amoeba_grid_create_boundary_place_blockages $core_id $box $place_blk_w
            }
            if {$add_route_blk} {
                amoeba_grid_create_boundary_route_blockages $core_id $box $route_blk_w $route_blk_layers
            }

            puts [format "%-7s : %6d insts -> {%.3f %.3f %.3f %.3f}" \
                $group_name $inst_count $llx $lly $urx $ury]
            puts $rpt [format "%d,%s,%s,%d,%.3f,%.3f,%.3f,%.3f" \
                $core_id $group_name $mode $inst_count $llx $lly $urx $ury]
        }
    }

    close $rpt
    if {$CORE_GRID_REPORT ne "core_grid_regions.rpt"} {
        catch {file copy -force $CORE_GRID_REPORT "core_grid_regions.rpt"}
    }

    if {[llength $missing_cores] > 0 && $require_all} {
        error "Missing instances for AMOEBA cores: $missing_cores. Check netlist hierarchy names."
    }

    puts ""
    puts "Wrote $CORE_GRID_REPORT"
}

if {[info exists CORE_GRID_ENABLE] && $CORE_GRID_ENABLE} {
    amoeba_apply_multicore_grid_constraints
}
