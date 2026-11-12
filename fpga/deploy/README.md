# Estado actualizado de despliegue KV260 (2026-11-06)

El paquete `PL_FLAT` `tfg-rv64i-kv260` fue instalado y cargado
satisfactoriamente en la Kria KV260 con DFX Manager 2023.1. El overlay
`tfg-rv64i-kv260_image_1` se aplicó. Linux reportó `pl0_ref=58823529 Hz`.
La aplicación ARM obtuvo una **primera ejecución PASS** con `RESULT_FLAG=1`.
Los hashes y límites del ensayo se documentan en
`docs/verification/fpga/kria_p2_9_4/RESULTADOS_PRIMERA_EJECUCION.md`.

Actualización del 11 de noviembre de 2026: se completaron dos ejecuciones físicas satisfactorias del programa de demostración con `RESULT_FLAG=1`. La segunda ejecución confirmó `CONTROL=0` y se restauró `k26-starter-kits` al slot 0.
La restauración se comprobó mediante DFX Manager, servicios activos y lecturas térmicas. No se acreditó una prueba funcional exhaustiva del overlay original ni medición independiente de RPM.
Informe actualizado: `docs/verification/fpga/cierre_kv260_20261111/README.md`.

Para nuevos usuarios, consultar la
[guía FPGA KV260](../../docs/fpga-kv260.md).

La sección histórica inferior conserva la decisión anterior de no
versionar binarios FPGA. La distribución final desde GitHub está en
preparación y requiere confirmar autorización y condiciones de licencia.
No interpretar aquella decisión histórica como el estado definitivo
de la entrega.
No modificar `default_firmware` ni suponer control de ventilador validado
por lectura RPM.

---

## Registro histórico de la fase previa a la primera carga

# Firmware candidato: no desplegar sin revisión

Fuentes DTS y shell.json del diseño PL_FLAT de KV260. El DTS fue
corregido (bus `/axi`: `#address-cells=2`, `#size-cells=2`) y compiló
sin advertencias de dtc. Se confirmó en la placa el servicio
`dfx-mgr 2023.1+5918fb3-0ubuntu0xlnx2`, pero **no se ha probado aún la
aplicación del overlay ni el soporte PL_FLAT de ese binario concreto**.

SHA256 bitstream corregido `.bit`:
`c303e68e380a66a1fec1d9c9be1ff4c1aee22c0beddafa2d86cae7c33878c3da`

SHA256 `.bit.bin`:
`a7d0e3c7990d188fc616a2544030935fd1ed77b999a3243bd984430530c27cd6`

SHA256 DTS anterior parcheado y compilado: revisar manifiesto de la
transferencia. No versionar `.bit`, `.bit.bin`, `.xsa` dentro del
repositorio normal: conservarlos en el paquete de transferencia y en un
respaldo separado, vinculados por SHA256.

Antes de aplicar: verificar reloj físico PL0, control de ventilador,
concurrencia con overlay `k26-starter-kits_image_1` y restauración.
No cambiar QSPI, U-Boot ni arranque persistente.
