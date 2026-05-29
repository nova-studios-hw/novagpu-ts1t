# NovaGPU TS 1T

<div align="center">

**An open-source GPU architecture built from scratch in Verilog RTL**  
*Nova Studios*

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Verilog](https://img.shields.io/badge/Verilog-2001--2012-blue.svg)](https://ieeexplore.ieee.org/document/6012607)
[![Simulation](https://img.shields.io/badge/Simulation-Icarus%20Verilog-green.svg)](https://github.com/steveicarus/iverilog)
[![Tests](https://img.shields.io/badge/Tests-35-blue.svg)](sim/tb_maestro_v12.v)
[![FPGA](https://img.shields.io/badge/FPGA-Arty%20A7--100T-orange.svg)](https://digilent.com/reference/programmable-logic/arty-a7/start)
[![Reddit](https://img.shields.io/badge/Reddit-r%2FFPGA-FF4500)](https://www.reddit.com/r/FPGA/comments/1tpccbz/experimental_tokendriven_gpu_architecture_in/)

### ⚠️ ACTIVE DEVELOPMENT — RTL VALIDATION PHASE

**37 tests implemented · 19 passing · 51% functional coverage**  
*FPGA demo currently in progress.*

</div>

---

# 📖 Table of Contents

- [What is NovaGPU TS 1T?](#what-is-novagpu-ts-1t)
- [Architecture — N.E.O.N.](#architecture--neon)
- [Full Pipeline Diagram](#full-pipeline-diagram)
- [Experimental Technologies](#experimental-technologies)
- [Module Reference](#module-reference)
- [Hardware Specifications](#hardware-specifications)
- [Current Status & Test Coverage](#current-status--test-coverage)
- [FPGA Synthesis Validation](#fpga-synthesis-validation)
- [How to Run Simulations](#how-to-run-simulations)
- [FPGA Implementation](#fpga-implementation)
- [ASIC Roadmap](#asic-roadmap)
- [Why This Project Exists](#why-this-project-exists)
- [Important Technical Clarifications](#important-technical-clarifications)
- [License](#license)
- [Contact](#contact)

---

# FPGA Synthesis Validation

## Successful Hardware Synthesis Milestone

NovaGPU TS 1T successfully synthesized the `triangle_rasterizer and token_matching_unit` module using **Yosys** targeting Xilinx FPGA architectures.

This validates that the raster pipeline is not only simulated, but also structurally compatible with real FPGA implementation flows.

### Current Verified Results

| Metric | Result |
|--------|--------|
| RTL Synthesis | ✅ Successful |
| Top Module Resolution | ✅ Successful |
| CHECK Pass | ✅ 0 Errors |
| FPGA Logic Estimation | ✅ Generated |
| DSP48E1 Inference | ✅ Confirmed |
| Functional Verification Coverage | ✅ 51% |
| Triangle Rasterizer | ✅ FPGA Synthesizable |

---

## Yosys Synthesis Snapshot

```text
=== triangle_rasterizer ===

Estimated number of LCs: 5201

Cells:
- DSP48E1 : 20
- LUT6    : 3074
- CARRY4  : 1353

CHECK pass:
Found and reported 0 problems.

=== token_matching_unit ===

6.51. Executing CHECK pass (checking for obvious problems).
Checking module token_matching_unit...
Found and reported 0 problems.

7. Printing statistics.



        +----------Local Count, excluding submodules.
        |
     6851 wires
    17421 wire bits
      143 public wires
     5487 public wire bits
       11 ports
      437 port bits
    14279 cells
        1   BUFG
       15   CARRY4
     5014   FDCE
        1   FDPE
      272   FDRE
      147   IBUF
     5036   INV
      796   LUT2
      387   LUT3
      106   LUT4
       93   LUT5
     1899   LUT6
      166   MUXF7
       56   MUXF8
      290   OBUF

Warnings: 4 unique messages, 4 total
End of script. Logfile hash: 538a8b7715
Yosys 0.65+67 (git sha1 1801abf30-dirty, x86_64-w64-mingw32-g++ 13.2.1 -O3)
Time spent: 1% 30x opt_expr (0 sec), 1% 19x read_verilog (0 sec), ...
