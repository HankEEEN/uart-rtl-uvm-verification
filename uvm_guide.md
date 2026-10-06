# Practical UVM Workflow for an RTL Project

This guide describes a reusable, industry-style flow for building a UVM testbench from an RTL design. The UART in this repository is the running example. The flow deliberately avoids `randomize()` and covergroups because the installed Questa Intel FPGA Starter Edition does not license the constrained-random features normally used by a full commercial UVM environment.

## 1. Start with the specification, not the testbench

Before writing classes, turn the design specification into a verification plan. For every feature, record:

- the requirement being checked;
- legal and illegal inputs;
- stimulus needed to exercise it;
- the observable result;
- the checker or assertion that decides pass/fail;
- the coverage evidence required for closure.

For this UART, the principal requirements are:

| Feature | Stimulus | Expected result | Coverage evidence |
|---|---|---|---|
| Reset | Assert reset before and between frames | Interfaces return to idle and later traffic succeeds | At least two reset observations |
| Baud selection | 4800 through 128000 | Transfer completes at every supported divider | One hit per baud |
| Unsupported baud | Example: 12345 | Clock generator uses its documented 9600 fallback | Unsupported/default bin hit |
| Word length | 5, 6, 7, and 8 bits | Only the selected low data bits are transmitted and received | One hit per length |
| Parity | Disabled, even, and odd | Serial parity bit matches an independent prediction | One hit per mode |
| Stop bits | One and two | Required stop intervals remain high | One hit per mode |
| Data patterns | `00`, `FF`, `AA`, `55`, and varied values | No stuck-at, order, or masking errors | Directed corner tests plus varied data |
| Back-to-back operation | Consecutive sequence items | No duplicated, dropped, or overlapping frame | Transfer count and per-item checks |

Negative tests such as bad parity, framing errors, false start bits, and line break require a dedicated RX serial driver. `uart_top` exposes conventional `tx` and `rx` pins; the current testbench connects them in loopback. A future RX agent can replace that testbench loopback and drive malformed frames without changing the RTL or faking failures in the scoreboard.

## 2. Understand the RTL boundary

List clocks, resets, configuration inputs, handshakes, data paths, and error outputs. Confirm whether reset is synchronous or asynchronous and which clock samples every control. For a multi-clock design such as this UART, explicitly identify the 50 MHz input clock, baud-rate TX clock, and 16-times-baud RX clock.

Also compile the RTL before investing in testbench code. Compilation catches structural problems that no sequence can solve. In this project, the integrated top needed a correct TX-to-RX loopback connection and a missing instance terminator before UVM could elaborate it.

## 3. Choose the testbench architecture

Use a conventional hierarchy:

```text
uart_test
`-- uart_env
    |-- uart_agent
    |   |-- uart_sequencer
    |   |-- uart_driver
    |   `-- uart_monitor
    |-- uart_scoreboard
    `-- uart_coverage
```

Responsibilities should remain separate:

- The **sequence item** describes one operation and its observed result.
- A **sequence** selects operations and their order; it does not toggle pins.
- The **sequencer** arbitrates sequence items.
- The **driver** converts one requested operation into pin activity and always calls `item_done()`.
- The **monitor** passively reconstructs operations from pins and creates a new object for every published observation.
- The **scoreboard** predicts expected behavior independently and reports mismatches with `uvm_error`.
- The **coverage collector** records whether the verification-plan space was exercised.
- The **agent** packages protocol components and supports active/passive configuration.
- The **environment** connects analysis ports to subscribers.
- The **test** configures the environment, starts a high-level scenario, and controls objections.
- The HDL **top module** instantiates the interface and DUT, generates clocks, publishes the virtual interface, and calls `run_test()`.

## 4. Define the transaction at the protocol level

Model intent rather than individual signal edges. A UART transaction contains data, baud, word length, parity configuration, and stop-bit selection. Reset is represented as a distinct item kind. Monitor-only fields hold decoded serial data, received data, framing status, completion, and error observations.

Keep driver and monitor roles clear. The driver must not declare the transfer correct; it only applies stimulus and bounds its wait with a timeout. The monitor must not reuse one transaction object for multiple `analysis_port.write()` calls because subscribers can retain the handle.

## 5. Build reusable sequences

A professional sequence library favors small scenarios and shared helpers over many copy-pasted classes. In `uart_uvm.sv`:

- `uart_base_sequence` owns `send_reset()` and `send_frame()`;
- focused sequences cover boot reset, data corners, baud sweep, format sweep, and reset recovery;
- `uart_regression_sequence` composes those focused sequences.

This structure supports small debug runs and a complete regression without duplicating transaction setup.

### Deterministic stimulus on a limited simulator

Normally, legal fields would be declared `rand`, constrained, randomized, and measured with functional coverage. Here, deterministic enumeration provides stronger reproducibility and avoids unavailable licenses:

- enumerate every small legal set, such as the four lengths and three parity modes;
- sweep every baud explicitly;
- use directed boundary patterns;
- use a fixed-seed LFSR for additional varied data;
- maintain coverage counters and fail the test when a required bin is absent.

Do not use `$urandom` merely to look random. A fixed algorithm and explicit coverage target make failures reproducible and the verification intent reviewable.

## 6. Design the driver defensively

The driver should:

1. establish safe values before requesting an item;
2. drive only on an agreed edge;
3. hold start controls until the DUT acknowledges them;
4. release controls promptly to prevent duplicate transfers;
5. use a baud-aware timeout;
6. report a timeout as a UVM error instead of hanging forever;
7. call `item_done()` exactly once for every `get_next_item()`.

Avoid unbounded waits such as `@(posedge done)` unless another mechanism guarantees simulation termination.

## 7. Make checking independent

Loopback alone can hide paired TX/RX bugs. If TX produces the wrong parity and RX expects the same wrong parity, received data still appears correct. The UART monitor therefore decodes the internal serial TX line in addition to observing `rx_out`. The scoreboard independently predicts:

- the data mask for 5–8 bit words;
- LSB-first serial payload;
- even or odd parity;
- valid start and stop levels;
- successful TX/RX completion;
- absence of unexpected error indications.

Use `uvm_error` or `uvm_fatal` for failed requirements. A message saying "Test Failed" at `UVM_INFO` severity still produces a passing UVM summary and is not an acceptable checker.

## 8. Plan coverage and closure

Coverage answers "did we test it?" while the scoreboard answers "did it work?" Keep both. The current collector maintains bins for:

- all eight supported bauds and one fallback baud;
- lengths 5, 6, 7, and 8;
- no parity, even parity, and odd parity;
- one and two stop bits;
- every `length x parity x stop2` format combination.

Its `check_phase` reports a UVM error for any missing required bin or format-cross combination. On a full simulator, these counters can be replaced or supplemented with covergroups and additional meaningful crosses.

## 9. Assemble files in dependency order

Questa compiles only the files named in the project file list. The UART order is:

```text
src/clk_gen/uart_clk_gen.sv
src/uart_tx/uart_tx.sv
src/uart_rx/uart_rx.sv
src/uart_top/uart_top.sv
tb/uart_tx/uart_uvm.sv
```

Interfaces must be visible before packages/classes that reference them. Packages must be visible before modules that import them. The project entry in `scripts/projects.psd1` maps `uart_tx` to this file list and to top module `uart_tb`.

## 10. Compile, run, diagnose, repeat

From the repository root:

```powershell
.\scripts\verify_questa.cmd uart_tx
```

The wrapper compiles first, stops on compilation failure, runs the configured top, and accepts the run only when the UVM summary contains zero errors and zero fatals. Results are written below:

```text
sim/questa/runs/uart_tx/<run-id>/
|-- sim.log
`-- waves.wlf
```

Use the log first. Open the WLF only when timing or signal history is needed. Optional VCD generation is available with `+DUMP_VCD`, but WLF is normally smaller and faster in Questa.

## 11. Definition of done

A UVM environment is ready for regression when:

- compilation is warning-reviewed and error-free;
- every planned requirement has an automatic checker;
- expected failures use UVM error/fatal severities;
- every wait is bounded;
- required coverage bins close;
- the test ends through objections rather than arbitrary delays;
- the full run reports zero unexpected UVM errors and fatals;
- seeds or deterministic generators make failures reproducible;
- logs and waveforms are retained per run;
- known verification gaps are documented.

The next meaningful extension for this UART is a separate controllable RX serial agent. It would enable parity-error, framing-error, false-start, break, jitter, and reset-during-frame testing without relying on the transmitter loopback.
