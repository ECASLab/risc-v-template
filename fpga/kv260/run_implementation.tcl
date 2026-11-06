# TFG P2.8.2 - Implementacion fisica sin bitstream
# Vivado 2024.1 / Kria KV260

set_param general.maxThreads 4

open_project $::env(TFG_XPR)

set output_dir [pwd]
set project_dir [file dirname $::env(TFG_XPR)]

# Comprobar el dispositivo seleccionado.
set part_name [get_property PART [current_project]]
puts "PART=$part_name"

if {$part_name ne "xck26-sfvc784-2LV-c"} {
    error "Dispositivo FPGA inesperado"
}

# Seleccionar unicamente el BD principal.
set bd_path [file join $project_dir \
    rv64i_kv260_ps_pl.srcs sources_1 bd system system.bd]

set bdfile [get_files -quiet $bd_path]

if {[llength $bdfile] != 1} {
    error "No se encontro system.bd"
}

# Generar productos y wrapper HDL.
generate_target all $bdfile

set wrapper [make_wrapper -files $bdfile -top]

if {[llength $wrapper] != 1} {
    error "No se pudo generar system_wrapper"
}

add_files -norecurse $wrapper
set_property top system_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

puts "P2_8_2_WRAPPER_READY"

# Primera etapa: sintesis completa.
launch_runs synth_1 -jobs 2
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "SYNTH_STATUS=$synth_status"

if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "La sintesis no termino correctamente"
}

open_run synth_1

set clocks [get_clocks -quiet *]
puts "SYNTH_CLOCK_COUNT=[llength $clocks]"

if {[llength $clocks] == 0} {
    error "No hay relojes definidos para timing"
}

report_utilization \
    -file [file join $output_dir synth_utilization.rpt]

check_timing \
    -file [file join $output_dir synth_check_timing.rpt]

report_timing_summary -report_unconstrained \
    -file [file join $output_dir synth_timing.rpt]

puts "P2_8_2_SYNTH_REPORTS_READY"
close_design

# Segunda etapa: implementacion hasta routing.
# NO ejecutar write_bitstream.
launch_runs impl_1 -to_step route_design -jobs 2
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "IMPL_STATUS=$impl_status"

if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "La implementacion no termino correctamente"
}

open_run impl_1

report_utilization \
    -file [file join $output_dir impl_utilization.rpt]

report_timing_summary -report_unconstrained \
    -file [file join $output_dir impl_timing.rpt]

check_timing \
    -file [file join $output_dir impl_check_timing.rpt]

report_drc \
    -file [file join $output_dir impl_drc.rpt]

report_route_status \
    -file [file join $output_dir impl_route_status.rpt]

report_methodology \
    -file [file join $output_dir impl_methodology.rpt]

set worst_path [get_timing_paths -setup -max_paths 1]

if {[llength $worst_path] > 0} {
    puts "ROUTED_WNS_NS=[get_property SLACK [lindex $worst_path 0]]"
} else {
    puts "ROUTED_WNS_NS=UNAVAILABLE"
}

puts "P2_8_2_ROUTED_REPORTS_READY"
puts "P2_8_2_NO_BITSTREAM"

close_project
exit
