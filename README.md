## NxN Systolic Array Accelerator (SystemVerilog)

Small educational **NxN fixed‑point systolic array accelerator** for matrix–matrix multiplication (MMM), written in **SystemVerilog**.  

- **Technologies**: SystemVerilog RTL, Python/MATLAB for stimulus and golden models, any modern SV simulator (Xcelium / VCS / Questa / Verilator).
- **Use cases**: Experiment with systolic arrays, instruction‑driven MMM workloads, and basic PPA trade‑offs.

---

## Features

- Parameterizable **NxN** systolic array architecture with 16‑bit fixed‑point MACs.
- Separate on‑chip SRAMs for input matrix `A`, weight matrix `B`, output matrix `O`, and instruction memory `I`.
- Simple memory‑mapped top‑level interface suitable for a small CPU, firmware, or pure testbench.
- Compact integer **[a, b, c]** instruction format that encodes chained matrix–matrix multiplies.
- Designed to support experiments with array size, data width, and throughput/area trade‑offs.

---

## Quick Start

1. **Clone**
   - `git clone <this-repo-url>`
   - `cd Systolic_Array`

2. **Choose a simulator**
   - Any SystemVerilog‑capable simulator should work (Xcelium, VCS, Questa, Verilator, etc.).

3. **Generate test data and golden reference** (Python)
   - Run `python3 scripts/gen_test_data.py` from the project root.
   - This creates `tb/data/memA.hex`, `memB.hex`, `memI.hex`, and `golden_O.hex` for the testbench to load.

4. **Compile and run simulation**
   - Compile all RTL and the testbench: `rtl/top.sv`, `rtl/controller.sv`, `rtl/systolic_array.sv`, `rtl/pe.sv`, and `tb/tb_top.sv`.
   - Run with the simulator's working directory set to the project root (so paths like `tb/data/memA.hex` resolve).
   - The testbench loads the hex files, drives the DUT, and compares `memO` output to `golden_O.hex`; it reports **PASS** or **FAIL**.

---

## Top‑Level Architecture

The design is organized into four conceptual blocks:

- **Systolic Array Core**
  - Parameterizable **NxN** 2‑D array of processing elements (PEs).
  - Each PE performs **16‑bit fixed‑point multiply‑accumulate (MAC)**.
  - Input activations and weights are streamed from orthogonal directions and accumulated as they propagate.

- **On‑Chip Memories** (inferred synchronous RAM in `top.sv`)
  - `memA`: Input matrix \(A\) (size up to `DEPTH_A` words of width `DATA_W`).
  - `memB`: Weight matrix \(B\) (size up to `DEPTH_B`).
  - `memO`: Output matrix \(O\) (size up to `DEPTH_O`).
  - `memI`: Instruction memory for the MMM instruction stream (depth `DEPTH_I`, width `INSTR_W`).
  - Implemented as arrays and `always_ff` in `top.sv`; no separate memory modules.

- **Instruction Controller** (`rtl/controller.sv`)
  - Reads instructions from `memI`.
  - Decodes integer triples **[a, b, c]** that describe one matrix–matrix multiply:
    - Input matrix:  \(a \times b\)
    - Weight matrix: \(b \times c\)
    - Output matrix: \(a \times c\)
  - Sequences reads from `memA` and `memB`, streams data into the systolic array, and writes results into `memO`.
  - Supports chained MMMs (e.g., instruction sequence `[32, 16, 64, 8, 16, 0]`) to model small multi‑layer MLPs.

- **Top‑Level Wrapper (`rtl/top.sv`)**
  - Instantiates the controller and systolic array core and wires them to the internal memories.
  - Provides a clean external interface for integration with a CPU or testbench.

---

## Top‑Level Interface

The `top` module exposes a **memory‑style interface**:

- **Global control**
  - `clk`: Clock.
  - `rst_n`: Active‑low synchronous reset.
  - `ap_start`: Pulse signal to start processing the instruction stream.
  - `ap_done`: Level signal indicating all MMM operations are complete.

- **Input Matrix A Write Port**
  - `addrA[ADDR_A_W-1:0]`: Address into `memA`.
  - `enA`: Write enable.
  - `dataA[DATA_W-1:0]`: Data to be written.

- **Weight Matrix B Write Port**
  - `addrB[ADDR_B_W-1:0]`: Address into `memB`.
  - `enB`: Write enable.
  - `dataB[DATA_W-1:0]`: Data to be written.

- **Instruction Memory I Write Port**
  - `addrI[ADDR_I_W-1:0]`: Address into `memI`.
  - `enI`: Write enable.
  - `dataI[INSTR_W-1:0]`: Encoded instruction word.

- **Output Matrix O Read Port**
  - `addrO[ADDR_O_W-1:0]`: Address into `memO`.
  - `dataO[DATA_W-1:0]`: Data read from result memory.

All memories are modeled as **simple synchronous RAMs** inferred from arrays and `always_ff` write and read processes.

---

## Instruction Format

The **instruction stream** is a sequence of **non‑zero integers** stored in `memI`.  
Each group of three consecutive integers **[a, b, c]** specifies one matrix–matrix multiplication (**MMM**):

- Input matrix \(A\): \(a \times b\)
- Weight matrix \(B\): \(b \times c\)
- Output matrix \(O\): \(a \times c\)

The integer **0** marks the end of the instruction sequence (no more MMMs).

### Example: Chained MMMs

Given the instruction sequence:

```text
[32, 16, 64, 8, 16, 0]
```

This encodes three chained MMMs, where each output becomes the next input:

1. First MMM  
   - Input:  \(32 \times 16\)  
   - Weights: \(16 \times 64\)  
   - Output: \(32 \times 64\)

2. Second MMM  
   - Input:  \(32 \times 64\) (output of previous step)  
   - Weights: \(64 \times 8\)  
   - Output: \(32 \times 8\)

3. Third MMM  
   - Input:  \(32 \times 8\)  
   - Weights: \(8 \times 16\)  
   - Output: \(32 \times 16\)

This models a small 3‑layer MLP with matrix multiplies back‑to‑back.

---

## Testbench & Workload Generation

Verification uses a **Python** script for stimulus and golden data, and a **SystemVerilog testbench** that loads those files and compares results.

- **Python script** (`scripts/gen_test_data.py`)
  - Generates random 16‑bit fixed‑point matrices \(A\) and \(B\), and an instruction stream (e.g. `[N, N, N, 0]`).
  - Computes the golden output \(C = A \times B\) with NumPy and writes it to `golden_O.hex`.
  - Writes `memA.hex`, `memB.hex`, `memI.hex`, and `golden_O.hex` into `tb/data/` (one 16‑bit hex value per line for `$readmemh`).

- **SystemVerilog testbench** (`tb/tb_top.sv`)
  - Loads the hex files with `$readmemh("tb/data/memA.hex", ...)` (and similarly for B, I, and golden_O).
  - Writes A, B, and I into the DUT via the top‑level ports, pulses `ap_start`, waits for `ap_done`.
  - Reads `memO` via `addrO`/`dataO` and compares each word to the golden file; reports **PASS** or **FAIL**.

See `tb/README.md` for run commands and simulator notes.

---

## Simulation

This project is simulator‑agnostic and should work with any modern **SystemVerilog** simulator (e.g., Cadence Xcelium, Synopsys VCS, Mentor Questa, Icarus Verilog, or Verilator with appropriate flags).

1. **Generate test data** (from project root)
   ```bash
   python3 scripts/gen_test_data.py
   ```

2. **Compile**
   - Include all RTL and the testbench:
     - `rtl/top.sv`, `rtl/controller.sv`, `rtl/systolic_array.sv`, `rtl/pe.sv`
     - `tb/tb_top.sv`

3. **Run**
   - Set the simulator's working directory to the project root so that paths like `tb/data/memA.hex` resolve.
   - Run until the testbench finishes; it will print `[TB] PASS` or `[TB] FAIL` and any mismatches.
   - For Vivado XSIM batch reproduction, see `docs/VIVADO_XSIM.md`.

4. **Inspect results** (optional)
   - Dump waveforms (e.g., VCD/FSDB) if desired.
   - See `docs/RUN_WALKTHROUGH.md` for a step‑by‑step trace of data flow with file and line references.

---

## Extending the Design

Some extensions and TODOs:

- Add **performance counters**:
  - Track number of cycles per MMM.
  - Report effective throughput (GOp/s) for different N and clock frequencies.

- Explore **PPA trade‑offs**:
  - Synthesize for an FPGA or ASIC‑like library.
  - Sweep N and data width and compare area, frequency, and energy.

---

## Repository Layout

- **`rtl/`** — Core RTL
  - `top.sv`: Top-level wrapper; internal memories (memA, memB, memO, memI), controller, and systolic array.
  - `controller.sv`: FSM that fetches instructions, drives A/B reads, feeds the array, and writes O.
  - `systolic_array.sv`: N×N PE grid with feed/drain logic and output collection.
  - `pe.sv`: Single processing element (MAC and pass-through).
- **`tb/`** — Testbench
  - `tb_top.sv`: Loads Python-generated hex files, drives the DUT, compares output to golden.
  - `data/`: Generated by `scripts/gen_test_data.py` (memA.hex, memB.hex, memI.hex, golden_O.hex).
  - `README.md`: How to run the testbench and simulators.
- **`scripts/`** — Python
  - `gen_test_data.py`: Generates test matrices, instruction stream, and golden output; writes hex files to `tb/data/`.
- **`docs/`** — Documentation
  - `RUN_WALKTHROUGH.md`: End-to-end run description with a concrete matrix example and file/line references.
  - `VIVADO_XSIM.md`: Vivado XSIM reproduction guide, version notes, and batch simulation flow.

---
