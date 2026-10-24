#!/usr/bin/env python3
"""B.9.3.9c: create isolated, matched physical-address candidates. Stdlib only."""
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import sys

HOME = Path.home()
ROOT = HOME / 'TFG_tools'
SRC = ROOT / 'B9_3_7d_primer_elf' / 'config'
OUT = ROOT / 'B9_3_9c_resultados'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    udb = SRC / 'tfg-rv64i.yaml'
    sail = SRC / 'sail.json'
    for path in (udb, sail):
        if not path.is_file():
            raise FileNotFoundError(f'Falta archivo original: {path}')
    txt = udb.read_text(encoding='utf-8')
    sj = json.loads(sail.read_text(encoding='utf-8'))
    pat = re.compile(r'(?m)^(\s*PHYS_ADDR_WIDTH:[ \t]*)(\d+)([ \t]*(?:\#.*)?)$')
    matches = list(pat.finditer(txt))
    if len(matches) != 1:
        raise ValueError(f'Se esperaba una sola asignacion PHYS_ADDR_WIDTH, encontre {len(matches)}')
    pa_udb = int(matches[0].group(2))
    pa_sail = sj['memory']['physaddr_bits']
    if not isinstance(pa_sail, int):
        raise ValueError('memory.physaddr_bits no es entero')
    if pa_udb != 56 or pa_sail != 32:
        raise ValueError(f'Configuracion original no coincide con auditoria anterior: UDB={pa_udb}; Sail={pa_sail}; detener para revisar')

    OUT.mkdir(parents=True, exist_ok=True)
    observations = {
        'fuente_udb': str(udb), 'fuente_sail': str(sail),
        'sha256_udb_original': sha(udb), 'sha256_sail_original': sha(sail),
        'ancho_udb_original': pa_udb, 'ancho_sail_original': pa_sail,
        'candidatas': [],
        'advertencia': 'Una validacion de UDB y Sail no determina por si sola el PA soportado por el hardware. No sustituir config ni declarar conformidad.'
    }
    for bits in (32, 56):
        candidate = OUT / f'pa_{bits}'
        candidate.mkdir(parents=True, exist_ok=True)
        yu = candidate / 'tfg-rv64i.yaml'
        js = candidate / 'sail.json'
        new_y = pat.sub(lambda m: m.group(1) + str(bits) + m.group(3), txt, count=1)
        new_s = copy.deepcopy(sj)
        new_s['memory']['physaddr_bits'] = bits
        yu.write_text(new_y, encoding='utf-8')
        js.write_text(json.dumps(new_s, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
        check_y = yu.read_text(encoding='utf-8')
        check_s = json.loads(js.read_text(encoding='utf-8'))
        assert len(list(pat.finditer(check_y))) == 1
        assert int(pat.search(check_y).group(2)) == bits
        assert check_s['memory']['physaddr_bits'] == bits
        assert check_s['memory']['regions'] == sj['memory']['regions'], 'No se deben modificar regiones'
        assert re.sub(pat, '__PA__', check_y) == re.sub(pat, '__PA__', txt), 'Cambios ajenos a PA en UDB'
        control = copy.deepcopy(check_s)
        control['memory']['physaddr_bits'] = pa_sail
        assert control == sj, 'Cambios ajenos a PA en Sail'
        observations['candidatas'].append({
            'bits': bits, 'udb_yaml': str(yu), 'sail_json': str(js),
            'sha256_udb': sha(yu), 'sha256_sail': sha(js)
        })
    (OUT / 'manifiesto.json').write_text(json.dumps(observations, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(f'PASS: fuentes originales UDB={pa_udb}, Sail={pa_sail}')
    print('PASS: dos candidatas 32/32 y 56/56 creadas sin modificar los originales')
    print('PASS: mapa de memoria y todos los demas parametros permanecen identicos')
    print(f'MANIFIESTO: {OUT / "manifiesto.json"}')

if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print('ERROR:', e, file=sys.stderr)
        sys.exit(1)
