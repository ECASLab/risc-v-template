#!/usr/bin/env python3
"""Validacion general de imagenes ACT4 sin direccion ni nombre de caso fijos.

Emite valores compatibles con `source` en Bash despues de su validacion.
"""
import hashlib
import json
import re
import shlex
import sys
from pathlib import Path


def fail(msg):
    raise SystemExit('ERROR: ' + msg)


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def main():
    if len(sys.argv) != 3:
        fail('uso: verificar_imagenes_generico.py DIR_IMAGENES ARCHIVO_ENTORNO')
    directory, env_path = Path(sys.argv[1]), Path(sys.argv[2])
    meta = json.loads((directory / 'metadata.json').read_text(encoding='utf-8'))
    name = Path(meta['elf']).stem
    if not re.fullmatch(r'[A-Za-z0-9_-]+', name):
        fail('nombre de caso fuera de los caracteres permitidos')
    imem = directory / (name + '_imem.hex')
    dmem = directory / (name + '_dmem.hex')
    for path in (imem, dmem):
        if not path.is_file():
            fail('imagen no encontrada: ' + str(path))
    for key, image in (('sha256_imem', imem), ('sha256_dmem', dmem)):
        if digest(image) != meta[key]:
            fail('huella SHA-256 incorrecta: ' + str(image))
    base = int(meta['ram_base'], 16)
    ram_bytes = int(meta['ram_bytes'])
    entry = int(meta['entry'], 16)
    tohost = int(meta['tohost'], 16)
    if (base, ram_bytes, entry) != (0x80000000, 0x100000, 0x80000000):
        fail('entry/base/tamano no compatibles con el DUT actual')
    if not (base <= tohost <= base + ram_bytes - 8 and tohost % 8 == 0):
        fail('tohost fuera de RAM o desalineado')
    if int(meta['imem_words_32']) != ram_bytes // 4 or int(meta['dmem_words_64']) != ram_bytes // 8:
        fail('cantidad de palabras incorrecta')
    high_sections = [s for s in meta['sections'] if s['name'] == '.text.rvmodel' and int(s['size']) > 0]
    if len(high_sections) != 1:
        fail('no hay una unica seccion ejecutable .text.rvmodel')
    high = int(high_sections[0]['addr'], 16)
    if not (base <= high <= base + ram_bytes - 4 and high % 4 == 0):
        fail('direccion de .text.rvmodel fuera de RAM o desalineada')
    if not any(int(s['addr'], 16) <= high < int(s['addr'], 16) + int(s['memsz'])
               and s['flags'] & 1 for s in meta['segments']):
        fail('.text.rvmodel no esta dentro de un segmento ejecutable')
    with imem.open(encoding='ascii') as fi, dmem.open(encoding='ascii') as fd:
        count = 0
        while True:
            lo, hi, wide = fi.readline(), fi.readline(), fd.readline()
            if not (lo or hi or wide):
                break
            if not (lo and hi and wide):
                fail('cantidad de palabras diferente entre IMEM y DMEM')
            try:
                if int(wide, 16) != int(lo, 16) | (int(hi, 16) << 32):
                    fail(f'imagenes no coinciden en indice de DMEM {count}')
            except ValueError:
                fail(f'palabra hex invalida en indice {count}')
            count += 1
        if count != ram_bytes // 8:
            fail(f'cantidad incorrecta de palabras: {count}')
    if imem.resolve().parent != directory.resolve() or dmem.resolve().parent != directory.resolve():
        fail('rutas de imagenes inconsistentes')
    env_path.write_text(
        'CASE_NAME=' + name + '\n'
        + 'TOHOST_HEX=' + format(tohost, 'x') + '\n'
        + 'ENTRY_HEX=' + format(entry, 'x') + '\n'
        + 'HIGH_TEXT_HEX=' + format(high, 'x') + '\n'
        + 'IMEM_FILE=' + shlex.quote(str(imem)) + '\n'
        + 'DMEM_FILE=' + shlex.quote(str(dmem)) + '\n', encoding='utf-8')
    print('PASS: imagenes IMEM/DMEM coherentes para ' + name)
    print('PASS: SHA-256 de ambas imagenes y mapa del ELF verificados')
    print(f'PASS: entry=0x{entry:x}, tohost=0x{tohost:x}, .text.rvmodel=0x{high:x}')
    print('PASS: palabras de 1 MiB comprobadas (' + str(count) + ' x 64 bits)')


if __name__ == '__main__':
    main()
