#!/usr/bin/env python3
"""B.9.3.9g: matriz de cobertura histórica del subconjunto CSR y traps, SOLO LECTURA."""
import argparse, csv, hashlib, json, re, subprocess, tarfile
from pathlib import Path

BASELINE = {
  'rtl/core/core_top.sv':'cdc92a0bcd5841a14a0e63fb4a5a9eca140c395b1dd853359663277671d491f7',
  'rtl/core/csr_file.sv':'c26a5497051412a7d1a1ab2fbf7efbbe74a627a805acaa391f912092f9e04a8c',
  'rtl/core/decoder.sv':'c7a43aa86b9b69ed0d334fb0b225b68d7541f03bc121ef3f9b2a455e8290353f',
  'tb/models/imem_sync_model.sv':'9d4a22ab33992d93abce7727cd6ced2ef9914f20404eac807cc40ca5ef818446',
}
EXPECTED_HEAD='cf78be1cc7206879744f7587ab9806a508113b24'
CSR={'MSTATUS':'300','MISA':'301','MTVEC':'305','MEPC':'341','MCAUSE':'342',
     'MTVAL':'343','MVENDORID':'F11','MARCHID':'F12','MIMPID':'F13','MHARTID':'F14'}
CAUSAS=['INSTR_ADDR_MISALIGNED','ILLEGAL_INSTR','LOAD_ADDR_MISALIGNED',
        'LOAD_ACCESS_FAULT','STORE_ADDR_MISALIGNED','STORE_ACCESS_FAULT','ECALL_M']
# Estas filas son rastros de tests históricos (no prueban cobertura completa de las especificaciones).
TRACES=[
 ('CSR: operaciones y acceso','tb_core_csr_ops'),
 ('CSR: valor mtval','tb_core_mtval'),
 ('Sistema: ECALL y MRET','tb_core_system_trap'),
 ('Sistema: EBREAK','tb_core_ebreak_trap'),
 ('Excepción: instrucción ilegal','tb_core_illegal_trap'),
 ('Excepción: salto condicional desalineado','tb_core_branch_misaligned_trap'),
 ('Excepción: JAL desalineado','tb_core_jal_misaligned_trap'),
 ('Excepción: JALR desalineado','tb_core_jalr_misaligned_trap'),
 ('Excepción: load/store desalineado','tb_core_mem_misaligned_trap'),
 ('Excepción: acceso de datos al modelo','tb_core_dmem_sync_fault'),
 ('Excepción: MMIO carga no válida','tb_core_expansion_fault_trap'),
 ('Excepción: MMIO escritura no válida','tb_core_expansion_store_fault_trap'),
 ('Precisión: CSR/trap durante waits','tb_core_expansion_priv_wait'),
 ('Precisión: AXI lectura con fallo','tb_core_expansion_axi4lite_load_fault'),
 ('Precisión: AXI escritura con fallo','tb_core_expansion_axi4lite_store_fault'),
]

def sha(path):
 return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
 ap=argparse.ArgumentParser()
 ap.add_argument('--core',type=Path,required=True)
 ap.add_argument('--baseline-tar',type=Path,required=True)
 ap.add_argument('--out',type=Path,required=True)
 a=ap.parse_args(); a.out.mkdir(parents=True,exist_ok=True)
 issues=[]; info={}
 head=subprocess.check_output(['git','-C',str(a.core),'rev-parse','HEAD'],text=True).strip()
 info['core_head']=head
 if head != EXPECTED_HEAD: issues.append('HEAD del núcleo distinto al baseline: '+head)
 hashes={}
 texts={}
 for rel,expected in BASELINE.items():
  fp=a.core/rel
  if not fp.is_file(): issues.append('Falta archivo '+rel);continue
  actual=sha(fp)
  hashes[rel]={'esperado':expected,'actual':actual,'coincide':actual==expected}
  if actual!=expected: issues.append('SHA distinto en '+rel)
  texts[rel]=fp.read_text(encoding='utf-8',errors='replace')
 info['sha256_fuentes']=hashes
 if issues:
  (a.out/'errores.txt').write_text('\n'.join(issues)+'\n')
  raise SystemExit('ERROR: '+ '; '.join(issues))
 core=texts['rtl/core/core_top.sv']; dec=texts['rtl/core/decoder.sv']; csr=texts['rtl/core/csr_file.sv']
 csr_regs=re.findall(r'\blocalparam\s+logic\s+\[11:0\]\s+CSR_(\w+)\s*=\s*12\x27h([0-9a-fA-F]+)',csr)
 actual_csr={k.upper():v.upper() for k,v in csr_regs}
 if actual_csr != CSR:
  issues.append(f'Inventario de CSR distinto: {actual_csr}')
 info['csr_rtl']=actual_csr
 causs={name:bool(re.search(r'\bMCAUSE_'+name+r'\b',core)) for name in CAUSAS}
 info['causas_rtl_estaticas']=causs
 if not all(causs.values()): issues.append('Falta referencia a causa de trap registrada')
 info['instrucciones_csr_declaradas']={op:bool(re.search(r'\b'+op+r'\b',dec)) for op in ['CSRRW','CSRRS','CSRRC','CSRRWI','CSRRSI','CSRRCI']}
 if not all(info['instrucciones_csr_declaradas'].values()): issues.append('Faltan instrucciones CSR del decoder')
 info['imem_error_como_puerto']=bool(re.search(r'\binput\s+(?:logic|wire)(?:\s*\[[^\]]+\])?\s+imem_error\b',core))
 info['mcause_instruction_access_fault_declarado']=bool(re.search(r'MCAUSE_INSTR_ACCESS_FAULT',core))
 info['fence_noop_documentado']=bool(re.search(r'FENCE[^\n]*(?:no.op|no.op arquitect)',dec,re.I))
 # Abrir el TAR de evidencia histórica en memoria, no extraerlo.
 with tarfile.open(a.baseline_tar,'r:gz') as tar:
  member=tar.getmember('B9_3_9a_resultados/make_regression.log')
  log=tar.extractfile(member).read().decode('utf-8',errors='replace')
 all_pass=re.findall(r'^\[PASS\]\s+(\S+)\s*$',log,re.M)
 if len(all_pass)!=35 or len(set(all_pass))!=35:
  issues.append(f'Esperados 35 [PASS] únicos, encontrados {len(all_pass)} ({len(set(all_pass))} únicos)')
 info['regresion_historica_9a_total_pass']=len(all_pass)
 info['regresion_historica_9a_casos']=all_pass
 rows=[]
 for aspect,test in TRACES:
  found=test in all_pass
  rows.append({'aspecto':aspect,'prueba':test,'evidencia':'PASS historico en B.9.3.9a' if found else 'NO ENCONTRADO', 'tipo':'RTL dirigido'})
  if not found: issues.append('No aparece en regresión histórica: '+test)
 rows += [
  {'aspecto':'Acceso inválido de instrucción','prueba':'B.9.3.9f-v3','evidencia':'Modelo IMEM emite $fatal; no trap de core_top','tipo':'LIMITACION'},
  {'aspecto':'Privilegio completo Sm','prueba':'ACT4 include_priv_tests=false','evidencia':'No acreditado por ACT4','tipo':'FUERA DE ALCANCE ACREDITADO'},
  {'aspecto':'Extensión completa Zicsr','prueba':'ACT4 Zicsr no declarado','evidencia':'6 formatos en decoder; conformidad total no acreditada','tipo':'PENDIENTE DE ALCANCE'},
  {'aspecto':'Ordenamiento FENCE-MMIO','prueba':'ACT4 I-fence-00','evidencia':'PASS ISA de FENCE, no cubre todo ordenamiento MMIO','tipo':'PENDIENTE DIRIGIDO'},
 ]
 with (a.out/'matriz_trazabilidad.csv').open('w',newline='',encoding='utf-8') as f:
  w=csv.DictWriter(f,fieldnames=['aspecto','prueba','evidencia','tipo']);w.writeheader();w.writerows(rows)
 (a.out/'auditoria.json').write_text(json.dumps(info,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
 report=['# B.9.3.9g — trazabilidad del subconjunto CSR y traps','',
         '**Alcance:** auditoría documental/histórica, NO simulaciones nuevas ni certificación privilegiada.','',
         f'- Core: `{head}`','- Fuente de regresión: paquete `B9_3_9a_resultados.tar.gz`',
         f'- Total resultados PASS de regresión: **{len(all_pass)}** (esperados 35).',
         f'- Tests dirigidos seleccionados: **{len(TRACES)}**.',
         f'- CSR declarados en RTL: **{len(actual_csr)}**.',
         '- Modificaciones RTL: ninguna.','',
         '## Límites que permanecen','',
         '- **IMEM**: B.9.3.9f-v3 demostró $fatal del modelo, no excepción arquitectural del núcleo.',
         '- **Sm**: declarado provisionalmente en UDB para tests I; no acreditación de arquitectura privilegiada completa.',
         '- **Zicsr**: seis instrucciones aparecen en decoder, pero la conformidad total no se ha demostrado con ACT4.',
         '- **FENCE**: su ordenamiento frente a MMIO sigue requiriendo un ensayo específico o limitación documentada.',
         '- **PMA y PHYS_ADDR_WIDTH**: aún requieren decisión consistente con la plataforma FPGA.',
         '', '## Interpretación','',
         'Los PASS de los bancos dirigidos evidencian solo las situaciones ejercitadas por esos bancos.',
         'La existencia de una constante o CSR en RTL es una observación estática, no una garantía funcional general.',
         'No deben presentarse estos datos como conformidad completa con Sm, Zicsr ni control de fallos IMEM.',
         '',f'## Resultado','',('**PASS**: inventario y trazabilidad histórica consistentes.' if not issues else '**ERROR**: '+ ', '.join(issues)),'']
 (a.out/'informe.md').write_text('\n'.join(report),encoding='utf-8')
 if issues:
  (a.out/'errores.txt').write_text('\n'.join(issues)+'\n',encoding='utf-8')
  raise SystemExit('ERROR: '+'; '.join(issues))
 print(f'PASS: core y cuatro fuentes RTL/modelo con SHA esperados ({head[:8]}...)')
 print(f'PASS: {len(actual_csr)} CSR y {len(CAUSAS)} causas de trap auditadas estaticamente')
 print(f'PASS: {len(all_pass)}/35 casos de regresion historica, {len(TRACES)} pruebas CSR/trap trazadas')
 print('ATENCION: IMEM error, Zicsr/Sm completos y FENCE-MMIO no acreditados')
 print('PASS: B.9.3.9g — matriz creada, sin modificar fuentes ni ejecutar nueva simulacion')

if __name__=='__main__':main()
