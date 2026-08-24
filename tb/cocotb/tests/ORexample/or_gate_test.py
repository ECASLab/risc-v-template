import cocotb
from cocotb.triggers import Timer, RisingEdge

@cocotb.test()
async def or_gate(dut):
    
    a = (0, 0, 1, 1)
    b = (0, 1, 0, 1)
    y = (0, 1, 1, 1)

    for x in range(4):
        dut.a.value = a[x]
        dut.b.value = b[x]
        await Timer (1, 'ns')

        observed = int(dut.y.value)
        expected = y[x]
 
        dut._log.info(f"iter={x} a={a[x]} b={b[x]} y={observed} expected={expected}")

        assert observed == expected, f"iter={x}: {a[x]} OR {b[x]} => {observed}, esperado {expected}"
            