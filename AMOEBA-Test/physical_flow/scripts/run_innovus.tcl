# Minimal Innovus flow for DC-synthesized AMOEBA handoff.

source scripts/lib_setup.tcl
source scripts/design_setup.tcl
source scripts/report_utils.tcl

setMultiCpuUsage -localCpu $INNOVUS_CPUS

if {![file exists $NETLIST]} {
    puts stderr "Netlist not found: $NETLIST. Run scripts/run_dc.sh first."
    exit 1
}
if {![file exists $SDC_FILE]} {
    puts stderr "SDC not found: $SDC_FILE. Run scripts/run_dc.sh first."
    exit 1
}

source scripts/mmmc_setup.tcl

set rptDir "summaryReport"
set encDir "enc"
set defDir "def"
foreach dir [list $rptDir $encDir $defDir timingReports reports] {
    if {![file exists $dir]} {
        exec mkdir -p $dir
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

setFPlanMode -snapBlockGrid LayerTrack
floorPlan -site $SITE -r 1.0 $FP_UTIL $FP_MARGIN $FP_MARGIN $FP_MARGIN $FP_MARGIN

setDesignMode -topRoutingLayer $TOP_ROUTING_LAYER
setDesignMode -bottomRoutingLayer 2

echo "Physical Design Stage, Core Area (um^2), Standard Cell Area (um^2), Macro Area (um^2), Total Power, Wirelength(um)" > ${DESIGN}_DETAILS.rpt
set rpt_post_synth [extract_report postSynth]
echo "$rpt_post_synth" >> ${DESIGN}_DETAILS.rpt

defOut -floorplan ${defDir}/${DESIGN}_fp.def
saveNetlist -removePowerGround ${defDir}/${TOP_MODULE}_post_init.v
saveDesign ${encDir}/${DESIGN}_init.enc

place_opt_design -out_dir $rptDir -prefix place
optDesign -preCTS
saveDesign ${encDir}/${DESIGN}_placed.enc
defOut -floorplan -placement ${defDir}/${DESIGN}_placed.def

set rpt_pre_cts [extract_report preCTS]
echo "$rpt_pre_cts" >> ${DESIGN}_DETAILS.rpt

create_ccopt_clock_tree_spec
ccopt_design

set_interactive_constraint_modes [all_constraint_modes -active]
set_propagated_clock [all_clocks]
set_clock_propagation propagated
optDesign -postCTS

saveDesign ${encDir}/${DESIGN}_cts.enc
set rpt_post_cts [extract_report postCTS]
echo "$rpt_post_cts" >> ${DESIGN}_DETAILS.rpt

setNanoRouteMode -drouteVerboseViolationSummary 1
setNanoRouteMode -routeWithSiDriven true
setNanoRouteMode -routeWithTimingDriven true
setNanoRouteMode -routeUseAutoVia true
setNanoRouteMode -drouteAutoStop false

routeDesign
saveDesign ${encDir}/${DESIGN}_route.enc
defOut -netlist -floorplan -routing ${defDir}/${DESIGN}_route.def

verify_connectivity -error 0 -geom_connect -no_antenna
verify_drc -limit 0

set rpt_post_route [extract_report postRoute]
echo "$rpt_post_route" >> ${DESIGN}_DETAILS.rpt

optDesign -postRoute

set rpt_post_route_opt [extract_report postRouteOpt]
echo "$rpt_post_route_opt" >> ${DESIGN}_DETAILS.rpt

verify_connectivity -error 0 -geom_connect -no_antenna
verify_drc -limit 0

summaryReport -noHtml -outfile ${rptDir}/post_route.sum
defOut -netlist -floorplan -routing ${defDir}/${DESIGN}.def
saveNetlist -removePowerGround ${defDir}/${TOP_MODULE}_post_route.v
saveDesign ${encDir}/${DESIGN}.enc

exit
