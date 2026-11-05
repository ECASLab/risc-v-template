# TFG P2.6.3 - Reproduccion de P2.6.2 sin dependencias externas al repositorio.
# Solo sintesis out-of-context, NUNCA implementacion ni bitstream.
if {![info exists ::env(TFG_REPO)]} {error "Falta TFG_REPO"}
set repo $::env(TFG_REPO)
set rtl [lsort [glob -directory [file join $repo rtl core] *.sv]]
if {[llength $rtl] != 18} {error "Se esperaban 18 archivos core RTL"}
read_verilog -sv $rtl
read_verilog -sv [file join $repo rtl platform rv64i_platform_ram.sv]
read_verilog -sv [file join $repo rtl platform rv64i_platform_top.sv]
auto_detect_xpm
set_param general.maxThreads 4
synth_design -top rv64i_platform_top -part xck26-sfvc784-2LV-c -mode out_of_context -flatten_hierarchy none
report_utilization -file integrated_utilization.rpt
set uc [get_cells -hier -quiet -filter {REF_NAME =~ URAM288*}]
set bc [get_cells -hier -quiet -filter {REF_NAME =~ RAMB36* || REF_NAME =~ RAMB18*}]
puts "INTEGRATED_URAM_COUNT=[llength $uc]"
puts "INTEGRATED_BRAM_COUNT=[llength $bc]"
if {[llength $uc] != 32} {error "Cantidad inesperada de UltraRAM"}
if {[llength $bc] != 0} {error "BRAM no prevista en el core integrado"}
write_checkpoint integrated_top_synth.dcp
puts "P2_6_3_SYNTH_PASS"
exit
