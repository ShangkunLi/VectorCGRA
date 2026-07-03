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

