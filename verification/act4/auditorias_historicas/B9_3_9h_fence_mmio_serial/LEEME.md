# B.9.3.9h — Orden observable FENCE/MMIO (ensayo dirigido)

## Objetivo
Evaluar si el núcleo original mantiene el orden de tres accesos al puerto MMIO
bajo esperas del periférico. Se compara un programa con `FENCE IORW,IORW` y
otro con las dos instrucciones sustituidas por NOP. No se atribuye todo el
orden observado a FENCE ni se declara cumplimiento pleno RVWMO.

## Requisitos
Ubuntu, núcleo en el commit `cf78be1` e Icarus, Make y Python instalados.
Las fuentes RTL originales y modelo IMEM se verifican mediante SHA-256.

## Instrucciones

```bash
tar -xzf "$HOME/Descargas/B9_3_9h_fence_mmio_serial.tar.gz" -C "$HOME/TFG_tools"
bash -n "$HOME/TFG_tools/B9_3_9h_fence_mmio_serial/ejecutar_B9_3_9h.sh"
bash "$HOME/TFG_tools/B9_3_9h_fence_mmio_serial/ejecutar_B9_3_9h.sh"
```

Resultados: `~/TFG_tools/B9_3_9h_resultados.tar.gz`.
Si falla, no se altera RTL; revisar `logs/*.compile.log` y `logs/*.log` del paquete.

## Criterio de paso
Ambas variantes deben terminar sin errores; en cada una, el monitor debe ver:

1. `SW x2,0(x1)` a `0x10000000`, valor 0x55; latencia simulada 6 ciclos.
2. `LW x3,0(x1)` a `0x10000000`, retorno 0x55; latencia 4 ciclos.
3. `SW x3,8(x1)` a `0x10000008`, valor 0x55; latencia 7 ciclos.

No deben existir transacciones adelantadas, accesos DMEM inesperados ni traps.
El monitor comprueba `mem_exp_wait_stall` y `pipeline_stall` durante las esperas.

Nota: no hay instrumento externo para comprobar visibilidad global en caches,
multiples harts o DMA. Si se cambia la arquitectura o el interconector FPGA,
se debe verificar el ordenamiento de nuevo.
