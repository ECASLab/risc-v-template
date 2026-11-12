#!/usr/bin/env python3
"""Empaquetar firmware PL_FLAT KV260 ya generado."""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEPLOY = ROOT / "fpga" / "deploy"

FIRMWARE = "tfg-rv64i-kv260"
BITBIN = "rv64i_tfg_kv260.bit.bin"
DTBO = "rv64i_tfg_kv260.dtbo"


def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def require(condition, message):
    if not condition:
        raise SystemExit("STOP: " + message)


def main():
    parser = argparse.ArgumentParser(
        description="Preparar firmware KV260 PL_FLAT sin Vivado"
    )
    parser.add_argument(
        "--bin", required=True, type=Path,
        help="Archivo BIN generado mediante Vivado"
    )
    parser.add_argument(
        "--out", required=True, type=Path,
        help="Nuevo directorio de paquete, fuera del repositorio"
    )
    parser.add_argument(
        "--design-commit", required=True,
        help="Commit completo de 40 caracteres del diseno implementado"
    )
    args = parser.parse_args()

    source = args.bin.expanduser().resolve()
    output = args.out.expanduser().resolve()

    require(source.is_file(), "BIN no encontrado")
    require(not args.bin.is_symlink(), "BIN simbolico no permitido")
    require(source.stat().st_size > 0, "BIN vacio")
    require(not output.exists(), "Directorio de salida existente")
    require(output.parent.is_dir(), "Directorio padre inexistente")
    require(
        ROOT not in output.parents and output != ROOT,
        "La salida debe quedar fuera del repositorio"
    )
    require(
        re.fullmatch(r"[0-9a-f]{40}", args.design_commit),
        "Se requiere el SHA completo del commit"
    )

    dts = DEPLOY / "rv64i_tfg_kv260.dts"
    shell = DEPLOY / "shell.json"

    require(dts.is_file(), "DTS no encontrado")
    require(shell.is_file(), "shell.json no encontrado")

    descriptor = json.loads(shell.read_text(encoding="utf-8"))
    require(
        descriptor.get("shell_type") == "PL_FLAT",
        "Descriptor incompatible"
    )

    dtc = shutil.which("dtc")
    require(dtc is not None, "DTC no disponible")

    with tempfile.TemporaryDirectory(
        prefix=".kv260-package-",
        dir=output.parent
    ) as temporary:
        stage = Path(temporary) / output.name
        firmware = stage / "firmware" / FIRMWARE
        firmware.mkdir(parents=True)

        bitbin = firmware / BITBIN
        overlay = firmware / DTBO
        shell_output = firmware / "shell.json"

        shutil.copyfile(source, bitbin)
        shutil.copyfile(shell, shell_output)

        result = subprocess.run(
            [
                dtc, "-@", "-I", "dts", "-O", "dtb",
                "-o", str(overlay), str(dts)
            ],
            cwd=DEPLOY,
            capture_output=True,
            text=True
        )

        require(
            result.returncode == 0,
            "DTC fallo: " + result.stderr[-1500:]
        )
        require(
            overlay.is_file()
            and overlay.read_bytes()[:4] == bytes.fromhex("d00dfeed"),
            "DTBO no valido"
        )

        files = [bitbin, overlay, shell_output]
        artifacts = []

        for path in files:
            artifacts.append({
                "path": path.relative_to(stage).as_posix(),
                "size_bytes": path.stat().st_size,
                "sha256": sha256(path),
            })

        manifest = {
            "schema_version": 1,
            "source_commit": args.design_commit,
            "vivado_version": "2024.1",
            "device": "xck26-sfvc784-2LV-c",
            "firmware_type": "PL_FLAT",
            "build_status": "generated",
            "hardware_validation": "not_performed",
            "distribution_status": "pending_authorization",
            "source_dts_sha256": sha256(dts),
            "source_shell_sha256": sha256(shell),
            "artifacts": artifacts,
        }

        (stage / "manifest.json").write_text(
            json.dumps(manifest, indent=2) + "\n",
            encoding="utf-8"
        )

        (stage / "SHA256SUMS.txt").write_text(
            "".join(
                f"{item['sha256']}  {item['path']}\n"
                for item in artifacts
            ),
            encoding="utf-8"
        )

        (stage / "README.md").write_text(
            "# Firmware KV260 reconstruido\n\n"
            "Este paquete contiene firmware PL_FLAT generado.\n\n"
            "No acredita validacion fisica del bitstream.\n"
            "No sustituye el firmware historico aprobado.\n"
            "La autorizacion de distribucion esta pendiente.\n"
            "Consultar manifest.json para procedencia e integridad.\n",
            encoding="utf-8"
        )

        for item in artifacts:
            path = stage / item["path"]
            require(
                sha256(path) == item["sha256"],
                "Integridad incorrecta"
            )

        os.rename(stage, output)

    print("PASS: firmware PL_FLAT ensamblado")
    for item in artifacts:
        print(
            f"PASS: {item['path']} "
            f"({item['size_bytes']} bytes)"
        )
    print("PASS: tres SHA-256 verificados")
    print("HARDWARE_VALIDATION=not_performed")
    print("DISTRIBUTION_STATUS=pending_authorization")
    print("OUTPUT_DIR=", output)


if __name__ == "__main__":
    main()
