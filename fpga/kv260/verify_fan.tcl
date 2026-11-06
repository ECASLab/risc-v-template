open_project $::env(TFG_XPR)
set st [get_property STATUS [get_runs impl_1]]
puts "IMPL_STATUS=$st"
if {![string match "*route_design Complete!*" $st]} {
    error "Implementación no completada sin fallo temporal: $st"
}
open_run impl_1
set fan [get_ports -quiet fan_en_b]
if {[llength $fan] != 1} {error "FAN_PORT_MISSING"}
set pin [get_property PACKAGE_PIN $fan]
set std [get_property IOSTANDARD $fan]
puts "FAN_PIN=$pin"
puts "FAN_IOSTANDARD=$std"
if {$pin ne "A12" || $std ne "LVCMOS33"} {error "FAN_CONSTRAINT_MISMATCH"}
set clk [get_clocks -quiet clk_pl_0]
if {[llength $clk] != 1} {error "Falta clk_pl_0"}
set period [get_property PERIOD $clk]
puts "PL_CLOCK_PERIOD_NS=$period"
if {[expr {abs(double($period)-17.0)}] > 0.01} {error "Frecuencia inesperada"}
set paths [get_timing_paths -setup -max_paths 1]
if {[llength $paths] != 1} {error "No hay caminos de setup"}
set wns [get_property SLACK [lindex $paths 0]]
puts "FINAL_WNS_NS=$wns"
if {[expr {double($wns) < 0.0}]} {error "SETUP_TIMING_FAIL"}
report_drc -file [file join $::env(TFG_AUDIT_DIR) final_drc.rpt]
set violations [get_drc_violations -quiet *]
puts "DRC_VIOLATIONS=[llength $violations]"
if {[llength $violations] != 0} {error "DRC_FAIL"}
report_timing_summary -report_unconstrained -file [file join $::env(TFG_AUDIT_DIR) final_timing.rpt]
puts "P2_8_5_FAN_IMPL_PASS"
puts "P2_8_5_NO_BITSTREAM"
close_project
exit
