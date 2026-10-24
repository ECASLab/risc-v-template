#!/usr/bin/env python3
"""Convierte un ELF64 RISC-V little-endian a imágenes IMEM/DMEM del TFG.

B.9.3.8d: conversion general por nombre de ELF. NO altera el RTL.
Utiliza únicamente la biblioteca estándar Python.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
from pathlib import Path
import struct

EM_RISCV = 243
PT_LOAD = 1
SHT_SYMTAB = 2


def fail(message: str):
    raise SystemExit(f"ERROR: {message}")


def read_cstr(blob: bytes, index: int) -> str:
    if index < 0 or index >= len(blob):
        return ""
    end = blob.find(b"\0", index)
    return blob[index:end if end >= 0 else len(blob)].decode("utf-8", "replace")


def parse_elf(blob: bytes):
    header_fmt = "<16sHHIQQQIHHHHHH"
    if len(blob) < struct.calcsize(header_fmt):
        fail("ELF demasiado corto")
    ident, e_type, machine, eversion, entry, phoff, shoff, flags, ehsize, phentsize, phnum, shentsize, shnum, shstrndx = struct.unpack_from(header_fmt, blob)
    if ident[:4] != b"\x7fELF" or ident[4] != 2 or ident[5] != 1:
        fail("se requiere ELF64 little-endian")
    if machine != EM_RISCV or e_type != 2:
        fail(f"se requiere ELF ejecutable de RISC-V (machine={machine}, type={e_type})")
    if eversion != 1 or flags & 1:
        fail(f"formato o flags no soportados (version={eversion}, e_flags=0x{flags:x})")
    if phnum < 1 or phentsize != struct.calcsize("<IIQQQQQQ") or phoff + phnum * phentsize > len(blob):
        fail("tabla de programas ELF invalida")
    segments = []
    for i in range(phnum):
        typ, p_flags, off, vaddr, paddr, filesz, memsz, align = struct.unpack_from("<IIQQQQQQ", blob, phoff + i * phentsize)
        if typ != PT_LOAD:
            continue
        if filesz > memsz or off + filesz > len(blob):
            fail(f"LOAD[{i}] inconsistente o truncado")
        if paddr != vaddr:
            fail(f"LOAD[{i}] paddr != vaddr: este loader bare-metal no hace traduccion")
        segments.append({"index": i, "addr": paddr, "filesz": filesz, "memsz": memsz,
                         "offset": off, "flags": p_flags})
    if not segments:
        fail("ELF no tiene segmentos PT_LOAD")

    symbols = {}
    sections = []
    sh_fmt = "<IIQQQQIIQQ"
    if shnum:
        if shentsize != struct.calcsize(sh_fmt) or shoff + shnum * shentsize > len(blob):
            fail("tabla de secciones ELF invalida")
        shdrs = [struct.unpack_from(sh_fmt, blob, shoff + i * shentsize) for i in range(shnum)]
        if shstrndx >= shnum:
            fail("indice shstrndx invalido")
        hdr = shdrs[shstrndx]
        strings = blob[hdr[4]:hdr[4] + hdr[5]]
        for i, sh in enumerate(shdrs):
            sections.append({"name": read_cstr(strings, sh[0]), "addr": sh[3], "size": sh[5], "type": sh[1]})
            if sh[1] != SHT_SYMTAB:
                continue
            if sh[6] >= shnum:
                fail("symbol table no tiene tabla de strings")
            st = shdrs[sh[6]]
            strtab = blob[st[4]:st[4] + st[5]]
            if sh[9] != 24 or sh[4] + sh[5] > len(blob):
                fail("symbol table invalida")
            for off in range(sh[4], sh[4] + sh[5], sh[9]):
                name_index, info, other, shndx, value, size = struct.unpack_from("<IBBHQQ", blob, off)
                name = read_cstr(strtab, name_index)
                if name and shndx != 0:
                    symbols[name] = value
    return entry, flags, segments, symbols, sections


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--elf", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--base", type=lambda s: int(s, 0), default=0x80000000)
    ap.add_argument("--ram-size", type=lambda s: int(s, 0), default=0x100000)
    args = ap.parse_args()
    if args.ram_size <= 0 or args.ram_size % 8 or args.base % 8:
        fail("base y tamano RAM deben estar alineados a 8 bytes")
    blob = args.elf.read_bytes()
    entry, flags, segments, symbols, sections = parse_elf(blob)
    mem = bytearray(args.ram_size)  # cero en los huecos y NOBITS (.bss/.stack)
    ordered = sorted(segments, key=lambda s: s["addr"])
    previous_end = args.base
    highest_end = args.base
    for s in ordered:
        start = s["addr"]
        end = start + s["memsz"]
        if start < args.base or end > args.base + args.ram_size or end < start:
            fail(f"LOAD[{s['index']}] fuera de RAM: 0x{start:x}..0x{end:x}")
        if start < previous_end:
            fail(f"LOAD[{s['index']}] solapa otro segmento")
        off = start - args.base
        mem[off:off + s["filesz"]] = blob[s["offset"]:s["offset"] + s["filesz"]]
        previous_end, highest_end = end, max(highest_end, end)
    if entry % 4 or not any(s["addr"] <= entry < s["addr"] + s["memsz"] and s["flags"] & 1 for s in ordered):
        fail("entry no alineado o fuera de segmento ejecutable")
    for name in ("rvtest_entry_point", "tohost", "begin_signature", "end_signature"):
        if name not in symbols:
            fail(f"falta simbolo obligatorio: {name}")
        if not (args.base <= symbols[name] < args.base + args.ram_size):
            fail(f"simbolo {name} fuera de RAM")
    if symbols["rvtest_entry_point"] != entry:
        fail("rvtest_entry_point difiere de e_entry")
    if symbols["tohost"] % 8:
        fail("tohost no alineado a 8 bytes")
    if not (symbols["begin_signature"] < symbols["end_signature"]):
        fail("firma de resultados vacia o invertida")
    if not any(s["addr"] <= symbols["tohost"] and symbols["tohost"] + 8 <= s["addr"] + s["memsz"] and s["flags"] & 2 for s in ordered):
        fail("tohost no esta en segmento LOAD escribible")
    args.out.mkdir(parents=True, exist_ok=True)
    case_name = args.elf.stem
    if not re.fullmatch(r"[A-Za-z0-9_-]+", case_name):
        fail("nombre de prueba invalido para generar archivos")
    out_i = args.out / f"{case_name}_imem.hex"
    out_d = args.out / f"{case_name}_dmem.hex"
    with out_i.open("w", encoding="ascii") as f:
        for offset in range(0, args.ram_size, 4):
            f.write(f"{int.from_bytes(mem[offset:offset + 4], 'little'):08x}\n")
    with out_d.open("w", encoding="ascii") as f:
        for offset in range(0, args.ram_size, 8):
            f.write(f"{int.from_bytes(mem[offset:offset + 8], 'little'):016x}\n")
    report = {
        "elf": str(args.elf), "sha256_elf": hashlib.sha256(blob).hexdigest(),
        "entry": f"0x{entry:016x}", "ram_base": f"0x{args.base:016x}",
        "ram_bytes": args.ram_size, "imem_words_32": args.ram_size // 4,
        "dmem_words_64": args.ram_size // 8,
        "highest_load_address_exclusive": f"0x{highest_end:016x}",
        "tohost": f"0x{symbols['tohost']:016x}",
        "begin_signature": f"0x{symbols['begin_signature']:016x}",
        "end_signature": f"0x{symbols['end_signature']:016x}",
        "signature_bytes": symbols["end_signature"] - symbols["begin_signature"],
        "segments": [{**s, "addr": f"0x{s['addr']:016x}"} for s in ordered],
        "sections": [{**s, "addr": f"0x{s['addr']:016x}"} for s in sections if s["addr"]],
        "sha256_imem": hashlib.sha256(out_i.read_bytes()).hexdigest(),
        "sha256_dmem": hashlib.sha256(out_d.read_bytes()).hexdigest(),
    }
    (args.out / "metadata.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    # Comprobar inversa del empaquetado con las primeras y últimas posiciones utilizadas
    for offset in (0, 4, 8, symbols["tohost"] - args.base, highest_end - args.base - 8):
        if offset < 0 or offset + 8 > len(mem):
            continue
        dword = int.from_bytes(mem[offset // 8 * 8:offset // 8 * 8 + 8], "little")
        assert mem[offset // 8 * 8:offset // 8 * 8 + 8] == dword.to_bytes(8, "little")
    print(f"PASS: ELF64 RISC-V y {len(ordered)} segmentos LOAD validados")
    print(f"PASS: entry=0x{entry:x}, tohost=0x{symbols['tohost']:x}")
    print(f"PASS: firma=0x{symbols['begin_signature']:x}..0x{symbols['end_signature']:x} ({report['signature_bytes']} bytes)")
    print(f"PASS: ultima direccion ocupada=0x{highest_end:x} < limite=0x{args.base+args.ram_size:x}")
    print(f"PASS: IMEM={report['imem_words_32']} palabras x32, DMEM={report['dmem_words_64']} palabras x64")
    print(f"IMEM: {out_i}")
    print(f"DMEM: {out_d}")
    print(f"METADATA: {args.out / 'metadata.json'}")
    print("AVISO: imagenes preparadas, aun no ejecutadas en core_top.")

if __name__ == '__main__':
    main()
