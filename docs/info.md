## How it works

This is an All-Digital Phase-Locked Loop (ADPLL) that locks an internal ring oscillator to an external 32.768 kHz crystal reference, synthesizing a 16.777216 MHz output clock (x512 frequency multiplication).

### Block Diagram

```
                          +---------------------------+
  ref_clk  ----+--------->|  TDC (Time-to-Digital     |
  32.768 kHz   |          |  Converter)                |
               |          |  Counts DCO edges per      |
               |          |  ref_clk period             |
               |          +------------+----------------+
               |                       |  phase_error
               |                       v
               |          +---------------------------+
               |          |  PI Loop Filter            |
               |          |  Kp, Ki set via pins       |
               |          +------------+----------------+
               |                       |  dco_control[11:0]
               |                       v
               |          +---------------------------+
               |          |  DCO (Ring Oscillator)     |
               |          |  63-stage with tunable     |
               |          |  length + switchable loads  |
               |          +------------+----------------+
               |                       |  dco_clk
               |                       +-------+-------> dco_clk_out
               |                               |
               |          +---------------------------+
               |          |  Divider (/512)            |
               |          +------------+----------------+
               |                       |
               +--- should match ----> +--------> div_clk_out
                   when locked
```

### Key Components

- **TDC**: Counts rising edges of `dco_clk` between consecutive `ref_clk` rising edges. Computes `phase_error = 512 - measured_count`. Positive error means DCO is too slow.

- **PI Loop Filter**: Proportional + integral controller using arithmetic right-shifts (no multipliers). Gains are programmable via `kp_sel` and `ki_sel` pins. Includes anti-windup clamping.

- **DCO**: On silicon, a digitally-controlled ring oscillator with coarse tuning (selectable ring length, 3-63 stages) and fine tuning (switchable capacitive loads). In simulation, a behavioral delay model.

- **Lock Detector**: Asserts `locked` when `|phase_error| < 4` for 16 consecutive reference cycles. De-asserts after 4 consecutive out-of-range cycles (hysteresis).

- **Divider**: Divide-by-512 counter on the DCO output. When locked, `div_clk_out` should match `ref_clk`.

### Design Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| DCO_WIDTH | 12 | DCO control word width |
| COUNT_WIDTH | 16 | TDC counter width |
| TARGET_COUNT | 512 | Expected DCO cycles per ref period |
| LOCK_THRESHOLD | 4 | Max |error| for lock |
| LOCK_COUNT | 16 | Consecutive good cycles to lock |

## How to test

### Pin Configuration

1. Connect a 32.768 kHz crystal oscillator to `ui_in[0]` (ref_clk)
2. Set loop gains via `ui_in[3:1]` (kp_sel) and `ui_in[6:4]` (ki_sel):
   - Recommended starting point: kp_sel=2, ki_sel=4
   - Lower values = higher gain = faster lock but less stable
   - Higher values = lower gain = slower lock but more stable
3. Assert `ui_in[7]` (loop_enable) to start the PLL

### Observing Operation

- `uo_out[0]`: DCO clock output (~16.777 MHz when locked)
- `uo_out[1]`: DCO / 512 — should match ref_clk frequency when locked
- `uo_out[2]`: Lock indicator (high = locked)
- `uo_out[3]`: Phase error sign (0 = DCO slow, 1 = DCO fast)
- `uo_out[7:4]`: Lower 4 bits of |phase_error| (should be near 0 when locked)
- `uio_out[7:0]`: Upper 8 bits of DCO control word (for debug)

### Expected Behavior

1. After enabling, the DCO starts at its midrange control word
2. The loop adjusts the control word to minimize phase error
3. Lock should be acquired within ~300 reference cycles (~9 ms)
4. Once locked: phase error oscillates between 0-2, `locked` stays high
5. `div_clk_out` frequency matches `ref_clk` within the DCO's quantization limit

### Simulation

```bash
# cocotb tests (recommended)
cd test && make

# Local iverilog simulation (behavioral model)
make sim

# View waveforms
gtkwave adpll.vcd
```

## External Hardware

- 32.768 kHz crystal oscillator module connected to `ui_in[0]`
- Optional: frequency counter on `uo_out[0]` to verify output frequency
- Optional: logic analyzer to observe lock acquisition transient
