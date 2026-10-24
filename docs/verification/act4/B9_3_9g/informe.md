# B.9.3.9g — trazabilidad del subconjunto CSR y traps

**Alcance:** auditoría documental/histórica, NO simulaciones nuevas ni certificación privilegiada.

- Core: `cf78be1cc7206879744f7587ab9806a508113b24`
- Fuente de regresión: paquete `B9_3_9a_resultados.tar.gz`
- Total resultados PASS de regresión: **35** (esperados 35).
- Tests dirigidos seleccionados: **15**.
- CSR declarados en RTL: **10**.
- Modificaciones RTL: ninguna.

## Límites que permanecen

- **IMEM**: B.9.3.9f-v3 demostró $fatal del modelo, no excepción arquitectural del núcleo.
- **Sm**: declarado provisionalmente en UDB para tests I; no acreditación de arquitectura privilegiada completa.
- **Zicsr**: seis instrucciones aparecen en decoder, pero la conformidad total no se ha demostrado con ACT4.
- **FENCE**: su ordenamiento frente a MMIO sigue requiriendo un ensayo específico o limitación documentada.
- **PMA y PHYS_ADDR_WIDTH**: aún requieren decisión consistente con la plataforma FPGA.

## Interpretación

Los PASS de los bancos dirigidos evidencian solo las situaciones ejercitadas por esos bancos.
La existencia de una constante o CSR en RTL es una observación estática, no una garantía funcional general.
No deben presentarse estos datos como conformidad completa con Sm, Zicsr ni control de fallos IMEM.

## Resultado

**PASS**: inventario y trazabilidad histórica consistentes.
