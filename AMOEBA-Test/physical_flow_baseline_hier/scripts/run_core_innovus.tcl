# Harden one 2x2-CGRA core as an Innovus macro.

source scripts/lib_setup.tcl
source scripts/design_setup.tcl
source scripts/report_utils.tcl
source scripts/placement_utils.tcl
source $MODULE_NAMES_TCL

setMultiCpuUsage -localCpu $INNOVUS_CPUS

if {![file exists $CORE_NETLIST]} {
    puts stderr "Core netlist not found: $CORE_NETLIST. Run scripts/run_dc_hier.sh first."
    exit 1
}
if {![file exists $CORE_SDC]} {
    puts stderr "Core SDC not found: $CORE_SDC. Run scripts/run_dc_hier.sh first."
    exit 1
}

set SDC_FILE $CORE_SDC
source scripts/mmmc_setup.tcl

set rptDir "summaryReport/core"
set encDir "enc/core"
set defDir "def/core"
foreach dir [list $rptDir $encDir $defDir timingReports reports] {
    if {![file exists $dir]} {
        exec mkdir -p $dir
    }
}

set init_pwr_net VDD
set init_gnd_net VSS
set init_verilog $CORE_NETLIST
set init_design_netlisttype "Verilog"
set init_design_settop 1
set init_top_cell $CORE_MODULE
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

setGenerateViaMode -auto true
generateVias

createBasicPathGroups -expanded

proc get_available_sites {} {
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

proc get_macro_sites_from_lefs {lef_files} {
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

proc resolve_floorplan_site {configured_site lef_files} {
    set available_sites [get_available_sites]
    puts "Innovus available placement sites: $available_sites"

    if {$configured_site ne "" &&
        [lsearch -exact $available_sites $configured_site] >= 0} {
        return $configured_site
    }

    set macro_sites [get_macro_sites_from_lefs $lef_files]
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

set FLOORPLAN_SITE [resolve_floorplan_site $SITE $lefs]
setFPlanMode -snapBlockGrid LayerTrack
floorPlan -site $FLOORPLAN_SITE -r 1.0 $FP_UTIL $FP_MARGIN $FP_MARGIN $FP_MARGIN $FP_MARGIN
amoeba_place_boundary_pins

setDesignMode -topRoutingLayer $TOP_ROUTING_LAYER
setDesignMode -bottomRoutingLayer 2

echo "Physical Design Stage, Core Area (um^2), Standard Cell Area (um^2), Macro Area (um^2), Total Power, Wirelength(um)" > ${CORE_DESIGN}_DETAILS.rpt
set rpt_post_synth [extract_report postSynth]
echo "$rpt_post_synth" >> ${CORE_DESIGN}_DETAILS.rpt

defOut -floorplan ${defDir}/${CORE_DESIGN}_fp.def
saveDesign ${encDir}/${CORE_DESIGN}_init.enc

place_opt_design -out_dir $rptDir -prefix core_place
optDesign -preCTS
saveDesign ${encDir}/${CORE_DESIGN}_placed.enc
defOut -floorplan -placement ${defDir}/${CORE_DESIGN}_placed.def

set rpt_pre_cts [extract_report preCTS]
echo "$rpt_pre_cts" >> ${CORE_DESIGN}_DETAILS.rpt

create_ccopt_clock_tree_spec
ccopt_design

set_interactive_constraint_modes [all_constraint_modes -active]
set_propagated_clock [all_clocks]
set_clock_propagation propagated
optDesign -postCTS

saveDesign ${encDir}/${CORE_DESIGN}_cts.enc
set rpt_post_cts [extract_report postCTS]
echo "$rpt_post_cts" >> ${CORE_DESIGN}_DETAILS.rpt

setNanoRouteMode -drouteVerboseViolationSummary 1
setNanoRouteMode -routeWithSiDriven true
setNanoRouteMode -routeWithTimingDriven true
setNanoRouteMode -routeUseAutoVia true
setNanoRouteMode -routeWithViaInPin "1:1"
setNanoRouteMode -routeWithViaOnlyForStandardCellPin "1:1"
setNanoRouteMode -drouteOnGridOnly "via 1:1"
setNanoRouteMode -drouteAutoStop false
setNanoRouteMode -drouteExpAdvancedMarFix true
setNanoRouteMode -routeExpAdvancedTechnology true
setNanoRouteMode -grouteExpWithTimingDriven false

routeDesign
saveDesign ${encDir}/${CORE_DESIGN}_route.enc
defOut -netlist -floorplan -routing $CORE_DEF

setViaGenMode -reset
catch {editPowerVia -top_layer M2 -bottom_layer M1 -orthogonal_only 0 -add_vias 1}

verify_connectivity -error 0 -geom_connect -no_antenna
verify_drc -limit 0

set rpt_post_route [extract_report postRoute]
echo "$rpt_post_route" >> ${CORE_DESIGN}_DETAILS.rpt

optDesign -postRoute

set rpt_post_route_opt [extract_report postRouteOpt]
echo "$rpt_post_route_opt" >> ${CORE_DESIGN}_DETAILS.rpt

verify_connectivity -error 0 -geom_connect -no_antenna
verify_drc -limit 0

summaryReport -noHtml -outfile ${rptDir}/post_route.sum
write_area_breakdown_csv reports/innovus_core_area_breakdown.csv
write_tile_area_breakdown_csv reports/innovus_core_tile_area_breakdown.csv
defOut -netlist -floorplan -routing $CORE_DEF
saveNetlist -removePowerGround ${defDir}/${CORE_MODULE}_post_route.v
lefOut $CORE_LEF
saveDesign ${encDir}/${CORE_DESIGN}.enc

exit
