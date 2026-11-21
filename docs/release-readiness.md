# Estado de publicación y condiciones pendientes

Este documento registra la publicación de la plataforma
RV64I y las condiciones que siguen pendientes de confirmación.

Rama principal vigente: `main`.
La rama histórica `entrega/plataforma-reutilizable`
se utilizó durante la preparación de la entrega.

Corte técnico de reconstrucción: `86fb682`.
Integración inicial en `main`: `c745409`.
Publicación `v1.0.0`: `73694be`.
Limpieza posterior de `main`: `ba29e03`.

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

## 4. Distribución publicada y condiciones de uso

- Código, herramientas y documentación:
  repositorio Git.
- Binarios FPGA: archivos publicados en
  [GitHub Release v1.0.0](https://github.com/ECASLab/risc-v-template/releases/tag/v1.0.0).
- Versiones: identificadas mediante etiquetas Git.
- Integridad: manifiestos y SHA-256.
- Dependencias AMD: documentadas separadamente.

Los archivos fueron publicados. Esto no acredita por sí mismo
la titularidad, las licencias ni los permisos de redistribución.

## 5. Hitos de publicación y condiciones por confirmar

- [ ] Confirmar titularidad y autorización del código.
- [ ] Elegir y aprobar la licencia del repositorio.
- [ ] Revisar atribuciones y licencias de terceros.
- [ ] Resolver autorización para redistribuir firmware.
- [x] Completar revisión estática de documentación (D.7.d).
- [x] Conciliar objetivos y entregables del TFG.
  Referencia: [especificación técnica](technical-specification.md), sección 7.
  Consolidación documental retrospectiva; no implica nuevas pruebas.
- [x] Integrar la rama de entrega en `main` (D.7.h).
- [x] Crear etiqueta de versión y GitHub Release (`v1.0.0`).
- [ ] Verificar descarga desde GitHub.

## 6. Estado actual

Código y documentación: integrados en `main`.
GitHub Release: `v1.0.0`, publicada desde `73694be`.
Las evidencias conservan las revisiones originales
de las campañas de validación documentadas.
El firmware reconstruido no fue validado nuevamente
en hardware. Las condiciones de redistribución de
terceros siguen sujetas a confirmación.

Este documento no concede una licencia, no sustituye
la autorización institucional y no certifica que los
artefactos puedan publicarse.
