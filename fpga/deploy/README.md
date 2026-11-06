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
