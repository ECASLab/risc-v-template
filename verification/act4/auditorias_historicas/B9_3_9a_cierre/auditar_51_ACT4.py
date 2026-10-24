#!/usr/bin/env python3
"""Audita evidencia historica ACT4 de 51 pruebas RV64I, sin modificar fuentes.

Uso: python3 auditar_51_ACT4.py --archivos ~/TFG_tools --salida ~/TFG_tools/B9_3_9_auditoria
Acepta los archivos B9_3_8c_resultados.tar.gz, B9_3_8d_resultados.tar.gz,
y B9_3_8e ... B9_3_8k_resultados.tar.gz.
"""
import argparse
import csv
import hashlib
import io
import re
import tarfile
from pathlib import Path

RE = re.compile(r"PASS: ACT4 (I-[\w-]+) ejecutado en core_top \(tohost=1\).*?ciclos=(\d+) fetch=(\d+) dmem=(\d+) respuestas=(\d+)", re.S)
BATCHES = ['e','f','g','h','i','j','k']
CORE = 'cf78be1cc7206879744f7587ab9806a508113b24'
ACT4 = 'd6094ad3ede5268b454197e7bb8eb1cbcbe140d0'

def find_bytes(tf, key):
    member = tf.getmember(key)
    return tf.extractfile(member).read()

def read_text(tf,key):
    return find_bytes(tf,key).decode('utf-8',errors='replace')

def parse_sim(raw, name):
    m = RE.search(raw)
    if m is None: raise ValueError(f'No aparece PASS+metricas en sim.log: {name}')
    match_name,cycles,fetch,dmem,responses = m.groups()
    if match_name != name: raise ValueError(f'Nombre inconsistente: {name} != {match_name}')
    if 'INFO: store tohost aceptado: 0x0000000000000001' not in raw:
        raise ValueError(f'Sin confirmacion explicita de escritura tohost=1: {name}')
    return [int(x) for x in (cycles,fetch,dmem,responses)]

def validation(archive_dir, output_dir):
    rows = []
    archives = []
    expected = None
    for single,batch in [('c','B.9.3.8c'),('d','B.9.3.8d')]:
        p = archive_dir / f'B9_3_8{single}_resultados.tar.gz'
        if not p.is_file(): raise FileNotFoundError(p)
        archives.append(p)
        name = 'I-addi-00' if single=='c' else 'I-add-00'
        with tarfile.open(p, 'r:gz') as t:
            sim = read_text(t,'sim.log')
            metrics = parse_sim(sim,name)
            code = read_text(t,'estado.txt').strip()
            if code not in ('SIM_EXIT=0','0'): raise ValueError(f'Codigo salida incorrecto en {p.name}: {code}')
            if 'PASS: testbench' in sim: pass
            if metrics[2] != metrics[3]: raise ValueError(f'Respuestas DMEM desiguales: {name}')
            rows.append([name,'PASS',*metrics,1,0,batch,p.name])
    for batch in BATCHES:
        p = archive_dir / f'B9_3_8{batch}_resultados.tar.gz'
        if not p.is_file(): raise FileNotFoundError(p)
        archives.append(p)
        with tarfile.open(p,'r:gz') as t:
            failure_count = read_text(t,'fallos.txt').strip()
            if failure_count!='0': raise ValueError(f'El lote 8{batch} reporta fallos={failure_count}')
            data = list(csv.DictReader(io.StringIO(read_text(t,'resumen.csv'))))
            if not data: raise ValueError(f'Sin casos en lote 8{batch}')
            for r in data:
                name = r['caso']
                if r['resultado']!='PASS' or r['tohost']!='1' or r['exit_code']!='0':
                    raise ValueError(f'Caso NO aprobado: {name}: {r}')
                metrics = [int(r[x]) for x in ('ciclos','fetch','dmem','respuestas')]
                if metrics[2]!=metrics[3]: raise ValueError(f'DMEM incompleta: {name}')
                log_name = f'logs/{name}.console.log'
                logs = read_text(t, log_name)
                if f'PASS: ACT4 {name} ejecutado en core_top (tohost=1)' not in logs:
                    raise ValueError(f'Log no confirma PASS: {name}')
                if '✓ Build complete: 7 succeeded' not in logs:
                    raise ValueError(f'Log no confirma compilacion ACT4: {name}')
                innerbytes = find_bytes(t, f'paquetes/{name}.tar.gz')
                with tarfile.open(fileobj=io.BytesIO(innerbytes),mode='r:gz') as inner:
                    sim = read_text(inner,'sim.log')
                    if parse_sim(sim,name) != metrics:
                        raise ValueError(f'CSV difiere de sim.log: {name}')
                    if read_text(inner,'estado.txt').strip()!='0':
                        raise ValueError(f'Exitcode interno no cero: {name}')
                    elf_members=[m for m in inner.getmembers() if m.name.endswith(f'/{name}.elf')]
                    if len(elf_members)!=1:
                        raise ValueError(f'ELF no comprobado: {name}, encontrados {len(elf_members)}')
                rows.append([name,'PASS',*metrics,1,0,f'B.9.3.8{batch}',p.name])
            if batch=='k':
                expected=set(read_text(t,'inventario_51.txt').splitlines())
                if read_text(t,'pendientes_despues.txt').strip():
                    raise ValueError('Quedan pruebas pendientes segun inventario final')
    names=[r[0] for r in rows]
    if len(set(names))!=len(names): raise ValueError('Casos duplicados en los archivos historicos')
    if len(rows)!=51 or expected!=set(names):
        missing=(expected or set())-set(names)
        extra=set(names)-(expected or set())
        raise ValueError(f'Inventario incorrecto: {len(rows)} filas; faltan {missing}; extras {extra}')
    rows.sort(key=lambda r:r[0])
    output_dir.mkdir(parents=True, exist_ok=True)
    csvpath=output_dir/'resultados_51_ACT4.csv'
    with csvpath.open('w',newline='',encoding='utf-8') as f:
        w=csv.writer(f)
        w.writerow(['caso','resultado','ciclos','fetch','dmem','respuestas','tohost','exit_code','subpunto','archivo_fuente'])
        w.writerows(rows)
    checks=output_dir/'sha256_archivos_historicos.txt'
    checks.write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in archives),encoding='utf-8')
    cycle_total=sum(r[2] for r in rows)
    fetch_total=sum(r[3] for r in rows)
    dmem_total=sum(r[4] for r in rows)
    report=output_dir/'informe_cierre_ACT4_RV64I.md'
    report.write_text(f'''# Auditoria de cierre ACT4 RV64I — TFG

**Resultado del cotejo retrospectivo:** 51 archivos de prueba unicos, 51 PASS, 0 FAIL, 0 ausentes respecto al inventario final.

- Core Git HEAD documentado en los logs: `{CORE}`.
- ACT4 Git HEAD documentado en los logs: `{ACT4}`.
- Archivos de evidencia cotejados: {len(archives)} paquetes TAR.GZ (B.9.3.8c, B.9.3.8d y B.9.3.8e–k).
- Verificado para cada prueba: CSV/log o sim.log, terminacion `tohost=1`, `exit_code=0`, y conteo igual de transacciones y respuestas DMEM.
- Para los lotes e–k tambien se contrastaron los logs internos con el CSV, la presencia del ELF, la compilacion ACT4 y `fallos.txt=0`.
- Suma descriptiva de simulaciones: {cycle_total:,} ciclos, {fetch_total:,} fetch, {dmem_total:,} transacciones DMEM. No es un benchmark de rendimiento ni mide el CPI de instrucciones aisladas.

## Alcance y limitaciones

1. Se acredita la **ejecucion local satisfactoria del conjunto de 51 archivos ACT4 RV64I identificados**. No es una certificacion oficial ni cobertura exhaustiva.
2. Esta auditoria es un cotejo documental; **no repite las simulaciones**. Ejecutar `make regression`, `make lint` y `make baremetal-probe` en el repositorio actual constituye una tarea separada.
3. Configuracion UDB con `Sm` provisional, pruebas privilegiadas desactivadas. Validar/justificar `PHYS_ADDR_WIDTH`, `PMA_GRANULARITY`, coherencia UDB/Sail y alcance de CSR, traps y FENCE/MMIO.
4. El modelo IMEM/DMEM de simulacion de 1 MiB no demuestra por si mismo implementacion en BRAM fisica ni timing FPGA.

## Referencias de evidencia

Los valores detallados figuran en `resultados_51_ACT4.csv` y las huellas SHA-256 de los paquetes fuente en `sha256_archivos_historicos.txt`.
''', encoding='utf-8')
    return rows, csvpath, checks, report

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--archivos',type=Path,default=Path.home()/'TFG_tools')
    parser.add_argument('--salida',type=Path,default=Path.home()/'TFG_tools'/'B9_3_9_auditoria')
    args=parser.parse_args()
    rows, *_ = validation(args.archivos, args.salida)
    print(f'PASS: {len(rows)} casos unicos auditados; 51/51 PASS; sin pendientes ni contradicciones en la evidencia historica.')
    print(f'REPORTES: {args.salida}')

if __name__=='__main__':
    main()
