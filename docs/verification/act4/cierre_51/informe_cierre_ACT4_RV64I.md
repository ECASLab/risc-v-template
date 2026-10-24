# Auditoria de cierre ACT4 RV64I — TFG

**Resultado del cotejo retrospectivo:** 51 archivos de prueba unicos, 51 PASS, 0 FAIL, 0 ausentes respecto al inventario final.

- Core Git HEAD documentado en los logs: `cf78be1cc7206879744f7587ab9806a508113b24`.
- ACT4 Git HEAD documentado en los logs: `d6094ad3ede5268b454197e7bb8eb1cbcbe140d0`.
- Archivos de evidencia cotejados: 9 paquetes TAR.GZ (B.9.3.8c, B.9.3.8d y B.9.3.8e–k).
- Verificado para cada prueba: CSV/log o sim.log, terminacion `tohost=1`, `exit_code=0`, y conteo igual de transacciones y respuestas DMEM.
- Para los lotes e–k tambien se contrastaron los logs internos con el CSV, la presencia del ELF, la compilacion ACT4 y `fallos.txt=0`.
- Suma descriptiva de simulaciones: 891,480 ciclos, 209,808 fetch, 50,834 transacciones DMEM. No es un benchmark de rendimiento ni mide el CPI de instrucciones aisladas.

## Alcance y limitaciones

1. Se acredita la **ejecucion local satisfactoria del conjunto de 51 archivos ACT4 RV64I identificados**. No es una certificacion oficial ni cobertura exhaustiva.
2. Esta auditoria es un cotejo documental; **no repite las simulaciones**. Ejecutar `make regression`, `make lint` y `make baremetal-probe` en el repositorio actual constituye una tarea separada.
3. Configuracion UDB con `Sm` provisional, pruebas privilegiadas desactivadas. Validar/justificar `PHYS_ADDR_WIDTH`, `PMA_GRANULARITY`, coherencia UDB/Sail y alcance de CSR, traps y FENCE/MMIO.
4. El modelo IMEM/DMEM de simulacion de 1 MiB no demuestra por si mismo implementacion en BRAM fisica ni timing FPGA.

## Referencias de evidencia

Los valores detallados figuran en `resultados_51_ACT4.csv` y las huellas SHA-256 de los paquetes fuente en `sha256_archivos_historicos.txt`.
