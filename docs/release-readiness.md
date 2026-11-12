# Estado de preparación de la entrega

Este documento controla la preparación de la plataforma
RV64I reutilizable para su distribución desde GitHub.

Rama de distribución: `main`.
Rama de desarrollo conservada: `entrega/plataforma-reutilizable`.

Corte técnico de reconstrucción: `86fb682`.
Integración inicial en `main`: `c745409`.
La etiqueta definitiva identificará la revisión publicada.

## 1. Uso de la plataforma

- [Introducción y comandos](../README.md)
- [Instalación y primer uso](getting-started.md)
- [Interfaz para aceleradores](expansion-interface.md)
- [Plataforma FPGA KV260](fpga-kv260.md)
- [Reconstrucción del firmware](rebuild-kv260-firmware.md)

## 2. Estado de verificación

Las campañas funcionales y FPGA históricas conservan
sus evidencias y criterios de aceptación originales.

La campaña D.6.8 reconstruyó la implementación KV260
desde una copia independiente de la rama de entrega.

Resultados posteriores a routing:

- WNS de setup: +1,245 ns.
- WHS de hold: +0,012 ns.
- DRC: cero violaciones.
- Metodología: cero violaciones.
- UltraRAM: 32 utilizadas.

La reconstrucción del bitstream y del paquete PL_FLAT
también fue comprobada posteriormente.

Estas actividades no sustituyen la validación física
histórica de la KV260.

## 3. Artefactos FPGA

Se distinguen dos categorías:

**Firmware histórico validado:**

Conserva las evidencias de ejecución física en KV260.

**Firmware reconstruido:**

Generado y empaquetado desde la implementación
reproducida. No fue probado físicamente de nuevo.

Las dos versiones tienen bitstreams con SHA-256
diferentes y no deben presentarse como idénticos.

## 4. Política de distribución propuesta

- Código, herramientas y documentación autorizados:
  repositorio Git.
- Binarios FPGA autorizados: archivos de una
  GitHub Release.
- Versiones: identificadas mediante etiquetas Git.
- Integridad: manifiestos y SHA-256.
- Dependencias AMD: documentadas separadamente.

La publicación de cualquiera de estos componentes
depende de contar con los permisos correspondientes.

## 5. Condiciones pendientes de liberación

- [ ] Confirmar titularidad y autorización del código.
- [ ] Elegir y aprobar la licencia del repositorio.
- [ ] Revisar atribuciones y licencias de terceros.
- [ ] Resolver autorización para redistribuir firmware.
- [x] Completar revisión estática de documentación (D.7.d).
- [ ] Conciliar objetivos y entregables del TFG.
- [x] Integrar la rama de entrega en `main` (D.7.h).
- [ ] Crear etiqueta de versión y GitHub Release.
- [ ] Verificar descarga desde GitHub.

## 6. Estado actual

Código y documentación: integrados en `main`.
GitHub Release: pendiente de preparación.
Firmware de terceros: sujeto a las condiciones de
redistribución aplicables.

Este documento no concede una licencia, no sustituye
la autorización institucional y no certifica que los
artefactos puedan publicarse.
