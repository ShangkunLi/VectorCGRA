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
    if {[catch {exec find $root -type f -name $pattern} found]} {
        return $files
    }
    foreach path [split $found "\n"] {
        if {$path ne ""} {
            lappend files $path
        }
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
        append_unique candidates [find_files_recursive $root "*.lef"]
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
            return [lsort $stack_matches]
        }
    }

    return $tech_lefs
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
    puts stderr "No Innovus .lef files found. Edit TECH_ROOT or INNOVUS_LEF_FILES in scripts/flow_config.tcl."
    exit 1
}
if {![is_technology_lef [lindex $lef_files 0]]} {
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
