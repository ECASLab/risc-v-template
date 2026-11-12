#!/usr/bin/env python3
"""Verifica el manifiesto y los binarios de referencia KV260."""

import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = ROOT / "fpga/prebuilt/kv260"
MANIFEST = PACKAGE / "manifest.json"

EXPECTED_PATHS = {
    "firmware/tfg-rv64i-kv260/shell.json",
    "firmware/tfg-rv64i-kv260/rv64i_tfg_kv260.bit.bin",
    "firmware/tfg-rv64i-kv260/rv64i_tfg_kv260.dtbo",
    "software/accelerator.bin",
    "software/rv64i_arm_loader_first_run",
}


def require(condition, message):
    if not condition:
        raise SystemExit("STOP: " + message)


def sha256_file(path):
    digest = hashlib.sha256()

    with path.open("rb") as source:
        for block in iter(
            lambda: source.read(1024 * 1024), b""
        ):
            digest.update(block)

    return digest.hexdigest()


def load_manifest():
    require(MANIFEST.is_file(), "falta manifest.json")

    data = json.loads(MANIFEST.read_text(encoding="utf-8"))

    require(data.get("schema_version") == 1,
            "version de manifiesto incompatible")

    require(data.get("distribution_status") in {
                "pending_authorization",
                "authorized_for_distribution",
            },
            "estado de distribucion inesperado")

    require(data.get("firmware_type") == "PL_FLAT",
            "tipo de firmware inesperado")

    require(data.get("device") ==
            "xck26-sfvc784-2LV-c",
            "dispositivo FPGA inesperado")

    items = data.get("artifacts")
    require(isinstance(items, list),
            "lista de artefactos invalida")

    paths = []

    for item in items:
        require(isinstance(item, dict),
                "entrada de artefacto invalida")

        path = item.get("path")
        size = item.get("size_bytes")
        digest = item.get("sha256")

        require(isinstance(path, str),
                "ruta de artefacto invalida")
        require(isinstance(size, int)
                and not isinstance(size, bool) and size > 0,
                f"tamano invalido: {path}")
        require(isinstance(digest, str)
                and re.fullmatch(r"[0-9a-f]{64}", digest),
                f"SHA-256 invalido: {path}")

        paths.append(path)

    require(len(paths) == len(set(paths)),
            "rutas duplicadas")

    require(set(paths) == EXPECTED_PATHS,
            "inventario diferente de los cinco artefactos")

    print("PASS: manifiesto valido (5 artefactos)")
    print("Estado:", data["distribution_status"])

    return items


def verify_files(items, base):
    require(base.is_dir(),
            f"directorio no encontrado: {base}")

    for item in items:
        path = base / item["path"]

        require(not path.is_symlink(),
                f"enlace simbolico no permitido: {path}")

        require(path.is_file(),
                f"archivo no encontrado: {path}")

        require(path.stat().st_size == item["size_bytes"],
                f"tamano incorrecto: {path}")

        require(sha256_file(path) == item["sha256"],
                f"SHA-256 incorrecto: {path}")

        print(f"PASS: {item['path']}")

    firmware = base / "firmware/tfg-rv64i-kv260"

    shell = json.loads(
        (firmware / "shell.json").read_text(encoding="utf-8")
    )

    require(shell.get("shell_type") == "PL_FLAT",
            "shell.json no declara PL_FLAT")

    with (firmware / "rv64i_tfg_kv260.dtbo").open("rb") as f:
        require(f.read(4) == bytes.fromhex("d00dfeed"),
                "encabezado DTBO incorrecto")

    loader = base / "software/rv64i_arm_loader_first_run"

    with loader.open("rb") as f:
        header = f.read(20)

    require(
        len(header) == 20
        and header[:4] == b"\x7fELF"
        and header[4] == 2
        and header[5] == 1
        and int.from_bytes(header[18:20], "little") == 183,
        "cargador no corresponde a ELF64 AArch64"
    )

    print("PASS: formatos PL_FLAT, DTBO y ELF64 AArch64")
    print("PASS: verificacion completa de los cinco archivos")


def main():
    parser = argparse.ArgumentParser(
        description="Verifica artefactos FPGA KV260"
    )

    parser.add_argument(
        "--metadata-only",
        action="store_true",
        help="Validar solo manifest.json"
    )

    parser.add_argument(
        "--artifact-root",
        type=Path,
        default=PACKAGE,
        help="Directorio que contiene firmware/ y software/"
    )

    args = parser.parse_args()
    items = load_manifest()

    if args.metadata_only:
        print("METADATA_ONLY: no se verificaron binarios")
        return

    verify_files(
        items,
        args.artifact_root.expanduser().resolve()
    )


if __name__ == "__main__":
    main()
