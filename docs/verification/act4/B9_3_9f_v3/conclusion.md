# B.9.3.9f-v3: integración core_top + IMEM original

La prueba válida comprueba la primera respuesta de instrucción consumible por el frontend.
Los cuatro casos negativos parten desde un RESET_PC fuera del rango de un modelo IMEM de 256 bytes.
En ellos, PASS indica **que el núcleo emite un fetch inválido y el modelo de simulación se detiene mediante $fatal**.
No se acredita un trap arquitectural ni el soporte de `instruction access fault` por `core_top`.
La ausencia de entrada `imem_error` sigue pendiente; no se altera RTL ni configuración ACT4.
Esta prueba no fija PHYS_ADDR_WIDTH ni sustituye una futura verificación en FPGA.
