import cocotb
from cocotb.triggers import Timer

@cocotb.test()                   # Decorador: Marca esto como una función de prueba Cocotb
async def test_adder(dut):       # Corutina asíncrona; 'dut' es el Diseño Bajo Prueba (el módulo adder). Usa asyncio de Python para manejar tiempo de simulación (ej., delays).
   
    """Prueba simple de un adder de 4 bits"""

    # No necesitamos reloj para lógica combinacional, pero agregamos un reset opcional o delay inicial
    await Timer(20, unit="ns")  # Delay inicial para estabilizar (espera 20 nanosegundos)

    # Pruebas
    for i in range(16):  # Prueba todas las combinaciones de 0-15
        a_val = i
        b_val = 15 - i  # Para variar (ej., i=0 -> b=15; i=1 -> b=14, etc.)
        dut.a.value = a_val # Establece entrada 'a' en el DUT
        dut.b.value = b_val # Establece entrada 'b'

        await Timer(10, unit="ns")  # Espera un pequeño delay para propagación combinacional (espera a que las señales se estabilicen)

        expected_sum = a_val + b_val        # Calcula el resultado esperado en Python
        observed_sum = int(dut.sum.value)   # Lee la salida 'sum' del DUT (convierte a int)

        dut._log.info(f"Probando {a_val}+{b_val}: Observado = {observed_sum}, Esperado = {expected_sum}")
        
        assert observed_sum == expected_sum, f"Error: {a_val} + {b_val} = {observed_sum}, esperado {expected_sum}"  # Verifica y lanza error si no coincide

    dut._log.info("Todas las pruebas pasaron!") # Registra éxito
