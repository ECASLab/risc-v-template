#!/usr/bin/env python3
"""Auditoria ESTATICA: confirma que se analiza la misma version del RTL que en 9d."""
import hashlib
import json
import pathlib
import re
import sys

EXPECTED = {
    'core_top.sv': 'cdc92a0bcd5841a14a0e63fb4a5a9eca140c395b1dd853359663277671d491f7',
    'imem_sync_model.sv': '9d4a22ab33992d93abce7727cd6ced2ef9914f20404eac807cc40ca5ef818446',
    'dmem_sync_model.sv': '5e2f7f52c3c4776cb381aa4fd846948fbb1f88f9f24b9250499d6dc775c11a33',
}

def main():
    if len(sys.argv) != 3:
        raise SystemExit('Uso: auditar_B9_3_9e.py CORE_PATH OUTPUT_DIR')
    core = pathlib.Path(sys.argv[1])
    out = pathlib.Path(sys.argv[2])
    paths = {
        'core_top.sv': core / 'rtl/core/core_top.sv',
        'imem_sync_model.sv': core / 'tb/models/imem_sync_model.sv',
        'dmem_sync_model.sv': core / 'tb/models/dmem_sync_model.sv',
    }
    missing = [str(v) for v in paths.values() if not v.is_file()]
    if missing:
        raise SystemExit('ERROR: faltan fuentes requeridas en el núcleo: ' + ', '.join(missing))
    hashes = {k: hashlib.sha256(v.read_bytes()).hexdigest() for k, v in paths.items()}
    for k in EXPECTED:
        if hashes[k] != EXPECTED[k]:
            raise SystemExit(f'ERROR: {k} ha cambiado respecto a B.9.3.9d: actual={hashes[k]} esperado={EXPECTED[k]}')
    core_text = paths['core_top.sv'].read_text()
    imem_text = paths['imem_sync_model.sv'].read_text()
    check = {
        'core_64_bit_instruction_address': bool(re.search(r'output\s+logic\s*\[\s*63\s*:\s*0\s*\]\s*imem_addr', core_text)),
        'core_input_imem_rvalid': bool(re.search(r'input\s+logic\s+imem_rvalid', core_text)),
        'core_input_imem_error': bool(re.search(r'input\s+logic\s+imem_error', core_text)),
        'imem_has_range_check': 'addr_in_range' in imem_text,
        'imem_out_of_range_fatal': 'IMEM model error:' in imem_text and '$fatal' in imem_text,
        'imem_error_output': bool(re.search(r'output\s+logic\s+error_o', imem_text)),
    }
    assert check['core_64_bit_instruction_address'] and check['core_input_imem_rvalid']
    assert not check['core_input_imem_error']
    assert check['imem_has_range_check'] and check['imem_out_of_range_fatal']
    assert not check['imem_error_output']
    result = {'sha256': hashes, 'checks': check, 'scope': 'modelo IMEM; no core_top en simulacion; no evidencia del PA global ni del trap instr access fault'}
    (out / 'auditoria_estatica.json').write_text(json.dumps(result, indent=2) + '\n')
    print('PASS: ruta correcta rtl/core/core_top.sv y tres fuentes idénticas a B.9.3.9d (SHA-256)')
    print('PASS: core_top expone imem_addr[63:0] e imem_rvalid, sin entrada imem_error')
    print('PASS: IMEM usa $fatal ante acceso fuera del rango del modelo')
    print('ADVERTENCIA: esto no demuestra un instruction access fault arquitectural')

if __name__ == '__main__':
    main()
