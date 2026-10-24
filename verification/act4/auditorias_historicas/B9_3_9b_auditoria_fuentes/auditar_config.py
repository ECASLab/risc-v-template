#!/usr/bin/env python3
"""Auditoría estática, de solo lectura, para UDB/Sail/RTL del TFG.
No verifica conformidad arquitectural ni modifica el diseño.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

CORE = Path(os.environ.get('TFG_CORE', '/run/media/saul/Data/Documentos/Linux/TFG_downloads/riscv-core-project/risc-v-template'))
ACT4 = Path(os.environ.get('TFG_ACT4', str(Path.home() / 'TFG_tools/riscv-arch-test')))
CONFIG = Path(os.environ.get('TFG_CONFIG', str(Path.home() / 'TFG_tools/B9_3_7d_primer_elf/config')))
OUT = Path(os.environ.get('TFG_REPORT', str(Path.home() / 'TFG_tools/B9_3_9b_auditoria')))
OUT.mkdir(parents=True, exist_ok=True)
COPY = OUT / 'fuentes'; COPY.mkdir(exist_ok=True)

inputs = {
    'core_top.sv': CORE / 'rtl/core/core_top.sv',
    'csr_file.sv': CORE / 'rtl/core/csr_file.sv',
    'decoder.sv': CORE / 'rtl/core/decoder.sv',
    'imem_sync_model.sv': CORE / 'tb/models/imem_sync_model.sv',
    'dmem_sync_model.sv': CORE / 'tb/models/dmem_sync_model.sv',
    'tfg-rv64i.yaml': CONFIG / 'tfg-rv64i.yaml',
    'sail.json': CONFIG / 'sail.json',
    'test_config.yaml': CONFIG / 'test_config.yaml',
    'link.ld': CONFIG / 'link.ld',
    'rvmodel_macros.h': CONFIG / 'rvmodel_macros.h',
}
missing = [f'{name}: {path}' for name,path in inputs.items() if not path.is_file()]
if missing:
    print('ERROR: faltan archivos para la auditoría:')
    print('\n'.join(missing)); sys.exit(2)

content = {}
hashes = {}
for name, path in inputs.items():
    data = path.read_bytes()
    hashes[name] = hashlib.sha256(data).hexdigest()
    (COPY / name).write_bytes(data)
    content[name] = data.decode('utf-8', errors='replace')

udb, test, core, csr, dec = [content[k] for k in ('tfg-rv64i.yaml', 'test_config.yaml', 'core_top.sv', 'csr_file.sv', 'decoder.sv')]
sail = json.loads(content['sail.json'])

def field(text, key):
    m = re.search(r'^\s*'+re.escape(key)+r'\s*:\s*([^#\r\n]+)', text, re.M)
    return m.group(1).strip() if m else None

def githead(path):
    try:
        r = subprocess.run(['git', '-C', str(path), 'rev-parse', 'HEAD'], capture_output=True, text=True, check=True)
        return r.stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None

exts = dict(re.findall(r'\{\s*name:\s*([A-Za-z0-9]+),\s*version:\s*"([^"]+)"', udb))
csrs = dict(re.findall(r'localparam\s+logic\s+\[11:0\]\s+CSR_([A-Z0-9]+)\s*=\s*12\'h([0-9a-fA-F]+)', csr))
phys_udb = field(udb, 'PHYS_ADDR_WIDTH')
phys_sail = sail.get('memory',{}).get('physaddr_bits')
pma = field(udb, 'PMA_GRANULARITY')
regions=[]
for reg in sail.get('memory',{}).get('regions',[]):
    b=int(reg['base']['value'],0); n=int(reg['size']['value'],0)
    regions.append({'type':reg['attributes']['mem_type'],'base':hex(b),'size':hex(n),'end_exclusive':hex(b+n)})

warnings=[]
if phys_udb is None or phys_sail is None: warnings.append('Falta el campo de ancho físico en UDB o Sail.')
elif int(phys_udb,0)!=int(phys_sail):
    warnings.append(f'Desacuerdo de ancho de dirección física: UDB={phys_udb} bits, Sail={phys_sail} bits.')
if field(test, 'include_priv_tests') not in ('false','False'):
    warnings.append('include_priv_tests no está explícitamente desactivado.')
if 'Sm' in exts and 'Zicsr' not in exts:
    warnings.append('UDB declara Sm sin Zicsr: configuración provisional de pruebas I, no acreditación privilegiada.')
if 'OPCODE_MISC_MEM' in dec and re.search(r'FENCE[^\n]*no-op', dec, re.I):
    warnings.append('El decoder documenta FENCE como no-op; revisar ordenamiento MMIO por separado.')
if 'csr_mstatus' not in core.lower() and 'csr_file' not in core:
    warnings.append('No se encontró referencia esperada al bloque CSR en core_top.')
if pma is not None:
    warnings.append(f'PMA_GRANULARITY={pma} es un supuesto declarado, pendiente de justificación frente a la plataforma.')

report={
  'core_head': githead(CORE), 'act4_head':githead(ACT4),
  'paths':{'core':str(CORE),'act4':str(ACT4),'config':str(CONFIG)},
  'sha256':hashes, 'extensions_udb':exts, 'udb':{
     'MXLEN':field(udb,'MXLEN'), 'PHYS_ADDR_WIDTH':phys_udb,
     'PMA_GRANULARITY':pma, 'NUM_PMP_ENTRIES':field(udb,'NUM_PMP_ENTRIES'),
     'MISALIGNED_LDST':field(udb,'MISALIGNED_LDST'),
     'MTVEC_MODES':field(udb,'MTVEC_MODES')},
  'sail':{'physaddr_bits':phys_sail, 'regions':regions},
  'test_config':{'include_priv_tests':field(test,'include_priv_tests'),'name':field(test,'name')},
  'csr_rtl_addresses':{k:'0x'+v.lower() for k,v in csrs.items()},
  'rtl_address_bus':{'imem_addr_64': bool(re.search(r'output\s+logic\s+\[63:0\]\s+imem_addr',core)),
                     'dmem_addr_64': bool(re.search(r'output\s+logic\s+\[63:0\]\s+dmem_addr',core))},
  'warnings':warnings
}
(OUT/'resultado.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n',encoding='utf8')
lines=[
 '# B.9.3.9b — Auditoría estática UDB/Sail/RTL',
 '',
 '> Esta auditoría identifica discrepancias documentales. No constituye validación funcional, síntesis ni certificación.',
 '',
 f"- Core HEAD: `{report['core_head']}`",
 f"- ACT4 HEAD: `{report['act4_head']}`",
 f"- Extensiones UDB: `{', '.join(f'{k} ({v})' for k,v in exts.items())}`",
 f"- MXLEN UDB: `{report['udb']['MXLEN']}`",
 f"- PHYS_ADDR_WIDTH UDB: `{phys_udb}`; physaddr_bits Sail: `{phys_sail}`",
 f"- PMA_GRANULARITY UDB: `{pma}`",
 f"- Pruebas privilegiadas: `{report['test_config']['include_priv_tests']}`",
 f"- CSR con direcciones en RTL: {len(csrs)} (`{', '.join(csrs)}`)",
 '', '## Regiones Sail',
 *[f"- {r['type']}: {r['base']} a {r['end_exclusive']} (fin exclusivo)" for r in regions],
 '', '## Observaciones a revisar',
 *[f'- {w}' for w in warnings],
 '', '## SHA-256 de los archivos inspeccionados',
 *[f'- `{k}`: `{v}`' for k,v in hashes.items()]
]
(OUT/'informe.md').write_text('\n'.join(lines)+'\n',encoding='utf8')
print('PASS: auditoría estática de archivos actuales completada')
print('CORE HEAD:',report['core_head'])
print('ACT4 HEAD:',report['act4_head'])
print('Extensiones UDB:', ', '.join(exts))
print('CSR definidos en RTL:',len(csrs))
print('PHYS_ADDR_WIDTH UDB:',phys_udb)
print('physaddr_bits Sail:',phys_sail)
print('PMA_GRANULARITY UDB:',pma)
print('Pruebas privilegiadas:',report['test_config']['include_priv_tests'])
for w in warnings: print('REVISAR:',w)
print('REPORTE:', OUT / 'informe.md')
