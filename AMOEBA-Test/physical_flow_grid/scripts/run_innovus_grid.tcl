# Innovus-only AMOEBA flow with 4x4 multi-core grid constraints.

set ::AMOEBA_GRID_SCRIPT_DIR [file dirname [file normalize [info script]]]
set ::AMOEBA_GRID_FLOW_DIR [file dirname $::AMOEBA_GRID_SCRIPT_DIR]
set ::AMOEBA_BASE_FLOW_DIR [file normalize [file join $::AMOEBA_GRID_FLOW_DIR ".." "physical_flow"]]
set ::AMOEBA_BASE_SCRIPTS [file join $::AMOEBA_BASE_FLOW_DIR "scripts"]

source scripts/flow_config.tcl
source [file join $::AMOEBA_BASE_SCRIPTS "lib_setup.tcl"]
source [file join $::AMOEBA_BASE_SCRIPTS "report_utils.tcl"]
source [file join $::AMOEBA_BASE_SCRIPTS "placement_utils.tcl"]

setMultiCpuUsage -localCpu $INNOVUS_CPUS

proc amoeba_grid_require_file {path description} {
    if {![file exists $path]} {
        puts stderr "$description not found: $path"
        exit 1
    }
}

amoeba_grid_require_file $NETLIST "DC handoff netlist"
amoeba_grid_require_file $SDC_FILE "DC handoff SDC"

source [file join $::AMOEBA_BASE_SCRIPTS "mmmc_setup.tcl"]

set rptDir "summaryReport"
set encDir "enc"
set defDir "def"
foreach dir [list $rptDir $encDir $defDir timingReports reports $LAYOUT_OUTPUT_DIR log] {
    if {![file exists $dir]} {
        file mkdir $dir
    }
}

set init_pwr_net VDD
set init_gnd_net VSS
set init_verilog $NETLIST
set init_design_netlisttype "Verilog"
set init_design_settop 1
set init_top_cell $TOP_MODULE
set init_lef_file $lefs

init_design -setup {WC_VIEW} -hold {BC_VIEW}
set_power_analysis_mode -leakage_power_view WC_VIEW -dynamic_power_view WC_VIEW

set_interactive_constraint_modes {CON}
setAnalysisMode -reset
setAnalysisMode -analysisType onChipVariation -cppr both

clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst * -override
globalNetConnect VSS -type pgpin -pin VSS -inst * -override
globalNetConnect VDD -type tiehi -inst * -override
globalNetConnect VSS -type tielo -inst * -override

setOptMode -powerEffort low -leakageToDynamicRatio 0.5 \
    -fixCap true -fixTran true -fixFanoutLoad true
createBasicPathGroups -expanded

proc amoeba_grid_get_available_sites {} {
    set sites [list]
    if {[catch {set db_sites [dbGet head.sites.name]}]} {
        return $sites
    }
    foreach site $db_sites {
        if {$site ne "" && $site ne "0x0" &&
            [lsearch -exact $sites $site] < 0} {
            lappend sites $site
        }
    }
    return $sites
}

proc amoeba_grid_get_macro_sites_from_lefs {lef_files} {
    set sites [list]
    foreach lef $lef_files {
        if {[catch {set fp [open $lef r]}]} {
            continue
        }
        while {[gets $fp line] >= 0} {
            if {[regexp {^[ \t]*SITE[ \t]+([^ \t;]+)[ \t]*;} $line -> site] &&
                [lsearch -exact $sites $site] < 0} {
                lappend sites $site
            }
        }
        close $fp
    }
    return $sites
}

proc amoeba_grid_resolve_floorplan_site {configured_site lef_files} {
    set available_sites [amoeba_grid_get_available_sites]
    puts "Innovus available placement sites: $available_sites"

    if {$configured_site ne "" &&
        [lsearch -exact $available_sites $configured_site] >= 0} {
        return $configured_site
    }

    if {$configured_site ne ""} {
        puts "Configured SITE '$configured_site' was not found in the loaded LEFs."
    }

    set macro_sites [amoeba_grid_get_macro_sites_from_lefs $lef_files]
    puts "Standard-cell macro SITE candidates from LEF: $macro_sites"
    foreach site $macro_sites {
        if {[lsearch -exact $available_sites $site] >= 0} {
            puts "Using floorplan SITE '$site' from the standard-cell LEF."
            return $site
        }
    }

    foreach site $available_sites {
        puts "Using first available floorplan SITE '$site'."
        return $site
    }

    puts stderr "No placement SITE was found after init_design."
    exit 1
}

set FLOORPLAN_SITE [amoeba_grid_resolve_floorplan_site $SITE $lefs]
setFPlanMode -snapBlockGrid LayerTrack
floorPlan -site $FLOORPLAN_SITE -r 1.0 $FP_UTIL $FP_MARGIN $FP_MARGIN $FP_MARGIN $FP_MARGIN
amoeba_place_boundary_pins

if {[info exists CORE_GRID_ENABLE] && $CORE_GRID_ENABLE} {
    source scripts/multicore_grid_constraints.tcl
}

setDesignMode -topRoutingLayer $TOP_ROUTING_LAYER
setDesignMode -bottomRoutingLayer 2
catch {setPlaceMode -place_detail_legalization_inst_gap 1}
catch {setFillerMode -fitGap true}

set details_file "${DESIGN}_DETAILS.rpt"
set details_fp [open $details_file "w"]
puts $details_fp "Physical Design Stage,Core Area (um^2),Standard Cell Area (um^2),Macro Area (um^2),Total Power,Wirelength(um)"
close $details_fp

if {[info exists RUN_FULL_STAGE_REPORTS] && $RUN_FULL_STAGE_REPORTS} {
    set rpt_post_synth [extract_report postSynth]
    echo "$rpt_post_synth" >> $details_file
}

defOut -floorplan ${defDir}/${DESIGN}_fp.def
if {[info exists SAVE_INTERMEDIATE_DBS] && $SAVE_INTERMEDIATE_DBS} {
    saveDesign ${encDir}/${DESIGN}_init.enc
}

place_opt_design -out_dir $rptDir -prefix place
optDesign -preCTS
defOut -floorplan -placement ${defDir}/${DESIGN}_placed.def
if {[info exists SAVE_INTERMEDIATE_DBS] && $SAVE_INTERMEDIATE_DBS} {
    saveDesign ${encDir}/${DESIGN}_placed.enc
}

if {[info exists RUN_FULL_STAGE_REPORTS] && $RUN_FULL_STAGE_REPORTS} {
    set rpt_pre_cts [extract_report preCTS]
    echo "$rpt_pre_cts" >> $details_file
}

catch {set_ccopt_property post_conditioning_enable_routing_eco 1}
catch {set_ccopt_property -cts_def_lock_clock_sinks_after_routing true}
catch {setOptMode -unfixClkInstForOpt false}

create_ccopt_clock_tree_spec
ccopt_design

set_interactive_constraint_modes [all_constraint_modes -active]
set_propagated_clock [all_clocks]
set_clock_propagation propagated
optDesign -postCTS

if {[info exists SAVE_INTERMEDIATE_DBS] && $SAVE_INTERMEDIATE_DBS} {
    saveDesign ${encDir}/${DESIGN}_cts.enc
}

if {[info exists RUN_FULL_STAGE_REPORTS] && $RUN_FULL_STAGE_REPORTS} {
    set rpt_post_cts [extract_report postCTS]
    echo "$rpt_post_cts" >> $details_file
}

setNanoRouteMode -drouteVerboseViolationSummary 1
setNanoRouteMode -routeWithSiDriven $ROUTE_SI_DRIVEN
setNanoRouteMode -routeWithTimingDriven $ROUTE_TIMING_DRIVEN
setNanoRouteMode -routeUseAutoVia true
catch {setNanoRouteMode -routeWithViaInPin "1:1"}
catch {setNanoRouteMode -routeWithViaOnlyForStandardCellPin "1:1"}
catch {setNanoRouteMode -drouteOnGridOnly "via 1:1"}
catch {setNanoRouteMode -drouteExpAdvancedMarFix true}
catch {setNanoRouteMode -routeExpAdvancedTechnology true}
catch {setNanoRouteMode -grouteExpWithTimingDriven false}
setNanoRouteMode -drouteAutoStop false

routeDesign
saveDesign ${encDir}/${DESIGN}_route.enc
defOut -netlist -floorplan -routing ${defDir}/${DESIGN}_route.def

catch {
    setViaGenMode -reset
    editPowerVia -top_layer M2 -bottom_layer M1 -orthogonal_only 0 -add_vias 1
}

verify_connectivity -error 0 -geom_connect -no_antenna
verify_drc -limit 0

if {[info exists RUN_FULL_STAGE_REPORTS] && $RUN_FULL_STAGE_REPORTS} {
    set rpt_post_route [extract_report postRoute]
    echo "$rpt_post_route" >> $details_file
}

optDesign -postRoute

set rpt_post_route_opt [extract_report postRouteOpt]
echo "$rpt_post_route_opt" >> $details_file

verify_connectivity -error 0 -geom_connect -no_antenna
verify_drc -limit 0

summaryReport -noHtml -outfile ${rptDir}/post_route.sum
write_area_breakdown_csv reports/innovus_area_breakdown.csv
write_tile_area_breakdown_csv reports/innovus_tile_area_breakdown.csv
defOut -netlist -floorplan -routing ${defDir}/${DESIGN}.def

if {[info exists WRITE_POST_ROUTE_NETLIST] && $WRITE_POST_ROUTE_NETLIST} {
    saveNetlist -removePowerGround ${defDir}/${TOP_MODULE}_post_route.v
}
saveDesign ${encDir}/${DESIGN}.enc

if {[info exists LAYOUT_EXPORT_DURING_FLOW] && $LAYOUT_EXPORT_DURING_FLOW} {
    if {[catch {source scripts/export_multicore_layout.tcl} export_error]} {
        puts "Layout export skipped or failed: $export_error"
    }
}

exit
