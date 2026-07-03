proc sum_db_values {values} {
    if {[llength $values] == 0} {
        return 0.0
    }

    set total 0.0
    foreach value $values {
        if {$value eq ""} {
            continue
        }
        set total [expr {$total + double($value)}]
    }
    return $total
}

proc extract_power {} {
    redirect -variable power_text {report_power}
    set total_power ""
    foreach line [split $power_text "\n"] {
        if {[lindex $line 0] == "Total"} {
            set total_power [lindex $line end]
        }
    }
    if {$total_power eq ""} {
        set total_power 0.0
    }
    return $total_power
}

proc extract_cell_area {} {
    set macro_area [sum_db_values [dbget [dbget top.insts.cell.subClass block -p2].area]]
    set std_cell_area [sum_db_values [dbget [dbget top.insts.cell.subClass block -v -p2].area]]
    return [list $macro_area $std_cell_area]
}

proc extract_wire_length {} {
    return [sum_db_values [dbget top.nets.wires.length]]
}

proc extract_report {stage} {
    setAnalysisMode -reset
    setAnalysisMode -analysisType onChipVariation -cppr both

    if {$stage == "preCTS"} {
        timeDesign -preCTS -prefix ${stage}
    } elseif {$stage == "postCTS"} {
        timeDesign -postCTS -prefix ${stage}
    } elseif {$stage == "postRoute"} {
        timeDesign -postRoute -prefix ${stage}
    } elseif {$stage == "postRouteOpt"} {
        timeDesign -postRoute -prefix ${stage}
    } elseif {$stage == "postSynth"} {
        timeDesign -prePlace -prefix ${stage}
    }

    set power [extract_power]
    set area [extract_cell_area]
    set wire_length [extract_wire_length]
    set core_area [dbget top.fplan.coreBox_area]

    return "$stage,$core_area,[lindex $area 1],[lindex $area 0],$power,$wire_length"
}

proc sum_inst_area {inst_collection} {
    set total 0.0
    foreach area [dbget $inst_collection.cell.area] {
        if {$area eq ""} {
            continue
        }
        set total [expr {$total + double($area)}]
    }
    return $total
}

proc sum_hier_area_by_name_patterns {patterns} {
    set total 0.0
    foreach pattern $patterns {
        set insts [dbget top.insts.name $pattern -p]
        if {$insts ne ""} {
            set total [expr {$total + [sum_inst_area $insts]}]
        }
    }
    return $total
}

proc sum_hier_area_by_module_patterns {patterns} {
    set total 0.0
    foreach pattern $patterns {
        set insts [dbget [dbget top.insts.cell.name $pattern -p2]]
        if {$insts ne ""} {
            set total [expr {$total + [sum_inst_area $insts]}]
        }
    }
    return $total
}

proc write_area_row {fp component area total_area} {
    set dist 0.0
    if {$total_area > 0.0} {
        set dist [expr {$area / $total_area}]
    }
    puts $fp "$component,$area,$dist"
}

proc write_area_breakdown_csv {outfile} {
    set fp [open $outfile w]

    set total_area [sum_db_values [dbget top.insts.cell.area]]
    if {$total_area == 0.0} {
        puts $fp "component,area_um2,distribution"
        puts $fp "Total,0.0,0.0"
        close $fp
        return
    }

    set tile_area [sum_hier_area_by_name_patterns [list */tile__*/* *tile__*]]
    set core_controller_area [sum_hier_area_by_name_patterns [list */controller/*]]
    set loop_controller_area [sum_hier_area_by_name_patterns [list */loop_controller/*]]
    set inter_cgra_noc_area [sum_hier_area_by_name_patterns [list */inter_cgra_noc/* *inter_cgra_noc*]]

    set known_area [expr {$tile_area + $core_controller_area + \
        $loop_controller_area + $inter_cgra_noc_area}]
    set other_area [expr {$total_area - $known_area}]
    if {$other_area < 0.0} {
        set other_area 0.0
    }

    puts $fp "# Top-level physical area breakdown from Innovus leaf instances."
    puts $fp "component,area_um2,distribution"
    write_area_row $fp "Tiles (x64)" $tile_area $total_area
    write_area_row $fp "Core Controllers (x16)" $core_controller_area $total_area
    write_area_row $fp "Loop Controllers (x16)" $loop_controller_area $total_area
    write_area_row $fp "Inter-Core NoC" $inter_cgra_noc_area $total_area
    write_area_row $fp "Other" $other_area $total_area
    write_area_row $fp "Total" $total_area $total_area

    close $fp
}

proc write_tile_area_breakdown_csv {outfile} {
    set fp [open $outfile w]

    set tile_area [sum_hier_area_by_name_patterns [list */tile__*/* *tile__*]]
    if {$tile_area == 0.0} {
        puts $fp "component,area_um2,distribution"
        puts $fp "Total Tile,0.0,0.0"
        close $fp
        return
    }

    set flexible_fu_area [sum_hier_area_by_name_patterns [list */tile__*/element/* *tile__*element*]]
    set dcu_area [sum_hier_area_by_name_patterns [list */tile__*/element/fu__10/* *tile__*element*fu__10*]]
    set other_fu_area [expr {$flexible_fu_area - $dcu_area}]
    if {$other_fu_area < 0.0} {
        set other_fu_area 0.0
    }
    set config_mem_area [sum_hier_area_by_name_patterns [list */tile__*/ctrl_mem/* *tile__*ctrl_mem*]]
    set register_area [sum_hier_area_by_name_patterns [list */tile__*/register_cluster/* *tile__*register_cluster*]]
    set xbar_area [sum_hier_area_by_name_patterns [list */tile__*/fu_crossbar/* */tile__*/routing_crossbar/* *tile__*crossbar*]]

    set known_area [expr {$dcu_area + $other_fu_area + $config_mem_area + \
        $register_area + $xbar_area}]
    set other_area [expr {$tile_area - $known_area}]
    if {$other_area < 0.0} {
        set other_area 0.0
    }

    puts $fp "# Tile-internal physical area breakdown from Innovus leaf instances."
    puts $fp "component,area_um2,distribution"
    write_area_row $fp "DCUs" $dcu_area $tile_area
    write_area_row $fp "Other FUs" $other_fu_area $tile_area
    write_area_row $fp "Register File" $register_area $tile_area
    write_area_row $fp "Crossbar" $xbar_area $tile_area
    write_area_row $fp "Configuration Memories" $config_mem_area $tile_area
    write_area_row $fp "Other Tile Logic" $other_area $tile_area
    write_area_row $fp "Tiles (x64)" $tile_area $tile_area

    close $fp
}
