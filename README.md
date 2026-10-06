# UART Verification Practice

This repository is organized for small UART RTL and UVM exercises. Source files, testbenches, compile lists, generated libraries, and simulation results have separate locations so that new exercises can be added without mixing their outputs.

## Directory layout

```text
Verification of UART/
|-- src/                         Synthesizable RTL
|   |-- common/                  RTL packages shared by multiple blocks
|   |-- clk_gen/                 Original clock generator and fractional tick generator
|   |-- uart_tx/                 Original and tick-enabled UART transmitters
|   |-- uart_rx/                 Original and tick-enabled UART receivers
|   `-- uart_top/                Original and tick-enabled integrated UARTs
|-- tb/                          Interfaces and UVM testbenches
|   |-- common/                  Verification code shared by multiple tests
|   |-- clk_gen/                 UVM environments for both timing generators
|   |-- uart_uvm/                Both integrated UVMs and tick loopback smoke test
|   |-- uart_rx/                 Future receiver testbench
|   `-- uart_top/                Future integration testbench
|-- filelists/                   Ordered source lists used by vlog
|-- scripts/                     Reusable PowerShell commands for Questa
|-- sim/questa/
|   |-- libraries/uart_work/     Shared compiled Questa library
|   `-- runs/<project>/<run-id>/ Separate logs and waveforms for every run
`-- archive/legacy_clk_gen/      Original tutorial files kept for reference
```

The contents of `sim/questa/libraries`, `sim/questa/runs`, and the generated `modelsim.ini` are build artifacts. They are excluded by `.gitignore` and can be regenerated from the source files.

Two UART implementations are kept side by side:

- The original implementation uses `uart_clk_gen.sv`, `uart_tx.sv`,
  `uart_rx.sv`, and `uart_top.sv`. Its TX and RX state machines are clocked by
  the generated `tx_clk` and `rx_clk` signals.
- The tick-based implementation uses `uart_clk_gen_tick.sv`,
  `uart_tx_tick.sv`, `uart_rx_tick.sv`, and `uart_top_tick.sv`. It keeps all
  sequential logic in the 50 MHz `clk` domain and uses fractional `tx_tick`
  and `rx_tick` clock-enable pulses. The original files remain unchanged so
  the two architectures can be studied and verified independently.

## Prerequisites

Questa commands must be available in `PATH`:

```powershell
vlog -version
vsim -version
```

The current machine uses Questa Intel Starter FPGA Edition 2024.3. The clock-generator test avoids class constrained randomization because that feature requires an additional verification license in this Starter installation.

## Run the clock-generator UVM test

Open PowerShell in this repository and run:

```powershell
.\scripts\verify_questa.cmd clk_gen
```

The `.cmd` wrapper enables the checked-in PowerShell scripts for its own process only. It does not change the machine-wide execution policy.

The wrapper performs two steps:

1. `compile_questa.ps1` compiles every path in `filelists/clk_gen.f` into the shared `uart_work` library.
2. `run_questa.ps1` loads `uart_work.uart_clk_gen_tb`, runs until the UVM test finishes, and checks that the UVM summary contains zero errors and zero fatals.

Every run receives a timestamped directory such as:

```text
sim/questa/runs/clk_gen/20260922_160953_093/
|-- sim.log
`-- waves.wlf
```

The terminal also prints the exact result directory. `sim.log` contains the UVM report and `waves.wlf` can be opened later in Questa for waveform inspection.

Compilation and simulation can also be run separately:

```powershell
.\scripts\compile_questa.ps1 -Project clk_gen
.\scripts\run_questa.ps1 -Project clk_gen
```

The PowerShell script can also be called directly. If the local execution policy blocks it, enable checked-in scripts only for the current terminal session:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\verify_questa.ps1 -Project clk_gen
```

## Run the tick-generator UVM test

The tick-based generator has a separate DUT, UVM environment, and file list:

```text
src/clk_gen/uart_clk_gen_tick.sv
tb/clk_gen/uart_clk_gen_tick_uvm.sv
filelists/clk_gen_tick.f
```

The monitor publishes one sample per 50 MHz clock cycle. Its scoreboard uses
a cycle-accurate reference accumulator to detect missing, extra, or misplaced
ticks, checks the 16 RX ticks to one TX tick relationship, and exercises every
supported baud plus the unsupported-value fallback.

After the original scripted test has initialized the local Questa library and
`modelsim.ini`, compile and run the tick-generator UVM test from the repository
root with:

```powershell
vlog -modelsimini ./sim/questa/modelsim.ini -sv -work uart_work -f ./filelists/clk_gen_tick.f
vsim -c -modelsimini ./sim/questa/modelsim.ini uart_work.uart_clk_gen_tick_tb +UVM_NO_RELNOTES -do "run -all; quit -f"
```

A successful run ends with:

```text
UVM_ERROR : 0
UVM_FATAL : 0
```

The original and tick-generator UVM tests use unique module, interface, and
class names, so both versions can coexist in the shared `uart_work` library.

## How Questa finds the files

Questa does not automatically scan every `.sv` file in the repository. The project file list explicitly supplies the files and their compile order:

```text
src/clk_gen/uart_clk_gen.sv
tb/clk_gen/uart_clk_gen_uvm.sv
```

The scripts invoke `vlog` from the repository root, so entries in each `.f` file are relative to this directory. The DUT is listed before its testbench. Packages and shared interfaces should be listed before modules or classes that import them.

## Run the integrated UART UVM test

The integrated UART testbench uses deterministic stimulus because the Starter
simulator does not support constrained randomization. The RTL exposes conventional
external `tx` and `rx` pins, which this testbench connects in loopback. It checks
serial framing, loopback data, all supported baud rates, legal word lengths,
parity modes, stop bits, reset recovery, the complete format cross, and the
unsupported-baud fallback.

```powershell
.\scripts\verify_questa.cmd uart_tx
```

See [uvm_guide.md](uvm_guide.md) for the verification plan, architecture, and a
step-by-step UVM workflow.

## Run the tick-based integrated UART UVM test

The tick-enabled UART has an independent UVM environment under
`tb/uart_uvm/uart_tick_uvm.sv`. It verifies 38 completed loopback frames plus
an intentional mid-frame reset/abort, all supported baud rates and the fallback
rate, serial framing and parity, reset recovery, the complete length x parity x
stop cross, one-cycle status pulses, tick-gated state/counter updates, and the
16-to-1 RX/TX tick relationship.

Run the complete compile-and-simulate flow with:

```powershell
.\scripts\verify_questa.cmd uart_tick_uvm
```

Compilation and simulation can also be run separately:

```powershell
.\scripts\compile_questa.ps1 -Project uart_tick_uvm
.\scripts\run_questa.ps1 -Project uart_tick_uvm
```

The underlying project uses `filelists/uart_tick_uvm.f` and the top-level test
module `uart_tick_uvm_tb`. A successful run reports 38 checked transfers, one
verified mid-frame abort, closed required coverage, and zero UVM errors and
fatals.

## Compile or smoke-test the tick-based integrated UART

The tick-based TX, RX, and top-level RTL can be compiled together with:

```powershell
vlog -modelsimini ./sim/questa/modelsim.ini -sv -work uart_work -f ./filelists/uart_tick.f
```

The separate loopback smoke test covers all supported baud rates, the 9600-baud
fallback, word lengths, parity modes, and one- and two-stop-bit frames:

```powershell
vlog -modelsimini ./sim/questa/modelsim.ini -sv -work uart_work -f ./filelists/uart_tick_smoke.f
vsim -c -modelsimini ./sim/questa/modelsim.ini uart_work.uart_tick_smoke_tb -do "run -all; quit -f"
```

The procedural smoke test remains as a fast integration check. The thorough
regression for the tick-enabled protocol is the `uart_tick_uvm` project above;
the separate `uart_clk_gen_tick_uvm.sv` environment verifies the fractional
tick generator cycle by cycle.

## Add another verification project

For another verification exercise:

1. Implement the RTL under `src/`.
2. Add its interface, UVM classes, and top module under `tb/`.
3. Create a file list in dependency order.
4. Add a project entry to `scripts/projects.psd1`:

```powershell
uart_tx = @{
    FileList = "filelists/new_project.f"
    Top      = "new_project_tb"
    IsUvm    = $true
}
```

5. Run:

```powershell
.\scripts\verify_questa.cmd new_project
```

All projects share the compiled `uart_work` library. Use unique names for top modules, interfaces, packages, and classes. Recommended names include `uart_tx_tb`, `uart_tx_if`, `uart_tx_uvm_pkg`, and `uart_tx_item`.

## Legacy tutorial files

The original `clk_gen.sv` and `clk_gen_uvm.sv` are stored under `archive/legacy_clk_gen`. They demonstrate the earlier tutorial implementation and are excluded from the active file list because the current `uart_clk_gen` project contains the corrected TX divider, the 16-times-baud RX clock, and the verified UVM environment.
