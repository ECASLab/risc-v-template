# B.9.3.9d — Mapa y ausencia de alias en modelo DMEM

**Alcance:** auditoría estática del RTL y prueba dirigida del modelo DMEM, no validación PA global ni del silicio/FPGA.

- Core HEAD: `cf78be1cc7206879744f7587ab9806a508113b24`
- Regiones Sail completas dentro de 4 GiB: sí
- Final exclusivo de la región mayor: `0x80100000`
- Interfaces core IMEM/DMEM: 64 bits
- DMEM: compara índices de rango derivados de direccion completa de 64 bits; genera `error_o` fuera de rango.
- IMEM: modelo lanza `$fatal` fuera de rango; core no dispone de entrada `imem_error`.
- MMIO: `EXP_MASK`/`EXP_BASE` comprueban los 64 bits de la direccion.
- UDB original: 56 bits; Sail original: 32 bits. Ambos archivos no modificados.

## Regiones Sail
- IOMemory: 0x0000000002000000 .. 0x000000000200c000 (exclusivo)
- IOMemory: 0x000000000c000000 .. 0x000000000c001000 (exclusivo)
- IOMemory: 0x0000000010000000 .. 0x0000000010001000 (exclusivo)
- MainMemory: 0x0000000080000000 .. 0x0000000080100000 (exclusivo)

## Interpretación provisional
No hay prueba de que exista un limite PA global en 32 bits. Se observa mapa por debajo de 4GiB y comparaciones a 64 bits. Falta politica de arquitectura/plataforma para fetch fuera de rango.
Una prueba PASS del modelo DMEM no demuestra por sí sola la semántica de accesos fuera de rango del núcleo completo.
Para establecer PHYS_ADDR_WIDTH definitivo hay que especificar la plataforma física y definir/resolver cómo se manejan direcciones no implementadas, incluyendo fetch.

## SHA-256 observados
- core_top: `cdc92a0bcd5841a14a0e63fb4a5a9eca140c395b1dd853359663277671d491f7`
- imem_model: `9d4a22ab33992d93abce7727cd6ced2ef9914f20404eac807cc40ca5ef818446`
- dmem_model: `5e2f7f52c3c4776cb381aa4fd846948fbb1f88f9f24b9250499d6dc775c11a33`
- sail: `c2000c9c85ffde07517fb581e5af520d8709886ea942e15583c30d6a803772ea`
- udb: `056eecbfcd0973cede1464c4e8c19c89e8bfba3627e6decaa07f67d70461a6c1`
