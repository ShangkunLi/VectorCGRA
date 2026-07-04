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

if {[llength $INNOVUS_LIB_FILES] > 0} {
    set lib_files $INNOVUS_LIB_FILES
} elseif {[file exists $TECH_ROOT]} {
    set lib_files [find_files_recursive $TECH_ROOT "*.lib"]
}

if {[llength $INNOVUS_LEF_FILES] > 0} {
    set lef_files $INNOVUS_LEF_FILES
} elseif {[file exists $TECH_ROOT]} {
    set lef_files [find_files_recursive $TECH_ROOT "*.lef"]
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
