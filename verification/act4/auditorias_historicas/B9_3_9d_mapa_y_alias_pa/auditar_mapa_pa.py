#!/usr/bin/env python3
"""Audita direcciones del modelo de plataforma, sin cambiar los originales.
NO infiere la anchura PA global implementada por core_top o FPGA.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

core = Path(os.environ.get('TFG_CORE', '/run/media/saul/Data/Documentos/Linux/TFG_downloads/riscv-core-project/risc-v-template'))
config = Path(os.environ.get('TFG_CONFIG', str(Path.home() / 'TFG_tools/B9_3_7d_primer_elf/config')))
out = Path(sys.argv[1])
files = {
    'core_top': core/'rtl/core/core_top.sv',
    'imem_model': core/'tb/models/imem_sync_model.sv',
    'dmem_model': core/'tb/models/dmem_sync_model.sv',
    'sail': config/'sail.json',
    'udb': config/'tfg-rv64i.yaml',
}
missing=[str(x) for x in files.values() if not x.is_file()]
if missing:
    sys.exit('ERROR: faltan fuentes: ' + ', '.join(missing))
sha={k:hashlib.sha256(v.read_bytes()).hexdigest() for k,v in files.items()}
EXPECTED={
    'core_top':'cdc92a0bcd5841a14a0e63fb4a5a9eca140c395b1dd853359663277671d491f7',
    'imem_model':'9d4a22ab33992d93abce7727cd6ced2ef9914f20404eac807cc40ca5ef818446',
    'dmem_model':'5e2f7f52c3c4776cb381aa4fd846948fbb1f88f9f24b9250499d6dc775c11a33',
    'sail':'c2000c9c85ffde07517fb581e5af520d8709886ea942e15583c30d6a803772ea',
    'udb':'056eecbfcd0973cede1464c4e8c19c89e8bfba3627e6decaa07f67d70461a6c1'
}
changed = [k for k in EXPECTED if sha[k]!=EXPECTED[k]]
if changed:
    sys.exit('ERROR: fuentes cambiaron frente a la auditoria B.9.3.9b/c: '+', '.join(changed) + '. Revisar antes de comparar.')
coretxt=files['core_top'].read_text()
imem=files['imem_model'].read_text()
dmem=files['dmem_model'].read_text()
sail=json.loads(files['sail'].read_text())
udb=files['udb'].read_text()
regions=[]
for r in sail['memory']['regions']:
    base=int(r['base']['value'],0)
    size=int(r['size']['value'],0)
    regions.append({'type':r['attributes']['mem_type'], 'base':f'0x{base:016x}', 'end_exclusive':f'0x{base+size:016x}', 'size_bytes':size})
max_end=max(int(x['end_exclusive'],16) for x in regions)
assert max_end<=2**32, 'Una region Sail requiere mas de 32 bits'
assert re.search(r'output\s+logic\s+\[63:0\]\s+imem_addr',coretxt)
assert re.search(r'output\s+logic\s+\[63:0\]\s+dmem_addr',coretxt)
assert not re.search(r'\binput\s+logic\s+imem_error\b',coretxt), 'Nueva interfaz de error IMEM: revisar conclusiones'
assert 'IMEM model error: dirección fuera de rango' in imem
assert 'request_fault' in dmem and 'addr_in_range' in dmem
assert '((mem_alu_result_out & EXP_MASK) == (EXP_BASE & EXP_MASK))' in coretxt
assert re.search(r'assign\s+addr_offset\s*=\s*addr_i\s*-\s*BASE_ADDR\s*;',dmem)
assert re.search(r'word_index_full\s*<\s*64\'\(MEM_WORDS\)', dmem)
p=int(re.search(r'^\s*PHYS_ADDR_WIDTH:\s*(\d+)\s*$',udb,re.M).group(1))
s=sail['memory']['physaddr_bits']
report={
  'core_git_head':subprocess.run(['git','-C',str(core),'rev-parse','HEAD'],text=True,capture_output=True).stdout.strip(),
  'sha256':sha,'sail_regions':regions,'max_region_end_exclusive':f'0x{max_end:08x}',
  'all_configured_regions_below_4GiB':max_end<=2**32,
  'core_imem_addr_bits':64,'core_dmem_addr_bits':64,
  'core_imem_error_input_present':False,
  'imem_out_of_range_handling':'$fatal en modelo de simulacion: no hay respuesta de fault a core',
  'dmem_out_of_range_handling':'modelo retorna error_o; core tiene dmem_error y traps de acceso de datos',
  'mmio_expansion_decode':'mascara y comparacion de 64 bits',
  'baseline_udb_phys_addr_width':p,'baseline_sail_physaddr_bits':s,
  'candidate_32_56':'ambas aceptadas, pero no prueban implementacion de ancho PA',
  'interpretation':'No hay prueba de que exista un limite PA global en 32 bits. Se observa mapa por debajo de 4GiB y comparaciones a 64 bits. Falta politica de arquitectura/plataforma para fetch fuera de rango.'
}
(out/'auditoria_pa.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
lines=[
 '# B.9.3.9d — Mapa y ausencia de alias en modelo DMEM', '',
 '**Alcance:** auditoría estática del RTL y prueba dirigida del modelo DMEM, no validación PA global ni del silicio/FPGA.',
 '',f'- Core HEAD: `{report["core_git_head"]}`',
 '- Regiones Sail completas dentro de 4 GiB: sí',
 f'- Final exclusivo de la región mayor: `{report["max_region_end_exclusive"]}`',
 '- Interfaces core IMEM/DMEM: 64 bits',
 '- DMEM: compara índices de rango derivados de direccion completa de 64 bits; genera `error_o` fuera de rango.',
 '- IMEM: modelo lanza `$fatal` fuera de rango; core no dispone de entrada `imem_error`.',
 '- MMIO: `EXP_MASK`/`EXP_BASE` comprueban los 64 bits de la direccion.',
 f'- UDB original: {p} bits; Sail original: {s} bits. Ambos archivos no modificados.',
 '', '## Regiones Sail'
]
for r in regions: lines.append(f'- {r["type"]}: {r["base"]} .. {r["end_exclusive"]} (exclusivo)')
lines += ['', '## Interpretación provisional', report['interpretation'],
          'Una prueba PASS del modelo DMEM no demuestra por sí sola la semántica de accesos fuera de rango del núcleo completo.',
          'Para establecer PHYS_ADDR_WIDTH definitivo hay que especificar la plataforma física y definir/resolver cómo se manejan direcciones no implementadas, incluyendo fetch.',
          '', '## SHA-256 observados']
lines.extend(f'- {k}: `{v}`' for k,v in sha.items())
(out/'informe.md').write_text('\n'.join(lines)+'\n')
print('PASS: fuentes originales coinciden con B.9.3.9b/c')
print('PASS: todas las regiones Sail caben en 32 bits; limite superior exclusivo:',report['max_region_end_exclusive'])
print('PASS: interfaces de direccion de core_top son de 64 bits')
print('ATENCION: modelo IMEM usa $fatal fuera de rango y core_top no tiene imem_error')
print('ATENCION: esto NO determina PHYS_ADDR_WIDTH del hardware')
print('REPORTE:',out/'informe.md')
