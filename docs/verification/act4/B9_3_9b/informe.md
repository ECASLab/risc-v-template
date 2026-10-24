# B.9.3.9b — Auditoría estática UDB/Sail/RTL

> Esta auditoría identifica discrepancias documentales. No constituye validación funcional, síntesis ni certificación.

- Core HEAD: `cf78be1cc7206879744f7587ab9806a508113b24`
- ACT4 HEAD: `d6094ad3ede5268b454197e7bb8eb1cbcbe140d0`
- Extensiones UDB: `I (= 2.1), Sm (= 1.11.0)`
- MXLEN UDB: `64`
- PHYS_ADDR_WIDTH UDB: `56`; physaddr_bits Sail: `32`
- PMA_GRANULARITY UDB: `3`
- Pruebas privilegiadas: `false`
- CSR con direcciones en RTL: 10 (`MSTATUS, MISA, MTVEC, MEPC, MCAUSE, MTVAL, MVENDORID, MARCHID, MIMPID, MHARTID`)

## Regiones Sail
- IOMemory: 0x2000000 a 0x200c000 (fin exclusivo)
- IOMemory: 0xc000000 a 0xc001000 (fin exclusivo)
- IOMemory: 0x10000000 a 0x10001000 (fin exclusivo)
- MainMemory: 0x80000000 a 0x80100000 (fin exclusivo)

## Observaciones a revisar
- Desacuerdo de ancho de dirección física: UDB=56 bits, Sail=32 bits.
- UDB declara Sm sin Zicsr: configuración provisional de pruebas I, no acreditación privilegiada.
- El decoder documenta FENCE como no-op; revisar ordenamiento MMIO por separado.
- PMA_GRANULARITY=3 es un supuesto declarado, pendiente de justificación frente a la plataforma.

## SHA-256 de los archivos inspeccionados
- `core_top.sv`: `cdc92a0bcd5841a14a0e63fb4a5a9eca140c395b1dd853359663277671d491f7`
- `csr_file.sv`: `c26a5497051412a7d1a1ab2fbf7efbbe74a627a805acaa391f912092f9e04a8c`
- `decoder.sv`: `c7a43aa86b9b69ed0d334fb0b225b68d7541f03bc121ef3f9b2a455e8290353f`
- `imem_sync_model.sv`: `9d4a22ab33992d93abce7727cd6ced2ef9914f20404eac807cc40ca5ef818446`
- `dmem_sync_model.sv`: `5e2f7f52c3c4776cb381aa4fd846948fbb1f88f9f24b9250499d6dc775c11a33`
- `tfg-rv64i.yaml`: `056eecbfcd0973cede1464c4e8c19c89e8bfba3627e6decaa07f67d70461a6c1`
- `sail.json`: `c2000c9c85ffde07517fb581e5af520d8709886ea942e15583c30d6a803772ea`
- `test_config.yaml`: `b857bedc54e7a3421d83ffdc789bcaf709a54c70c76b3222c85300b9ee4ddac3`
- `link.ld`: `a58267ba92174cbdc5f5bcbe836d10c99971ce26b894a5d9e5d8f5b76d851a0b`
- `rvmodel_macros.h`: `6e73211b03cd663eb7e511928eba8a5427971cc2e106fc0034e683085e3098fa`
