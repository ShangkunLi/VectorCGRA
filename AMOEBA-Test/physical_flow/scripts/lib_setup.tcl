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
    global TSMC22_ROUTING_STACK

    if {[llength $tech_lefs] == 0} {
        return [list]
    }

    # A routing-stack LEF/header defines routing layers and vias. Loading more
    # than one such file causes duplicate VIA definitions, and layers defined
    # after the first technology LEF are ignored by Innovus.
    set best_path ""
    set best_score -1
    foreach lef $tech_lefs {
        set score 0
        if {[info exists TSMC22_ROUTING_STACK] &&
            $TSMC22_ROUTING_STACK ne "" &&
            [path_contains $lef $TSMC22_ROUTING_STACK]} {
            incr score 100
        }
        if {[path_contains $lef "9m"]} {
            incr score 20
        }
        if {[path_contains $lef "innovus"]} {
            incr score 10
        }
        if {[path_contains $lef "cadence"]} {
            incr score 5
        }
        if {[path_contains $lef "lefheader"]} {
            incr score 3
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
    return [find_files_recursive $std_cell_search_root "*.lib"]
}

proc discover_innovus_tech_lefs {} {
    global TECH_ROOT TSMC22_STD_CELL TSMC22_ROUTING_STACK

    set roots [list \
        "${TECH_ROOT}/SC/${TSMC22_STD_CELL}" \
        "${TECH_ROOT}/SC" \
        "${TECH_ROOT}/PDK" \
        "${TECH_ROOT}/Back_End" \
        "${TECH_ROOT}" \
    ]

    set candidates [list]
    foreach root $roots {
        append_unique candidates [find_lef_like_files_recursive $root]
    }
    set tech_lefs [filter_technology_lefs $candidates]

    # Prefer the same routing stack as the QRC file when multiple technology
    # LEFs exist in the PDK. The default TSMC22 ULL setup uses 5x2z.
    if {[info exists TSMC22_ROUTING_STACK] && $TSMC22_ROUTING_STACK ne ""} {
        set stack_matches [list]
        foreach lef $tech_lefs {
            if {[path_contains $lef $TSMC22_ROUTING_STACK]} {
                lappend stack_matches $lef
            }
        }
        if {[llength $stack_matches] > 0} {
            return [choose_one_technology_lef [lsort $stack_matches]]
        }
    }

    return [choose_one_technology_lef $tech_lefs]
}

proc discover_innovus_cell_lefs {} {
    global std_cell_root std_cell_search_root TSMC22_STD_CELL

    set roots [list]
    if {[file exists $std_cell_root]} {
        lappend roots $std_cell_root
    } else {
        lappend roots $std_cell_search_root
    }

    set candidates [list]
    foreach root $roots {
        append_unique candidates [find_files_recursive $root "*.lef"]
    }

    set cell_lefs [list]
    foreach lef $candidates {
        if {[is_technology_lef $lef]} {
            continue
        }
        if {![path_contains $lef $TSMC22_STD_CELL]} {
            continue
        }
        lappend cell_lefs $lef
    }
    return [lsort $cell_lefs]
}

if {[llength $INNOVUS_LIB_FILES] > 0} {
    set lib_files $INNOVUS_LIB_FILES
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
