# P2.7.1: sintesis OOC 1 MiB del SoC AXI4-Lite para K26.
# No crea proyecto de bloques ni bitstream; nunca programa hardware.
if {![info exists ::env(TFG_REPO)] || ![info exists ::env(P27_PKG)]} {
    error "Falta TFG_REPO/P27_PKG"
}
set repo $::env(TFG_REPO)
set pkg $::env(P27_PKG)
set rtl [lsort [glob -directory [file join $repo rtl core] *.sv]]
if {[llength $rtl] != 18} {error "Se esperaban 18 archivos core RTL"}
read_verilog -sv $rtl
read_verilog -sv [file join $repo rtl platform rv64i_platform_ram.sv]
read_verilog -sv [file join $pkg rtl platform rv64i_platform_top.sv]
read_verilog -sv [file join $pkg rtl platform rv64i_axi_supervisor.sv]
read_verilog -sv [file join $pkg rtl platform rv64i_soc_axi_top.sv]
read_verilog [file join $pkg rtl platform rv64i_soc_axi_bd_wrapper.v]
auto_detect_xpm
set_param general.maxThreads 4
synth_design -top rv64i_soc_axi_bd_wrapper -part xck26-sfvc784-2LV-c -mode out_of_context -flatten_hierarchy none
report_utilization -file p27_axi_soc_utilization.rpt
set uc [get_cells -hier -quiet -filter {REF_NAME =~ URAM288*}]
set bc [get_cells -hier -quiet -filter {REF_NAME =~ RAMB36* || REF_NAME =~ RAMB18*}]
puts "AXI_SOC_URAM_COUNT=[llength $uc]"
puts "AXI_SOC_BRAM_COUNT=[llength $bc]"
if {[llength $uc] != 32} {error "Memoria no ocupa 32 UltraRAM"}
if {[llength $bc] != 0} {error "BRAM inesperada en SoC"}
write_checkpoint p27_axi_soc_synth.dcp
puts "P2_7_1_SYNTH_PASS"
exit
