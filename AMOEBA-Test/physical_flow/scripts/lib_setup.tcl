# Technology setup for Innovus.

source scripts/flow_config.tcl

set lib_files {}
set lef_files {}
set qrc_file  ""

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

proc find_lef_like_files_recursive {root} {
    set files [list]
    foreach pattern [list "*.lef" "*.tlef" "*techlef*" "*tech.lef" "*technology*.lef"] {
        append_unique files [find_files_recursive $root $pattern]
    }
    return $files
}

proc append_unique {var_name items} {
    upvar 1 $var_name result
    foreach item $items {
        if {$item ne "" && [lsearch -exact $result $item] < 0} {
            lappend result $item
        }
    }
}

proc path_contains {path token} {
    return [expr {[string first [string tolower $token] [string tolower $path]] >= 0}]
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

proc choose_one_liberty_timing_lib {lib_files} {
    global TSMC22_LIB_CORNER TSMC22_STD_CELL

    set timing_libs [list]
    foreach lib $lib_files {
        if {[is_liberty_timing_lib $lib]} {
            lappend timing_libs $lib
        }
    }
    if {[llength $timing_libs] == 0} {
        return [list]
    }

    if {[info exists TSMC22_LIB_CORNER] && $TSMC22_LIB_CORNER ne ""} {
        set corner_matches [list]
        foreach lib $timing_libs {
            if {[path_contains $lib $TSMC22_LIB_CORNER]} {
                lappend corner_matches $lib
            }
        }
        if {[llength $corner_matches] > 0} {
            set timing_libs $corner_matches
        }
    }

    set best_path ""
    set best_score -1
    foreach lib $timing_libs {
        set score 0
        if {[info exists TSMC22_STD_CELL] &&
            [path_contains $lib $TSMC22_STD_CELL]} {
            incr score 50
        }
        if {[info exists TSMC22_LIB_CORNER] &&
            $TSMC22_LIB_CORNER ne "" &&
            [path_contains $lib $TSMC22_LIB_CORNER]} {
            incr score 40
        }
        if {[path_contains $lib "/nldm/"]} {
            incr score 10
        }
        if {[path_contains $lib "/front_end/"]} {
            incr score 5
        }
        if {$score > $best_score || ($score == $best_score &&
                                     ($best_path eq "" ||
                                      [string compare $lib $best_path] < 0))} {
            set best_score $score
            set best_path $lib
        }
    }
    return [list $best_path]
}

proc is_technology_lef {path} {
    if {[catch {set fp [open $path r]}]} {
        return 0
    }
    set text [read $fp 1048576]
    close $fp

    # Technology LEFs define process layers before standard-cell macros use
    # those layers in pin shapes. If a macro LEF is loaded first, Innovus fails
    # with errors like "layer M1 ... is not found in the database".
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

proc filter_technology_lefs {lef_files} {
    set tech_lefs [list]
    foreach lef $lef_files {
        if {[is_technology_lef $lef]} {
            lappend tech_lefs $lef
        }
    }
    return [lsort $tech_lefs]
}

proc choose_one_technology_lef {tech_lefs} {
    global TSMC22_TECH_LEF_TOKENS TSMC22_EXPECTED_ROUTING_LAYER_COUNT

    if {[llength $tech_lefs] == 0} {
        return [list]
    }

    # A routing-stack LEF/header defines routing layers and vias. Loading more
    # than one such file causes duplicate VIA definitions, and layers defined
    # after the first technology LEF are ignored by Innovus.
    set best_path ""
    set best_score -1
    foreach lef $tech_lefs {
        set routing_layers [lef_routing_layers $lef]
        if {[info exists TSMC22_EXPECTED_ROUTING_LAYER_COUNT] &&
            $TSMC22_EXPECTED_ROUTING_LAYER_COUNT > 0 &&
            [llength $routing_layers] != $TSMC22_EXPECTED_ROUTING_LAYER_COUNT} {
            continue
        }

        set score 0
        if {[info exists TSMC22_TECH_LEF_TOKENS]} {
            foreach token $TSMC22_TECH_LEF_TOKENS {
                if {[path_contains $lef $token]} {
                    incr score 50
                }
            }
        }
        if {[path_contains $lef "innovus"]} { incr score 10 }
        if {[path_contains $lef "cadence"]} { incr score 5 }
        if {[path_contains $lef "lefheader"]} { incr score 5 }
        if {[path_contains $lef "hv"] || [path_contains $lef "hvh"]} {
            incr score 2
        }
        if {$score > $best_score || ($score == $best_score &&
                                     ($best_path eq "" ||
                                      [string compare $lef $best_path] < 0))} {
            set best_score $score
            set best_path $lef
        }
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

set std_cell_root "${TECH_ROOT}/SC/${TSMC22_STD_CELL}"
set std_cell_search_root $TECH_ROOT
if {[file exists $std_cell_root]} {
    set std_cell_search_root $std_cell_root
}

proc discover_innovus_lib_files {} {
    global std_cell_search_root
    if {![file exists $std_cell_search_root]} {
        return [list]
    }
    return [choose_one_liberty_timing_lib \
                [find_files_recursive $std_cell_search_root "*.lib"]]
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
    return [choose_one_technology_lef [filter_technology_lefs $candidates]]
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
    foreach lib $lib_files {
        if {![is_liberty_timing_lib $lib]} {
            puts stderr "INNOVUS_LIB_FILES contains a non-Liberty timing file:"
            puts stderr "  $lib"
            puts stderr "Innovus MMMC timing libraries must be Liberty .lib files,"
            puts stderr "not Cadence cds.lib or back-end CDK mapping files."
            exit 1
        }
    }
} else {
    set lib_files [discover_innovus_lib_files]
}

if {[llength $INNOVUS_LEF_FILES] > 0} {
    set lef_files $INNOVUS_LEF_FILES
} else {
    if {[info exists INNOVUS_TECH_LEF_FILES] &&
        [llength $INNOVUS_TECH_LEF_FILES] > 0} {
        set tech_lefs $INNOVUS_TECH_LEF_FILES
        if {[llength $tech_lefs] > 1} {
            puts stderr "INNOVUS_TECH_LEF_FILES contains multiple technology LEFs."
            puts stderr "Innovus must load exactly one technology LEF/header first;"
            puts stderr "otherwise VIA definitions are duplicated and later routing"
            puts stderr "layers are ignored. Keep only the one matching routing stack"
            puts stderr "$TSMC22_ROUTING_STACK."
            puts stderr "Current list:"
            foreach lef $tech_lefs {
                puts stderr "  $lef"
            }
            exit 1
        }
    } else {
        set tech_lefs [discover_innovus_tech_lefs]
    }

    if {[info exists INNOVUS_CELL_LEF_FILES] &&
        [llength $INNOVUS_CELL_LEF_FILES] > 0} {
        set cell_lefs $INNOVUS_CELL_LEF_FILES
    } else {
        set cell_lefs [discover_innovus_cell_lefs]
    }

    set lef_files [concat $tech_lefs $cell_lefs]
}

if {$INNOVUS_QRC_FILE ne ""} {
    set qrc_file $INNOVUS_QRC_FILE
} elseif {[file exists $TECH_ROOT]} {
    set qrc_candidates [find_files_recursive $TECH_ROOT "*.tch"]
    if {[llength $qrc_candidates] > 0} {
        set qrc_file [lindex $qrc_candidates 0]
    }
}

if {[llength $lib_files] == 0} {
    puts stderr "No Innovus .lib files found. Edit TECH_ROOT or INNOVUS_LIB_FILES in scripts/flow_config.tcl."
    exit 1
}
if {[llength $lib_files] != 1} {
    puts stderr "Expected exactly one Innovus Liberty timing library for this flow, but got:"
    foreach lib $lib_files {
        puts stderr "  $lib"
    }
    puts stderr "Set INNOVUS_LIB_FILES to the single .lib matching the DC corner,"
    puts stderr "for example the ffg0p88v0c NLDM Liberty file."
    exit 1
}
if {[llength $lef_files] == 0} {
    puts stderr "No Innovus LEF files found. Edit TECH_ROOT or INNOVUS_LEF_FILES in scripts/flow_config.tcl."
    exit 1
}
if {![is_technology_lef [lindex $lef_files 0]]} {
    if {[llength $INNOVUS_LEF_FILES] == 0 &&
        (![info exists INNOVUS_TECH_LEF_FILES] ||
         [llength $INNOVUS_TECH_LEF_FILES] == 0)} {
        puts stderr "No technology LEF was auto-discovered under TECH_ROOT:"
        puts stderr "  $TECH_ROOT"
        puts stderr "Run this helper on the VDI to find candidate files:"
        puts stderr "  ./scripts/find_innovus_tech_files.sh"
        puts stderr "Then set INNOVUS_TECH_LEF_FILES and INNOVUS_CELL_LEF_FILES in scripts/flow_config.tcl."
        puts stderr ""
    }
    puts stderr "The first Innovus LEF is not a technology LEF:"
    puts stderr "  [lindex $lef_files 0]"
    puts stderr "Put a technology LEF first via INNOVUS_TECH_LEF_FILES or an ordered INNOVUS_LEF_FILES list."
    puts stderr "A standard-cell LEF cannot be first because it references routing layers such as M1."
    exit 1
}
if {$qrc_file eq ""} {
    puts stderr "No Innovus QRC .tch file found. Edit TECH_ROOT or INNOVUS_QRC_FILE in scripts/flow_config.tcl."
    puts stderr "Try searching manually on the VDI with:"
    puts stderr "  find $TECH_ROOT -type f \\( -name '*.tch' -o -iname '*qrc*' -o -name '*.ict' \\)"
    exit 1
}
if {![file exists $qrc_file]} {
    puts stderr "Innovus QRC file does not exist: $qrc_file"
    exit 1
}

set tech_routing_layers [lef_routing_layers [lindex $lef_files 0]]
if {[info exists TSMC22_EXPECTED_ROUTING_LAYER_COUNT] &&
    $TSMC22_EXPECTED_ROUTING_LAYER_COUNT > 0 &&
    [llength $tech_routing_layers] != $TSMC22_EXPECTED_ROUTING_LAYER_COUNT} {
    puts stderr "Technology LEF/QRC stack mismatch before init_design."
    puts stderr "  Technology LEF: [lindex $lef_files 0]"
    puts stderr "  Routing layers: $tech_routing_layers"
    puts stderr "  Expected routing layer count: $TSMC22_EXPECTED_ROUTING_LAYER_COUNT"
    puts stderr "  QRC file: $qrc_file"
    puts stderr "Use a tech LEF from the same 1P8M/5x2z stack as the QRC file."
    exit 1
}

set init_lib_search_path [list]
foreach lib $lib_files {
    lappend init_lib_search_path [file dirname $lib]
}
foreach lef $lef_files {
    lappend init_lib_search_path [file dirname $lef]
}

set libworst $lib_files
set libbest  $lib_files
set lefs     $lef_files
set qrc_max  $qrc_file
set qrc_min  $qrc_file

puts "Innovus timing libraries:"
foreach lib $lib_files {
    puts "  $lib"
}
puts "Innovus LEF load order:"
foreach lef $lef_files {
    puts "  $lef"
}
puts "Innovus QRC file:"
puts "  $qrc_file"
puts "Technology LEF routing layers: $tech_routing_layers"
