# Technology setup for the hierarchical AMOEBA Innovus flow.
#
# This intentionally mirrors the reference CGRA Innovus package: build one
# explicit technology tuple and pass it through MMMC. Avoid loading multiple
# technology LEFs or mixing a QRC file from one routing stack with a LEF from
# another stack.

source scripts/flow_config.tcl

proc append_unique {var_name items} {
    upvar 1 $var_name result
    foreach item $items {
        if {$item ne "" && $item ne "0x0" &&
            [lsearch -exact $result $item] < 0} {
            lappend result $item
        }
    }
}

proc find_files_recursive {root pattern} {
    set files [list]
    if {![file exists $root]} {
        return $files
    }
    if {[catch {exec find $root -type f -iname $pattern} found]} {
        return $files
    }
    foreach path [split $found "\n"] {
        if {$path ne ""} {
            lappend files $path
        }
    }
    return $files
}

proc path_contains {path token} {
    return [expr {[string first [string tolower $token] \
                       [string tolower $path]] >= 0}]
}

proc is_liberty_timing_lib {path} {
    if {[string equal -nocase [file tail $path] "cds.lib"]} {
        return 0
    }
    if {[path_contains $path "/cdk/"] || [path_contains $path "/back_end/"]} {
        return 0
    }
    if {[catch {set fp [open $path r]}]} {
        return 0
    }
    set text [read $fp 1048576]
    close $fp
    return [regexp -nocase {(^|\n)[ \t]*library[ \t]*\(} $text]
}

proc is_technology_lef {path} {
    if {[catch {set fp [open $path r]}]} {
        return 0
    }
    set text [read $fp 1048576]
    close $fp

    if {[regexp -nocase {(^|\n)[ \t]*MANUFACTURINGGRID[ \t]+} $text]} {
        return 1
    }
    if {[regexp -nocase {(^|\n)[ \t]*LAYER[ \t]+M1([ \t]|\n)} $text] &&
        ![regexp -nocase {(^|\n)[ \t]*MACRO[ \t]+} $text]} {
        return 1
    }
    return 0
}

proc lef_routing_layers {path} {
    set layers [list]
    if {[catch {set fp [open $path r]}]} {
        return $layers
    }

    set in_layer 0
    set current_layer ""
    set layer_text ""
    while {[gets $fp line] >= 0} {
        if {!$in_layer &&
            [regexp -nocase {^[ \t]*LAYER[ \t]+([^ \t;]+)} $line -> layer]} {
            set in_layer 1
            set current_layer $layer
            set layer_text "$line\n"
            continue
        }

        if {$in_layer} {
            append layer_text "$line\n"
            if {[regexp -nocase {^[ \t]*END[ \t]+} $line]} {
                if {[regexp -nocase {TYPE[ \t]+ROUTING[ \t]*;} $layer_text]} {
                    lappend layers $current_layer
                }
                set in_layer 0
                set current_layer ""
                set layer_text ""
            }
        }
    }
    close $fp
    return $layers
}

proc choose_one_liberty_timing_lib {candidates} {
    global TSMC22_LIB_CORNER TSMC22_STD_CELL

    set timing_libs [list]
    foreach lib $candidates {
        if {[is_liberty_timing_lib $lib]} {
            lappend timing_libs $lib
        }
    }

    set best_path ""
    set best_score -1
    foreach lib $timing_libs {
        set score 0
        if {[path_contains $lib $TSMC22_STD_CELL]} { incr score 50 }
        if {[path_contains $lib $TSMC22_LIB_CORNER]} { incr score 40 }
        if {[path_contains $lib "/nldm/"]} { incr score 10 }
        if {[path_contains $lib "/front_end/"]} { incr score 5 }
        if {$score > $best_score ||
            ($score == $best_score &&
             ($best_path eq "" || [string compare $lib $best_path] < 0))} {
            set best_score $score
            set best_path $lib
        }
    }

    if {$best_path eq ""} {
        return [list]
    }
    return [list $best_path]
}

proc choose_one_technology_lef {candidates} {
    global TSMC22_TECH_LEF_TOKENS TSMC22_EXPECTED_ROUTING_LAYER_COUNT

    set best_path ""
    set best_score -1
    foreach lef $candidates {
        if {![is_technology_lef $lef]} {
            continue
        }

        set routing_layers [lef_routing_layers $lef]
        if {[llength $routing_layers] != $TSMC22_EXPECTED_ROUTING_LAYER_COUNT} {
            continue
        }

        set score 0
        foreach token $TSMC22_TECH_LEF_TOKENS {
            if {[path_contains $lef $token]} { incr score 50 }
        }
        if {[path_contains $lef "innovus"]} { incr score 10 }
        if {[path_contains $lef "cadence"]} { incr score 5 }
        if {[path_contains $lef "lefheader"]} { incr score 5 }
        if {[path_contains $lef "hv"] || [path_contains $lef "hvh"]} {
            incr score 2
        }

        if {$score > $best_score ||
            ($score == $best_score &&
             ($best_path eq "" || [string compare $lef $best_path] < 0))} {
            set best_score $score
            set best_path $lef
        }
    }

    if {$best_path eq ""} {
        return [list]
    }
    return [list $best_path]
}

proc choose_one_stdcell_lef {candidates} {
    global TSMC22_STD_CELL

    set best_path ""
    set best_score -1
    foreach lef $candidates {
        if {[is_technology_lef $lef]} {
            continue
        }
        if {![path_contains $lef $TSMC22_STD_CELL]} {
            continue
        }

        set score 0
        if {[path_contains $lef "/back_end/lef/"]} { incr score 30 }
        if {[path_contains $lef "/lef/"]} { incr score 10 }
        if {[string equal -nocase [file tail $lef] "${TSMC22_STD_CELL}.lef"]} {
            incr score 50
        }

        if {$score > $best_score ||
            ($score == $best_score &&
             ($best_path eq "" || [string compare $lef $best_path] < 0))} {
            set best_score $score
            set best_path $lef
        }
    }

    if {$best_path eq ""} {
        return [list]
    }
    return [list $best_path]
}

proc discover_innovus_lib_files {} {
    global TSMC22_NLDM_DIR TECH_ROOT TSMC22_STD_CELL

    set roots [list $TSMC22_NLDM_DIR "${TECH_ROOT}/SC/${TSMC22_STD_CELL}"]
    set candidates [list]
    foreach root $roots {
        append_unique candidates [find_files_recursive $root "*.lib"]
    }
    return [choose_one_liberty_timing_lib $candidates]
}

proc discover_innovus_tech_lefs {} {
    global TECH_ROOT

    set roots [list \
        "${TECH_ROOT}/APR_Tech/Cadence" \
        "${TECH_ROOT}/Back_End" \
        "${TECH_ROOT}/SC" \
        "${TECH_ROOT}/PDK" \
    ]
    set candidates [list]
    foreach root $roots {
        append_unique candidates [find_files_recursive $root "*.tlef"]
        append_unique candidates [find_files_recursive $root "*.lef"]
    }
    return [choose_one_technology_lef $candidates]
}

proc discover_innovus_cell_lefs {} {
    global TECH_ROOT TSMC22_STD_CELL

    set roots [list "${TECH_ROOT}/SC/${TSMC22_STD_CELL}"]
    set candidates [list]
    foreach root $roots {
        append_unique candidates [find_files_recursive $root "*.lef"]
    }
    return [choose_one_stdcell_lef $candidates]
}

if {[llength $INNOVUS_LIB_FILES] > 0} {
    set lib_files $INNOVUS_LIB_FILES
} else {
    set lib_files [discover_innovus_lib_files]
}

if {[llength $INNOVUS_LEF_FILES] > 0} {
    set lef_files $INNOVUS_LEF_FILES
} else {
    if {[llength $INNOVUS_TECH_LEF_FILES] > 0} {
        set tech_lefs $INNOVUS_TECH_LEF_FILES
    } else {
        set tech_lefs [discover_innovus_tech_lefs]
    }

    if {[llength $INNOVUS_CELL_LEF_FILES] > 0} {
        set cell_lefs $INNOVUS_CELL_LEF_FILES
    } else {
        set cell_lefs [discover_innovus_cell_lefs]
    }
    set lef_files [concat $tech_lefs $cell_lefs]
}

set qrc_file $INNOVUS_QRC_FILE

if {[llength $lib_files] != 1} {
    puts stderr "Expected exactly one Innovus Liberty timing library, got:"
    foreach lib $lib_files { puts stderr "  $lib" }
    exit 1
}
foreach lib $lib_files {
    if {![is_liberty_timing_lib $lib]} {
        puts stderr "Not a Liberty timing library: $lib"
        exit 1
    }
}

if {[llength $lef_files] < 2} {
    puts stderr "Expected a technology LEF followed by at least one standard-cell LEF."
    puts stderr "Resolved LEFs: $lef_files"
    exit 1
}
if {![is_technology_lef [lindex $lef_files 0]]} {
    puts stderr "The first Innovus LEF is not a technology LEF:"
    puts stderr "  [lindex $lef_files 0]"
    exit 1
}

set tech_routing_layers [lef_routing_layers [lindex $lef_files 0]]
if {[llength $tech_routing_layers] != $TSMC22_EXPECTED_ROUTING_LAYER_COUNT} {
    puts stderr "Technology LEF/QRC stack mismatch before init_design."
    puts stderr "  Technology LEF: [lindex $lef_files 0]"
    puts stderr "  Routing layers: $tech_routing_layers"
    puts stderr "  Expected routing layer count: $TSMC22_EXPECTED_ROUTING_LAYER_COUNT"
    puts stderr "  QRC file: $qrc_file"
    puts stderr "Use a tech LEF from the same 1P8M/5x2z stack as the QRC file."
    exit 1
}

if {$qrc_file eq "" || ![file exists $qrc_file]} {
    puts stderr "Innovus QRC file does not exist: $qrc_file"
    exit 1
}

set init_lib_search_path [list]
foreach lib $lib_files { lappend init_lib_search_path [file dirname $lib] }
foreach lef $lef_files { lappend init_lib_search_path [file dirname $lef] }

set libworst $lib_files
set libbest  $lib_files
set lefs     $lef_files
set qrc_max  $qrc_file
set qrc_min  $qrc_file

puts "Innovus timing libraries:"
foreach lib $lib_files { puts "  $lib" }
puts "Innovus LEF load order:"
foreach lef $lef_files { puts "  $lef" }
puts "Technology LEF routing layers: $tech_routing_layers"
puts "Innovus QRC file:"
puts "  $qrc_file"

catch {setDesignMode -process 22}
