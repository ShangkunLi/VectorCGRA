# Paper-friendly post-route layout export for AMOEBA Innovus sessions.
#
# Usage inside an already restored Innovus session:
#   cd /dfs/usrhome/slifd/VectorCGRA/AMOEBA-Test/physical_flow
#   set ::amoeba_layout_gif "reports/amoeba_post_route_layout.gif"
#   set ::amoeba_layout_draw_grid 1
#   source scripts/export_paper_layout.tcl
#
# If no design is loaded, restore first, for example:
#   set restore_db_file_check 0
#   restoreDesign enc/amoeba.enc.dat AmoebaMultiCgra4x4Cgra2x2RTL
#
# The output image resolution follows the active Innovus layout canvas size.
# For paper figures, maximize the Innovus window before sourcing this script.

proc amoeba_layout_get_or_default {var_name default_value} {
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

    # Disable Voltus-style analysis overlays. Routing shapes remain visible.
    catch {set_power_rail_display -plot none}
}

proc amoeba_layout_prepare_layers {} {
    # Hide display classes that tend to cover routed metals in screenshots.
    amoeba_layout_try_set_layer StandardRow 0
    amoeba_layout_try_set_layer row 0
    amoeba_layout_try_set_layer Row 0
    amoeba_layout_try_set_layer violation 0

    # Keep actual placed cells and routed metals visible.
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

proc amoeba_layout_core_box {} {
    set box ""
    catch {set box [dbGet top.fPlan.coreBox]}
    if {$box eq "" || $box eq "0x0"} {
        catch {set box [dbGet top.fPlan.box]}
    }
    if {$box eq "" || $box eq "0x0"} {
        error "Could not read Innovus floorplan/core box."
    }
    return $box
}

proc amoeba_layout_draw_grid {} {
    set rows [amoeba_layout_get_or_default ::amoeba_layout_grid_rows 4]
    set cols [amoeba_layout_get_or_default ::amoeba_layout_grid_cols 4]
    set width [amoeba_layout_get_or_default ::amoeba_layout_grid_width 5]
    set color [amoeba_layout_get_or_default ::amoeba_layout_grid_color white]

    if {$width < 1} {
        set width 1
    }
    if {$width > 7} {
        puts "Grid line width $width is too large for add_gui_shape; clamping to 7."
        set width 7
    }

    amoeba_layout_try_set_layer amoeba_paper_grid 1 $color $width

    lassign [amoeba_layout_core_box] llx lly urx ury
    set cell_w [expr {($urx - $llx) / double($cols)}]
    set cell_h [expr {($ury - $lly) / double($rows)}]

    for {set i 0} {$i <= $cols} {incr i} {
        set x [expr {$llx + $i * $cell_w}]
        add_gui_shape -layer amoeba_paper_grid -width $width \
            -line [list $x $lly $x $ury]
    }
    for {set i 0} {$i <= $rows} {incr i} {
        set y [expr {$lly + $i * $cell_h}]
        add_gui_shape -layer amoeba_paper_grid -width $width \
            -line [list $llx $y $urx $y]
    }
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
    set pdf_file "${base_name}.pdf"
    if {![catch {hardCopy -format pdf -file $pdf_file} err]} {
        puts "Wrote PDF hardcopy: $pdf_file"
        set wrote 1
    } else {
        puts "PDF hardCopy unavailable or failed: $err"
    }

    set ps_file "${base_name}.ps"
    if {![catch {hardCopy -format ps -file $ps_file} err]} {
        puts "Wrote PS hardcopy: $ps_file"
        set wrote 1
    } else {
        puts "PS hardCopy unavailable or failed: $err"
    }
    return $wrote
}

proc amoeba_export_paper_layout {} {
    amoeba_layout_require_design

    set gif_file [amoeba_layout_get_or_default \
        ::amoeba_layout_gif "reports/amoeba_post_route_layout.gif"]
    set base_name [amoeba_layout_get_or_default \
        ::amoeba_layout_hardcopy_base "reports/amoeba_post_route_layout"]
    set draw_grid [amoeba_layout_get_or_default ::amoeba_layout_draw_grid 1]
    set export_hardcopy [amoeba_layout_get_or_default ::amoeba_layout_export_hardcopy 1]

    file mkdir [file dirname $gif_file]
    file mkdir [file dirname $base_name]

    amoeba_layout_clean_display
    amoeba_layout_prepare_layers
    if {$draw_grid} {
        amoeba_layout_draw_grid
    }

    catch {fit}
    catch {redraw}

    puts ""
    puts "Display is prepared for paper export."
    puts "Tip: for a higher-resolution GIF, maximize the Innovus window and source this script again."
    amoeba_layout_try_dump_gif $gif_file

    if {$export_hardcopy} {
        amoeba_layout_try_hardcopy $base_name
    }
}

amoeba_export_paper_layout
