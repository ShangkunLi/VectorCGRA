# Paper-friendly layout export for the AMOEBA 4x4 grid Innovus database.
#
# This script can be sourced in an already-loaded Innovus session or by
# scripts/export_layout_image.tcl after restoring enc/amoeba_grid.enc.dat.

proc amoeba_layout_get_or_default {var_name default_value} {
    if {[uplevel #0 [list info exists $var_name]]} {
        return [uplevel #0 [list set $var_name]]
    }
    return $default_value
}

proc amoeba_layout_global_or_default {var_name default_value} {
    if {[uplevel #0 [list info exists $var_name]]} {
        return [uplevel #0 [list set $var_name]]
    }
    return $default_value
}

proc amoeba_layout_require_design {} {
    if {[catch {set top_name [dbGet top.name]}] ||
        $top_name eq "" || $top_name eq "0x0"} {
        error "No Innovus design is loaded. Restore the post-route design first."
    }
    puts "Loaded Innovus design: $top_name"
}

proc amoeba_layout_try_set_layer {layer_name visible {color ""} {width ""}} {
    catch {setLayerPreference $layer_name -isVisible $visible}
    if {$color ne ""} {
        catch {setLayerPreference $layer_name -color $color}
    }
    if {$width ne ""} {
        catch {setLayerPreference $layer_name -lineWidth $width}
    }
}

proc amoeba_layout_clean_display {} {
    catch {clearAllRulers}
    catch {delete_gui_object -text}
    catch {delete_gui_object -shape}
    catch {clearDrc}
    catch {clearViolationBrowser}
    catch {setLayerPreference violation -isVisible 0}
    catch {setLayerPreference ruler -isVisible 0}

    catch {setPreference ShowInstanceText 0}
    catch {setPreference ShowNetText 0}
    catch {setPreference ShowIoPinText 0}
    catch {setPreference ShowGroupText 0}
    catch {setPreference ShowModuleText 0}
    catch {setPreference ShowInstancePinText 0}
    catch {setPreference ShowUtilizationText 0}
    catch {setPreference DisplayPinName 0}
    catch {setPreference ShowFloorplanObjectName 0}
    catch {setPreference LayoutBackground black}

    catch {set_power_rail_display -plot none}
}

proc amoeba_layout_prepare_layers {} {
    foreach layer {StandardRow row Row violation ruler} {
        amoeba_layout_try_set_layer $layer 0
    }

    foreach layer {M1 VIA1 M2 VIA2 M3 VIA3 M4 VIA4 M5 VIA5 M6 VIA6 M7 VIA7 M8 RV AP} {
        amoeba_layout_try_set_layer $layer 1
    }
    foreach class {Wire Via PatchWire TrimMetal Shield EarlyGlobal MetalFill} {
        amoeba_layout_try_set_layer $class 1
    }
    foreach class {StdCell Block Cover Physical IO AreaIO BlackBox} {
        amoeba_layout_try_set_layer $class 1
    }
}

proc amoeba_layout_resolve_grid_report {} {
    set candidates {}
    set configured [amoeba_layout_get_or_default ::amoeba_layout_grid_report ""]
    if {$configured ne ""} {
        lappend candidates $configured
    }
    if {[info exists ::CORE_GRID_REPORT]} {
        lappend candidates $::CORE_GRID_REPORT
    }
    lappend candidates "reports/core_grid_regions.rpt"
    lappend candidates "core_grid_regions.rpt"

    foreach path $candidates {
        if {$path ne "" && [file exists $path]} {
            return $path
        }
    }
    error "Could not find core grid report. Tried: $candidates"
}

proc amoeba_layout_load_grid_boxes {rpt_file} {
    set boxes [dict create]
    set fp [open $rpt_file r]
    set is_header 1
    while {[gets $fp line] >= 0} {
        if {$is_header} {
            set is_header 0
            continue
        }
        if {[string trim $line] eq ""} {
            continue
        }

        set fields [split $line ,]
        if {[llength $fields] != 8} {
            continue
        }

        lassign $fields core_id group_name mode inst_count llx lly urx ury
        dict set boxes $core_id [list $llx $lly $urx $ury]
    }
    close $fp
    return $boxes
}

proc amoeba_layout_draw_box {llx lly urx ury layer width} {
    add_gui_shape -layer $layer -width $width -line [list $llx $lly $urx $lly]
    add_gui_shape -layer $layer -width $width -line [list $urx $lly $urx $ury]
    add_gui_shape -layer $layer -width $width -line [list $urx $ury $llx $ury]
    add_gui_shape -layer $layer -width $width -line [list $llx $ury $llx $lly]
}

proc amoeba_layout_add_label {core_id llx lly urx ury layer} {
    set label_enable [amoeba_layout_get_or_default ::amoeba_layout_label_enable 0]
    if {!$label_enable} {
        return
    }

    set cx [expr {($llx + $urx) / 2.0}]
    set cy [expr {($lly + $ury) / 2.0}]
    add_gui_text -layer $layer -label [format "CGRA %d" $core_id] \
        -fixed_height 18 -pt [list $cx $cy]
}

proc amoeba_layout_draw_core_grid {} {
    set line_width [amoeba_layout_get_or_default ::amoeba_layout_line_width 7]
    if {$line_width < 1} {
        set line_width 1
    }
    if {$line_width > 7} {
        puts "Grid line width $line_width is too large for add_gui_shape; clamping to 7."
        set line_width 7
    }

    set grid_layer "amoeba_paper_grid"
    set text_layer "amoeba_paper_text"
    amoeba_layout_try_set_layer $grid_layer 1 white $line_width
    amoeba_layout_try_set_layer $text_layer 1 white $line_width

    set rpt_file [amoeba_layout_resolve_grid_report]
    set boxes [amoeba_layout_load_grid_boxes $rpt_file]
    set rows [amoeba_layout_get_or_default ::amoeba_layout_grid_rows 4]
    set cols [amoeba_layout_get_or_default ::amoeba_layout_grid_cols 4]
    set expected [expr {$rows * $cols}]

    if {[dict size $boxes] < $expected} {
        puts "Warning: only found [dict size $boxes] grid boxes in $rpt_file; expected $expected."
    }

    for {set core_id 0} {$core_id < $expected} {incr core_id} {
        if {![dict exists $boxes $core_id]} {
            continue
        }
        lassign [dict get $boxes $core_id] llx lly urx ury
        amoeba_layout_draw_box $llx $lly $urx $ury $grid_layer $line_width
        amoeba_layout_add_label $core_id $llx $lly $urx $ury $text_layer
    }

    puts "Drew AMOEBA 4x4 grid overlay from $rpt_file"
}

proc amoeba_layout_try_dump_gif {gif_file} {
    set ok 0
    if {![catch {dumpToGIF $gif_file} err]} {
        puts "Wrote GIF layout image: $gif_file"
        set ok 1
    } else {
        puts "dumpToGIF failed: $err"
    }
    return $ok
}

proc amoeba_layout_try_hardcopy {base_name} {
    set wrote 0
    foreach fmt {pdf ps} {
        set out_file "${base_name}.${fmt}"
        if {![catch {hardCopy -format $fmt -file $out_file} err]} {
            puts "Wrote $fmt hardcopy: $out_file"
            set wrote 1
        } else {
            puts "$fmt hardCopy unavailable or failed: $err"
        }
    }
    return $wrote
}

proc amoeba_export_multicore_layout {} {
    amoeba_layout_require_design

    set output_dir [amoeba_layout_get_or_default ::amoeba_layout_output_dir "reports/layout"]
    set basename [amoeba_layout_get_or_default ::amoeba_layout_output_basename "amoeba_grid_post_route_layout"]
    set gif_file [file join $output_dir "${basename}.gif"]
    set hardcopy_base [file join $output_dir $basename]
    set export_hardcopy [amoeba_layout_get_or_default ::amoeba_layout_export_hardcopy 1]

    file mkdir $output_dir

    amoeba_layout_clean_display
    amoeba_layout_prepare_layers
    amoeba_layout_draw_core_grid

    catch {fit}
    catch {redraw}

    puts ""
    puts "Display is prepared for paper export."
    amoeba_layout_try_dump_gif $gif_file
    if {$export_hardcopy} {
        amoeba_layout_try_hardcopy $hardcopy_base
    }
}

set ::amoeba_layout_output_dir [amoeba_layout_get_or_default \
    ::amoeba_layout_output_dir \
    [amoeba_layout_global_or_default LAYOUT_OUTPUT_DIR "reports/layout"]]
set ::amoeba_layout_output_basename [amoeba_layout_get_or_default \
    ::amoeba_layout_output_basename \
    [amoeba_layout_global_or_default LAYOUT_OUTPUT_BASENAME "amoeba_grid_post_route_layout"]]
set ::amoeba_layout_grid_report [amoeba_layout_get_or_default \
    ::amoeba_layout_grid_report \
    [amoeba_layout_global_or_default CORE_GRID_REPORT "reports/core_grid_regions.rpt"]]
set ::amoeba_layout_grid_rows [amoeba_layout_get_or_default \
    ::amoeba_layout_grid_rows \
    [amoeba_layout_global_or_default CORE_GRID_ROWS 4]]
set ::amoeba_layout_grid_cols [amoeba_layout_get_or_default \
    ::amoeba_layout_grid_cols \
    [amoeba_layout_global_or_default CORE_GRID_COLS 4]]
set ::amoeba_layout_line_width [amoeba_layout_get_or_default \
    ::amoeba_layout_line_width \
    [amoeba_layout_global_or_default LAYOUT_GRID_LINE_WIDTH 7]]
set ::amoeba_layout_label_enable [amoeba_layout_get_or_default \
    ::amoeba_layout_label_enable \
    [amoeba_layout_global_or_default LAYOUT_LABEL_ENABLE 0]]
set ::amoeba_layout_export_hardcopy [amoeba_layout_get_or_default \
    ::amoeba_layout_export_hardcopy \
    [amoeba_layout_global_or_default LAYOUT_EXPORT_HARDCOPY 1]]

amoeba_export_multicore_layout
