# Generar firmware desde una implementacion KV260 enrutada.
# No ejecuta sintesis, routing ni programacion fisica.

foreach name {TFG_XPR TFG_OUTPUT_DIR} {
    if {![info exists ::env($name)]} {
        error "Variable requerida ausente: $name"
    }
}

set xpr [file normalize $::env(TFG_XPR)]
set out [file normalize $::env(TFG_OUTPUT_DIR)]

if {![file isfile $xpr]} {
    error "Proyecto XPR no encontrado"
}
if {![file isdirectory $out]} {
    error "Directorio de salida no encontrado"
}

set bitfile [file join $out rv64i_tfg_kv260.bit]
set binfile [file join $out rv64i_tfg_kv260.bin]

if {[file exists $bitfile] || [file exists $binfile]} {
    error "Archivos de salida existentes: no sobrescribir"
}

open_project $xpr

set part [get_property PART [current_project]]
puts "FIRMWARE_PART=$part"

if {$part ne "xck26-sfvc784-2LV-c"} {
    error "Dispositivo FPGA inesperado"
}

set status [get_property STATUS [get_runs impl_1]]
puts "FIRMWARE_IMPL_STATUS=$status"

if {![string match "*route_design Complete!*" $status]} {
    error "La implementacion no completo route_design"
}

open_run impl_1
write_bitstream -bin_file $bitfile

if {![file exists $bitfile] || ![file exists $binfile]} {
    error "Faltan los archivos BIT/BIN"
}

puts "FIRMWARE_BIT_GENERATED"
puts "FIRMWARE_BIN_GENERATED"

close_project

puts "FIRMWARE_GENERATION_PASS"
