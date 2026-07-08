# Paper-friendly high-resolution GIF export for AMOEBA Innovus sessions.
#
# This script follows the display-cleanup style used by the reference CGRA
# layout scripts, but does not draw a white tile/core grid. It keeps the routed
# post-route layout visible and exports a GIF from the active Innovus canvas.
#
# Usage inside an already restored Innovus session:
#   cd /dfs/usrhome/slifd/VectorCGRA/AMOEBA-Test/physical_flow
#   source scripts/export_paper_layout.tcl
#
# Optional controls before source:
#   set ::amoeba_layout_gif "reports/amoeba_post_route_layout.gif"
#   set ::amoeba_layout_show_rows 0
#   set ::amoeba_layout_show_text 0
#
# GIF resolution follows the active Innovus layout canvas size. For a paper
# figure, maximize the Innovus layout window before sourcing this script.

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

proc amoeba_layout_try_set_preference {pref_name pref_value} {
    catch {setPreference $pref_name $pref_value}
}

proc amoeba_layout_clean_annotations {} {
    catch {clearAllRulers}
    catch {delete_gui_object -text}
    catch {delete_gui_object -shape}
    catch {clearDrc}
    catch {clearViolationBrowser}
    catch {deselectAll}
}

proc amoeba_layout_prepare_text_display {} {
    set show_text [amoeba_layout_get_or_default ::amoeba_layout_show_text 0]
    if {$show_text} {
        set text_visible 1
    } else {
        set text_visible 0
    }

    foreach pref {
        ShowInstanceText
        ShowNetText
        ShowIoPinText
        ShowGroupText
        ShowModuleText
        ShowInstancePinText
        ShowUtilizationText
        DisplayPinName
    } {
        amoeba_layout_try_set_preference $pref $text_visible
    }
}

proc amoeba_layout_prepare_display_classes {} {
    set show_rows [amoeba_layout_get_or_default ::amoeba_layout_show_rows 0]

    # These are the main sources of clutter in screenshot-style exports.
    amoeba_layout_try_set_layer violation 0
    amoeba_layout_try_set_layer ruler 0

    if {$show_rows} {
        amoeba_layout_try_set_layer StandardRow 1
        amoeba_layout_try_set_layer row 1
        amoeba_layout_try_set_layer Row 1
    } else {
        amoeba_layout_try_set_layer StandardRow 0
        amoeba_layout_try_set_layer row 0
        amoeba_layout_try_set_layer Row 0
    }

    # Keep placed logic and IO markers visible.
    foreach class {StdCell Block Cover Physical IO AreaIO BlackBox} {
        amoeba_layout_try_set_layer $class 1
    }

    # Keep routed layout visible. Different Innovus versions expose some of
    # these as display classes and others as physical layers, so use catch.
    foreach class {Wire Via PatchWire TrimMetal Shield EarlyGlobal MetalFill} {
        amoeba_layout_try_set_layer $class 1
    }

    foreach layer {
        M1 VIA1 M2 VIA2 M3 VIA3 M4 VIA4
        M5 VIA5 M6 VIA6 M7 VIA7 M8 RV AP
    } {
        amoeba_layout_try_set_layer $layer 1
    }

    # Avoid Voltus/power-analysis overlays covering the routed view.
    catch {set_power_rail_display -plot none}
}

proc amoeba_layout_prepare_route_view {} {
    # These mirror the reference scripts' idea: force routed detail to stay
    # visible and suppress dense labels at full-chip zoom.
    amoeba_layout_try_set_preference ShowRoute 1
    amoeba_layout_try_set_preference ShowFPObjInPlace 0
    amoeba_layout_try_set_preference ShowAllFence 0
    amoeba_layout_try_set_preference DisplayRelFPlan 0
    amoeba_layout_try_set_preference AutoDetailDisplay 0
    amoeba_layout_try_set_preference DetailDisplayFactor 1000000
}

proc amoeba_layout_try_dump_gif {gif_file} {
    if {![catch {dumpToGIF $gif_file} err]} {
        puts "Wrote GIF layout image: $gif_file"
        return 1
    }

    puts "dumpToGIF failed: $err"
    return 0
}

proc amoeba_export_paper_layout {} {
    amoeba_layout_require_design

    set gif_file [amoeba_layout_get_or_default \
        ::amoeba_layout_gif "reports/amoeba_post_route_layout.gif"]
    file mkdir [file dirname $gif_file]

    amoeba_layout_clean_annotations
    amoeba_layout_prepare_text_display
    amoeba_layout_prepare_display_classes
    amoeba_layout_prepare_route_view

    catch {fit}
    catch {redraw}

    puts ""
    puts "Paper layout view is prepared."
    puts "No grid/white outline is drawn."
    puts "For higher resolution, maximize the Innovus layout window and source this script again."
    amoeba_layout_try_dump_gif $gif_file
}

amoeba_export_paper_layout
