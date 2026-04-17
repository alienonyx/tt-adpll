import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge, ClockCycles

GATE_LEVEL = os.environ.get("GATES", "no") == "yes"


# Reference clock: 32.768 kHz -> half-period ~15259 ns
REF_HALF_PERIOD_NS = 15259
REF_PERIOD_NS = REF_HALF_PERIOD_NS * 2


async def ref_clk_gen(dut, config_bits):
    """Generate 32.768 kHz reference clock on ui_in[0].

    config_bits sets ui_in[7:1] (gains + enable). Bit 0 is toggled
    as the reference clock.
    """
    while True:
        dut.ui_in.value = config_bits | 1   # ref_clk high
        await Timer(REF_HALF_PERIOD_NS, units="ns")
        dut.ui_in.value = config_bits & ~1  # ref_clk low
        await Timer(REF_HALF_PERIOD_NS, units="ns")


def decode_outputs(dut):
    """Decode uo_out and uio_out into meaningful signals."""
    raw = dut.uo_out.value
    if not raw.is_resolvable:
        return None
    val = raw.integer
    uio = dut.uio_out.value.integer if dut.uio_out.value.is_resolvable else 0
    return {
        "dco_clk":    (val >> 0) & 1,
        "div_clk":    (val >> 1) & 1,
        "locked":     (val >> 2) & 1,
        "err_sign":   (val >> 3) & 1,
        "err_low":    (val >> 4) & 0xF,
        "dco_hi":     uio,
    }


@cocotb.test()
async def test_reset(dut):
    """Outputs should be deterministic during and after reset."""
    dut._log.info("Starting reset test")

    # Drive defaults
    dut.rst_n.value = 0
    dut.ena.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0

    # Use system clock as time reference only (ADPLL doesn't use it)
    clock = Clock(dut.clk, 20, units="ns")  # 50 MHz
    cocotb.start_soon(clock.start())

    await ClockCycles(dut.clk, 20)

    out = decode_outputs(dut)
    if out is not None:
        assert out["locked"] == 0, "Should not be locked during reset"

    # Release reset but keep loop disabled
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 20)

    out = decode_outputs(dut)
    if out is not None:
        assert out["locked"] == 0, "Should not be locked when disabled"

    dut._log.info("Reset test passed")


@cocotb.test()
async def test_adpll_lock(dut):
    """ADPLL should acquire lock within 350 reference clock cycles."""
    if GATE_LEVEL:
        dut._log.info("GL mode: skipping lock test (DCO ring oscillator "
                       "requires real gate delays, not unit-delay simulation)")
        return
    dut._log.info("Starting ADPLL lock test")
    dut._log.info("Target: 32.768 kHz x 512 = 16.777216 MHz")

    # System clock (time reference for cocotb, not used by ADPLL core)
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.rst_n.value = 0
    dut.ena.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await Timer(REF_PERIOD_NS * 3, units="ns")

    # Release reset
    dut.rst_n.value = 1
    await Timer(REF_PERIOD_NS * 2, units="ns")

    # Enable: kp_sel=2 (Kp=1/4), ki_sel=4 (Ki=1/16)
    #   ui_in[7]   = loop_enable = 1
    #   ui_in[6:4] = ki_sel = 3'b100
    #   ui_in[3:1] = kp_sel = 3'b010
    #   ui_in[0]   = ref_clk (toggled by coroutine)
    config = (1 << 7) | (4 << 4) | (2 << 1)  # 0xC4
    dut.ena.value = 1

    # Start reference clock generation
    cocotb.start_soon(ref_clk_gen(dut, config))

    # Wait for lock (up to 350 ref cycles, ~10.7 ms sim time)
    locked = False
    lock_cycle = 0
    for cycle in range(350):
        await Timer(REF_PERIOD_NS, units="ns")
        out = decode_outputs(dut)
        if out is not None and out["locked"]:
            locked = True
            lock_cycle = cycle + 1
            dut._log.info(f"LOCKED after {lock_cycle} ref cycles")
            break
        if (cycle + 1) % 50 == 0:
            dut._log.info(f"  cycle {cycle+1}: not yet locked")

    assert locked, "ADPLL failed to lock within 350 ref cycles"

    # Verify lock holds for 20 more cycles
    lock_lost = False
    for i in range(20):
        await Timer(REF_PERIOD_NS, units="ns")
        out = decode_outputs(dut)
        if out is not None and not out["locked"]:
            lock_lost = True
            dut._log.error(f"Lock lost at +{i} cycles after lock")
            break

    assert not lock_lost, "Lock was not stable"
    dut._log.info(f"Lock stable for 20 cycles after acquisition at cycle {lock_cycle}")
    dut._log.info("ADPLL lock test passed")
