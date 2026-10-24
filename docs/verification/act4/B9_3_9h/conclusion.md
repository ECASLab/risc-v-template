# B.9.3.9h: limite del ensayo FENCE y MMIO

Dos variantes de la secuencia SW → (FENCE o NOP) → LW → (FENCE o NOP) → SW
se ejecutan en core_top con 3 operaciones MMIO de distinta latencia. Se verifica
el orden visible en la salida exp_valid/exp_ready y la estabilidad durante
los wait-states; la segunda escritura usa el dato que devolvió el load anterior.

**Alcance:** solo esta secuencia de un hart en el camino de MMIO de un
sistema serializado. Que ambas variantes pasen indicaría que el orden ensayado
proviene de la disciplina de ejecución/handshake del diseño y NO demostraría
que FENCE implementa ordenamiento general ni la conformidad RVWMO con varios
observadores, DMA u otros interconectores/outstanding concurrentes.

No cambia RTL, ni redefine el soporte de Zicsr/Sm/PA.
