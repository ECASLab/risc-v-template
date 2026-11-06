# P2.8.1: crear BD de KV260 PS + SmartConnect + RV64I AXI en proyecto AISLADO.
# No programar placa, no sintetizar, no generar bitstream, no exportar XSA.
if {![info exists ::env(TFG_REPO)] || ![info exists ::env(P28_PKG)]} {
    error "Variables TFG_REPO/P28_PKG ausentes"
}
set repo [file normalize $::env(TFG_REPO)]
set pkg [file normalize $::env(P28_PKG)]
set project_dir [file normalize [file join [pwd] vivado_project]]
set part_name "xck26-sfvc784-2LV-c"
set board_name "xilinx.com:kv260_som:part0:1.4"

set rtl_core [lsort [glob -nocomplain -directory [file join $repo rtl core] *.sv]]
if {[llength $rtl_core] != 18} { error "No hay 18 archivos core RTL" }
set rtl_platform [list \
    [file join $repo rtl platform rv64i_platform_ram.sv] \
    [file join $repo rtl platform rv64i_platform_top.sv] \
    [file join $repo rtl platform rv64i_axi_supervisor.sv] \
    [file join $repo rtl platform rv64i_soc_axi_top.sv]]
foreach f [concat $rtl_core $rtl_platform [list [file join $pkg rv64i_soc_axi_bd_wrapper_ipi.v]]] {
    if {![file exists $f]} {error "Falta fuente: $f"}
}

create_project rv64i_kv260_ps_pl $project_dir -part $part_name
if {[llength [get_board_parts -quiet $board_name]] != 1} {
    error "Falta board part $board_name en Vivado 2024.1. No se crea un preset alternativo."
}
set_property board_part $board_name [current_project]
# Restricciones oficiales KV260 para la salida de control del ventilador.
set fan_xdc [file join $pkg kv260_fan.xdc]
if {![file exists $fan_xdc]} {error "Falta XDC ventilador"}
add_files -fileset constrs_1 -norecurse $fan_xdc
puts "FAN_XDC=$fan_xdc"

set_property target_language Verilog [current_project]
set_param general.maxThreads 4

add_files -norecurse [concat $rtl_core $rtl_platform [list [file join $pkg rv64i_soc_axi_bd_wrapper_ipi.v]]]
update_compile_order -fileset sources_1

auto_detect_xpm
create_bd_design "system"
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 ps_0]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} $ps

# Preservar control del ventilador KV260: PS TTC0 waveout[2] -> HDA20/A12.
# Habilitación explícita PS TTC0/EMIO, sin generar un PWM alternativo en PL.
set_property -dict [list \
    CONFIG.PSU__TTC0__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__TTC0__WAVEOUT__ENABLE {1} \
    CONFIG.PSU__TTC0__WAVEOUT__IO {EMIO}] [get_bd_cells ps_0]

if {[llength [get_bd_pins -quiet ps_0/emio_ttc0_wave_o]] != 1} {
    error "No existe ps_0/emio_ttc0_wave_o: verificar TTC0/EMIO"
}
set fan_slice [create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 fan_slice]
set_property -dict [list CONFIG.DIN_WIDTH {3} CONFIG.DIN_FROM {2} CONFIG.DIN_TO {2}] $fan_slice
create_bd_port -dir O fan_en_b
connect_bd_net [get_bd_pins ps_0/emio_ttc0_wave_o] [get_bd_pins fan_slice/Din]
connect_bd_net [get_bd_pins fan_slice/Dout] [get_bd_ports fan_en_b]
puts "FAN_BD_ROUTE=TTC0_WAVEOUT_2_TO_FAN_EN_B"

# P2.8.5: conservar frecuencia físicamente validada (solicitar 60 MHz).
set_property -dict [list CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {60}] [get_bd_cells ps_0]
puts "PL0_REQUESTED_MHZ=[get_property CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ [get_bd_cells ps_0]]"

# HPM0 FPD: maestro del ARM hacia el supervisor. No habilitar otros puertos por rutina.
set_property -dict [list CONFIG.PSU__USE__M_AXI_GP0 {1} CONFIG.PSU__USE__M_AXI_GP1 {0}] [get_bd_cells ps_0]
if {[llength [get_bd_intf_pins -quiet ps_0/M_AXI_HPM1_FPD]] != 0} {
    error "HPM1 sigue habilitado"
}

set sc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 sc_0]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $sc
set rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_pl]
set rst_inv [create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 rst_inv]
set_property -dict [list CONFIG.C_OPERATION {not} CONFIG.C_SIZE {1}] $rst_inv
set const_one [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_one]
set_property -dict [list CONFIG.CONST_VAL {1} CONFIG.CONST_WIDTH {1}] $const_one
set const_zero [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_zero]
set_property -dict [list CONFIG.CONST_VAL {0} CONFIG.CONST_WIDTH {1}] $const_zero

set soc [create_bd_cell -type module -reference rv64i_soc_axi_bd_wrapper soc_0]
if {[llength [get_bd_intf_pins -quiet soc_0/S_AXI]] != 1} {
    puts "SOC_INTERFACES=[get_bd_intf_pins -of_objects $soc]"
    error "No se infirio S_AXI. Revisar los atributos X_INTERFACE_INFO."
}
foreach pin {ps_0/M_AXI_HPM0_FPD sc_0/S00_AXI sc_0/M00_AXI soc_0/S_AXI} {
    if {[llength [get_bd_intf_pins -quiet $pin]] != 1} {error "Falta AXI interface: $pin"}
}
connect_bd_intf_net [get_bd_intf_pins ps_0/M_AXI_HPM0_FPD] [get_bd_intf_pins sc_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins sc_0/M00_AXI] [get_bd_intf_pins soc_0/S_AXI]

# El ARM aporta el mismo reloj para puente AXI, RAM y procesador RV64I.
set c [get_bd_pins ps_0/pl_clk0]
foreach p {sc_0/aclk soc_0/s_axi_aclk rst_pl/slowest_sync_clk ps_0/maxihpm0_fpd_aclk} {
    if {[llength [get_bd_pins -quiet $p]] != 1} {error "Falta pin reloj: $p"}
    connect_bd_net $c [get_bd_pins $p]
}
connect_bd_net [get_bd_pins ps_0/pl_resetn0] [get_bd_pins rst_inv/Op1]
connect_bd_net [get_bd_pins rst_inv/Res] [get_bd_pins rst_pl/ext_reset_in]

set ext_reset_high [get_property CONFIG.C_EXT_RESET_HIGH [get_bd_cells rst_pl]]
puts "RESET_EXT_ACTIVE_HIGH=$ext_reset_high"
if {$ext_reset_high ne "1"} {
    error "Polaridad inesperada en rst_pl: $ext_reset_high"
}
connect_bd_net [get_bd_pins const_one/dout] [get_bd_pins rst_pl/dcm_locked]
connect_bd_net [get_bd_pins const_zero/dout] [get_bd_pins rst_pl/mb_debug_sys_rst]
connect_bd_net [get_bd_pins rst_pl/peripheral_aresetn] [get_bd_pins soc_0/s_axi_aresetn]
connect_bd_net [get_bd_pins rst_pl/interconnect_aresetn] [get_bd_pins sc_0/aresetn]

# Dirección de control vista por ARM, distinta del mapa MMIO interno del RV64I.
set segs [get_bd_addr_segs -quiet -of_objects [get_bd_intf_pins soc_0/S_AXI]]
puts "SOC_ADDR_SEGS=$segs"
if {[llength $segs] != 1} {error "Se esperaba exactamente un segmento AXI del supervisor"}
assign_bd_address -offset 0xA0000000 -range 4K \
    -target_address_space [get_bd_addr_spaces ps_0/Data] $segs

validate_bd_design
save_bd_design
current_bd_design system
set system_bd_path [file join $project_dir rv64i_kv260_ps_pl.srcs sources_1 bd system system.bd]
set bdfile [get_files -quiet $system_bd_path]
if {[llength $bdfile] != 1} {
    error "No se identifico el BD principal: $system_bd_path"
}
puts "MAIN_BD=$bdfile"
write_bd_tcl -force [file join [pwd] generated_system_bd.tcl]

set fp [open [file join [pwd] bd_summary.txt] w]
puts $fp "PART=$part_name"
puts $fp "BOARD=$board_name"
puts $fp "AXI_CONTROL_BASE=0xA0000000"
puts $fp "AXI_CONTROL_RANGE=4K"
puts $fp "PS_MASTER=ps_0/M_AXI_HPM0_FPD"
puts $fp "PL_CLOCK=ps_0/pl_clk0"
puts $fp "PL_RESET=ps_0/pl_resetn0 -> rst_inv -> rst_pl -> soc_0/s_axi_aresetn"
puts $fp "BD_CELLS=[get_bd_cells]"
puts $fp "ADDRESS_SEGMENT=$segs"
close $fp
puts "P2_8_1_BD_VALIDATED"
puts "P2_8_1_NO_BITSTREAM"
puts "PROJECT_DIR=$project_dir"
close_project
exit
