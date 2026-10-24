# B.9.3.9e-v3: caracterización aislada del modelo IMEM

- Version v3 evita `string` en selector SV por una incompatibilidad conocida de Icarus 12.0.
- Dos lecturas de memoria válidas y seis condiciones inválidas contrastadas en IMEM de cuatro palabras (16 bytes).
- En las seis condiciones inválidas, PASS indica solamente un `$fatal` previsto del **modelo de memoria**.
- **No implica `instruction access fault` arquitectural ni validación de un trap de `core_top`.**
- `core_top` carece de `imem_error`, por lo que el tratamiento físico de fetch inválido continúa pendiente.
- No se ha determinado `PHYS_ADDR_WIDTH` de la implementación en FPGA.
- La ejecución no modifica fuentes RTL, UDB ni Sail.
