#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""B.9.3.8k: auditoría del conjunto de 51 archivos RV64I fijado en ACT4."""
import csv
import sys
from pathlib import Path

if len(sys.argv) != 3:
    raise SystemExit("Uso: auditar_pendientes.py DIRECTORIO_ACT4 DIRECTORIO_RESULTADOS")
act4, out = Path(sys.argv[1]), Path(sys.argv[2])
completed = {'I-blt-00', 'I-sub-00', 'I-sll-00', 'I-srlw-00', 'I-jal-00', 'I-lui-00', 'I-addi-00', 'I-sh-00', 'I-add-00', 'I-ori-00', 'I-lh-00', 'I-sd-00', 'I-lwu-00', 'I-sraw-00', 'I-sltiu-00', 'I-and-00', 'I-beq-00', 'I-slli-00', 'I-jalr-00', 'I-addiw-00', 'I-or-00', 'I-sllw-00', 'I-auipc-00', 'I-sw-00', 'I-srliw-00', 'I-subw-00', 'I-bgeu-00', 'I-bltu-00', 'I-bge-00', 'I-sraiw-00', 'I-lb-00', 'I-addw-00', 'I-lbu-00', 'I-lw-00', 'I-sb-00', 'I-lhu-00', 'I-xor-00', 'I-srai-00', 'I-slt-00', 'I-ld-00', 'I-andi-00', 'I-sra-00', 'I-srl-00', 'I-xori-00', 'I-srli-00', 'I-slti-00', 'I-sltu-00', 'I-slliw-00', 'I-bne-00'}
selected = {"I-fence-00", "I-nop-00"}
testdir = act4 / "tests/rv64i/I"
all_cases = {p.stem for p in testdir.glob("I-*.S") if p.is_file()}
remaining = all_cases - completed
problems = []
if len(completed) != 49: problems.append("Se esperaban 49 pruebas históricas distintas")
if len(all_cases) != 51: problems.append(f"Inventario ACT4 de esta revisión distinto de 51: {len(all_cases)}")
if not completed <= all_cases: problems.append("Pruebas históricas ausentes: "+", ".join(sorted(completed-all_cases)))
if remaining != selected: problems.append("Pendientes distintos de FENCE y NOP: "+", ".join(sorted(remaining)))
if completed & selected: problems.append("Prueba repetida en selección")
# Comprobar registro B.9.3.8j en el equipo del usuario, sin modificarlo
prev = Path.home() / "TFG_tools/B9_3_8j_resultados/resumen.csv"
if not prev.is_file():
    problems.append("Falta evidencia CSV del lote B.9.3.8j: "+str(prev))
else:
    with prev.open(newline="") as f:
        rows = list(csv.DictReader(f))
    previous_cases={"I-auipc-00","I-bge-00","I-bltu-00","I-lb-00","I-lh-00","I-lui-00","I-slti-00","I-sltiu-00"}
    if ({r.get("caso") for r in rows} != previous_cases or len(rows) != 8 or
        any(r.get("resultado") != "PASS" or r.get("tohost") != "1" or r.get("exit_code") != "0" for r in rows)):
        problems.append("Evidencia B.9.3.8j no concuerda con ocho PASS")
print("=== INVENTARIO ANTES DE B.9.3.8k ===")
print(f"Total ACT4 RV64I: {len(all_cases)}; previas declaradas: {len(completed)}; pendientes: {len(remaining)}")
print("Pendientes: "+", ".join(sorted(remaining)))
if problems:
    for p in problems: print("ERROR: "+p, file=sys.stderr)
    raise SystemExit(1)
(out / "inventario_51.txt").write_text("\n".join(sorted(all_cases))+"\n")
(out / "pendientes_antes.txt").write_text("\n".join(sorted(remaining))+"\n")
(out / "pendientes_despues.txt").write_text("\n".join(sorted(remaining-selected))+ ("\n" if remaining-selected else ""))
print("PASS: inventario de 49 previas y las dos pruebas nuevas sin duplicaciones")
print("Pendientes tras dos PASS: ninguno en este conjunto de 51 archivos")
