<div align="center">

# NovaGPU TS 1T

### Experimental GPU Rendering Pipeline in Verilog RTL

Nova Studios / Maximal Technology

Discord Server: https://discord.gg/RfQwz8ySr

[![License](https://img.shields.io/badge/License-MIT-yellow.svg)]()
[![RTL](https://img.shields.io/badge/RTL-Verilog-blue.svg)]()
[![Vivado](https://img.shields.io/badge/Vivado-2023.1-green.svg)]()
[![Simulation](https://img.shields.io/badge/Tests-33%2F37_Passed-brightgreen.svg)]()
[![Synthesis](https://img.shields.io/badge/Synthesis-Passed-success.svg)]()
[![Implementation](https://img.shields.io/badge/Implementation-Passed-success.svg)]()
[![Bitstream](https://img.shields.io/badge/Bitstream-Generated-success.svg)]()

</div>

---

# Project Status

Current development status:

| Stage | Status |
|---------|---------|
| RTL Development | ✅ Complete |
| Simulation | ✅ Functional |
| Test Coverage | ✅ 33 / 37 Tests Passing |
| Synthesis | ✅ Successful |
| Place & Route | ✅ Successful |
| Bitstream Generation | ✅ Successful |
| FPGA Hardware Validation | ⏳ Pending |
| VGA Output Verification | ⏳ Pending |

---

# Latest Simulation Results

Testbench:

sim/tb_novagpu_v12.v

Results:

Total Tests : 37

Passed : 33

Failed : 4

Success Rate : 89%

Passing Groups:

- Triangle Rasterizer (8/10)
- Shader Cluster (5/5)
- BVH Traversal (5/5)
- SRAM Controller (5/5)
- Budget Controller
- Motion Vector Unit
- Most Top-Level Integration Tests

Remaining Failures:

- A5 – Degenerate Triangle Handling
- A6 – Partial Clipping
- B1 – Token Matching Fire Logic
- B2 – Token Matching Data Output
- F2 – Top-Level Frame Completion Propagation

---

# Recent Milestones (May 2026)

- Triangle rasterizer emits pixels successfully
- Framebuffer image generated from RTL simulation
- PPM output verified using IrfanView
- 86% simulation pass rate achieved
- Vivado synthesis completed successfully
- Vivado implementation completed successfully
- FPGA bitstream generated successfully

---

# Architecture Overview

NovaGPU TS 1T is an experimental graphics pipeline implemented entirely in synthesizable Verilog RTL.

Current pipeline:

PCIe Input
    ↓
Token Matching Unit (TMU)
    ↓
Shader Cluster
    ↓
Budget Controller
    ↓
Three Tracing Unit (TTU)
    ↓
Tile Arbiter
    ↓
Dual-Port SRAM
    ↓
Motion Vector Unit (MVU)
    ↓
Framebuffer Output

Additional rasterization path:

Triangle Rasterizer
    ↓
Tile Arbiter
    ↓
SRAM Framebuffer

---

# FPGA Results

Target Device:

Xilinx Artix-7 xc7a100tcsg324-1

Vivado Version:

2023.1

Implementation Results:

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| LUTs | 2602 | 63400 | 4.10% |
| Registers | 2380 | 126800 | 1.88% |
| RAMB36E1 | 120 | 135 | 88.89% |
| DSP48E1 | 19 | 240 | 7.92% |
| IOB | 20 | 210 | 9.52% |

Power:

171 mW

Status:

- Synthesis: PASS
- Implementation: PASS
- Bitstream Generation: PASS

---

# Generated Framebuffer

The rasterizer currently generates framebuffer data during RTL simulation.

A framebuffer image is produced in PPM format and can be viewed using standard image viewers such as IrfanView.

Example output:

frame.ppm


Execution commands
Project location:
cd [your project location]

Verilog build command
iverilog -g2012 -o novagpu_sim sim/tb_novagpu_v12.v rtl/*.v

Test
vvp novagpu_sim
---

# Roadmap

Short Term:

- Fix remaining 5 simulation failures
- Improve rasterizer clipping
- Improve TMU matching logic
- Complete top-level frame_done propagation

Mid Term:

- VGA framebuffer output
- OpenGL visualization driver
- Cube rendering demonstration

Long Term:

- FPGA hardware validation
- HDMI output
- PCIe host communication
- Expanded ray tracing pipeline

---

# License

MIT License

Copyright © 2026 Nova Studios / Maximal Technology

---

<div align="center">

Built in RTL.

Simulated.
Synthesized.
Implemented.
<img width="1679" height="1001" alt="image" src="https://github.com/user-attachments/assets/37041ccf-571e-4133-b0ea-34f632d18c99" />

<img width="1679" height="957" alt="image" src="https://github.com/user-attachments/assets/b4861878-26e9-4190-ba70-5fc47041af6a" />

Hardware validation in progress.

</div>
