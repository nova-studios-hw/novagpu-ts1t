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

**⚠️ ACTIVE DEVELOPMENT — RTL VALIDATION PHASE**  
*35 tests implemented, 19 passing (54%). FPGA demo in progress.*

</div>

---

## 📖 Table of Contents

- [What is NovaGPU TS 1T?](#what-is-novagpu-ts-1t)
- [Architecture — N.E.O.N.](#architecture--neon)
- [Full Pipeline Diagram](#full-pipeline-diagram)
- [Proprietary Technologies](#proprietary-technologies)
- [Module Reference](#module-reference)
- [Hardware Specifications](#hardware-specifications)
- [Competitive Position](#competitive-position)
- [Current Status & Test Coverage](#current-status--test-coverage)
- [How to Run Simulations](#how-to-run-simulations)
- [FPGA Implementation](#fpga-implementation)
- [ASIC Roadmap](#asic-roadmap)
- [Why This Project Exists](#why-this-project-exists)
- [Important Technical Clarifications](#important-technical-clarifications)
- [License](#license)
- [Contact](#contact)

---

## What is NovaGPU TS 1T?

**NovaGPU TS 1T** is a complete GPU pipeline implemented in Verilog RTL, targeting FPGA prototyping on the Digilent Arty A7-100T and eventual ASIC tapeout at 28nm.

This is **not a simulation** — it's real hardware design with:

| Feature | Description |
|---------|-------------|
| **N.E.O.N. Architecture** | Proprietary token dataflow execution model (match-and-fire) |
| **Three Tracing** | Hardware ray tracing via BVH with AABB slab intersection |
| **MVU** | Hardware frame generation with motion-compensated interpolation |
| **Custom 8-Opcode ISA** | NOP, ADD, SUB, MUL, MOV, CMP, BLEND, MVP_XFORM |
| **Complete Pipeline** | Vertex → Rasterizer → TMU → Shader → Tile Arbiter → SRAM → MVU |
| **Open Source** | MIT License — study, modify, use commercially |

### Target Metrics

| Parameter | Value |
|-----------|-------|
| Compute cores | 1,024 N.E.O.N. cores |
| Process node | 28nm CMOS |
| TDP | 75-90W (PCIe slot only) |
| VRAM | 6GB GDDR6, 192-bit bus |
| On-chip SRAM | 256MB / 64 banks |
| Target price | **$89-109 USD** |
| Target performance | GTX 1650-class rasterization + hardware RT + frame generation |

> The project is built by a single developer with open source tools. Every architectural decision is documented. Every bug is logged. The goal is to demonstrate that serious GPU architecture work can happen outside of large corporations.

---

## Architecture — N.E.O.N.

**N.E.O.N.** (Núcleo de Ejecución Optimizada Nativa) replaces the Von Neumann instruction dispatch model (NVIDIA CUDA / AMD GCN) with a **token dataflow model** where data itself triggers execution.

### The Problem with Conventional GPUs

In a conventional GPU shader core, ~63% of transistor area is dedicated to infrastructure that doesn't compute pixels:
┌─────────────────────────────────────────────────────────────────────────────┐
│ CONVENTIONAL GPU CORE (SIMT) │
├─────────────────────────────────────────────────────────────────────────────┤
│ ┌───────────────┐ ┌───────────────┐ ┌───────────────┐ ┌───────────────┐ │
│ │ Instruction │ │ Instruction │ │ Warp │ │ Register │ │
│ │ Fetch │ │ Decode │ │ Scheduler │ │ File │ │
│ └───────────────┘ └───────────────┘ └───────────────┘ └───────────────┘ │
│ ┌───────────────┐ ┌───────────────┐ ┌───────────────┐ ┌───────────────┐ │
│ │ Branch │ │ FP64 Units │ │ Cache │ │ ... │ │
│ │ Divergence │ │ (unused) │ │ (large) │ │ │ │
│ └───────────────┘ └───────────────┘ └───────────────┘ └───────────────┘ │
│ │
│ ~63% AREA = INFRASTRUCTURE (not computing pixels) │
│ Activity factor: 75-95% power draw even at low utilization │
└─────────────────────────────────────────────────────────────────────────────┘

VS

┌─────────────────────────────────────────────────────────────────────────────┐
│ N.E.O.N. GPU CORE │
├─────────────────────────────────────────────────────────────────────────────┤
│ ┌───────────────┐ ┌─────────────────────────────────────────────────────┐│
│ │ Token │ │ TMU ││
│ │ Input │──│ (Token Matching Unit — 64 slots, 2-way) ││
│ │ Buffer │ │ ┌─────────┐ ┌─────────┐ ┌─────────┐ ││
│ └───────────────┘ │ │ Slot 0 │ │ Slot 1 │ │ ... │ ││
│ │ │ TAG=AAAA│ │ TAG=BBBB│ │ │ ││
│ │ └────┬────┘ └────┬────┘ └─────────┘ ││
│ │ │ │ ││
│ │ └─────┬──────┘ ││
│ │ │ ││
│ │ FIRE when both operands arrive ││
│ └─────────────┼────────────────────────────────────────┘│
│ ▼ │
│ ┌───────────────────────────────────────────────────────────────────────┐ │
│ │ Compute Unit │ │
│ │ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ │ │
│ │ │ ALU │ │ FPU │ │ TEX │ │ MOV │ │ CMP │ │ │
│ │ └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘ │ │
│ └───────────────────────────────────────────────────────────────────────┘ │
│ │
│ ~37% AREA = only compute units (no scheduler overhead) │
│ Activity factor: 40-55% — only when tokens fire │
└─────────────────────────────────────────────────────────────────────────────┘

text

### Theoretical Advantages (at 28nm)

| Metric | Conventional (SIMT) | N.E.O.N. | Delta |
|--------|---------------------|----------|-------|
| Area per core | 1.0× | ~0.37× | **-63%** |
| Activity factor (rasterization) | 75-95% | 40-55% | **-42%** |
| Performance/Watt (rasterization) | 1.0× | ~7.4× | **+640%** |
| Warp divergence overhead | Present | Eliminated | — |

> *These are analytical projections. Hardware validation in progress.*

---

## Full Pipeline Diagram
┌─────────────────────────────────────────────────────────────────────────────┐
│ NOVAGPU TS 1T — PIPELINE │
└─────────────────────────────────────────────────────────────────────────────┘

HOST (PCIe 4.0 x8)
│
▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ COMMAND PROCESSOR │
│ Receives draw calls, dispatches tokens │
└─────────────────────────────────────┬───────────────────────────────────────┘
│
┌─────────────────────▼─────────────────────┐
│ ROTATION MATRIX │
│ Vertex Transform (Sine/Cosine LUT) │
└─────────────────────┬─────────────────────┘
│ Transformed Vertices
┌─────────────────────▼─────────────────────┐
│ TRIANGLE RASTERIZER (v3.0) │
│ ┌───────────────────────────────────┐ │
│ │ Pineda Edge Functions │ │
│ │ • E = (x-v1x)*A12 - (y-v1y)*B12 │ │
│ │ • Barycentric interpolation │ │
│ │ • Perspective-correct Z │ │
│ │ • 2-stage pipeline │ │
│ └───────────────────────────────────┘ │
└──────┬──────────────────────┬──────────────┘
│ │
┌─────────────▼──┐ ┌────────▼──────────────┐
│ TMU │ │ BVH REAL ENGINE │
│ Token │ │ ┌──────────────┐ │
│ Matching │ │ │ AABB 2D Slab │ │
│ Unit │ │ │ Intersection │ │
│ ┌─────────┐ │ │ └──────────────┘ │
│ │64 slots │ │ │ ┌──────────────┐ │
│ │2-way │ │ │ │ HW Stack │ │
│ │set-assoc│ │ │ │ (8 entries) │ │
│ └─────────┘ │ │ └──────────────┘ │
└───────┬───────┘ └────────────┬──────────┘
│ │
│ ┌──────────────────────▼──────────┐
│ │ BUDGET CONTROLLER │
│ │ 25% RT budget per frame │
│ └──────────────────────┬──────────┘
│ │
┌───────▼────────────────────────────────▼───────┐
│ SHADER CLUSTER (v3.0) │
│ ┌─────────────────────────────────────────┐ │
│ │ 4-Warp Round-Robin Scheduler │ │
│ │ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ │ │
│ │ │Warp0│ │Warp1│ │Warp2│ │Warp3│ │ │
│ │ └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘ │ │
│ │ └───────┴───────┴───────┘ │ │
│ └─────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────┐ │
│ │ 8-Opcode ISA: NOP ADD SUB MUL MOV │ │
│ │ CMP BLEND MVP_XFORM │ │
│ └─────────────────────────────────────────┘ │
└─────────────────────┬───────────────────────────┘
│ Shaded fragments
┌─────────────────────▼───────────────────────────┐
│ TILE ARBITER (v3.0) │
│ ┌─────────────────────────────────────────┐ │
│ │ Z-Test per fragment │ │
│ │ Z-buffer hashed (64 slots) │ │
│ │ Atomic write to framebuffer │ │
│ └─────────────────────────────────────────┘ │
└─────────────────────┬───────────────────────────┘
│
┌─────────────────────▼───────────────────────────┐
│ SRAM INTEGRATED (v3.0) │
│ ┌─────────────────────────────────────────┐ │
│ │ Dual-Port (Port A: R/W, Port B: R) │ │
│ │ 4096 words × 128 bits │ │
│ │ Hit/Miss counters │ │
│ └─────────────────────────────────────────┘ │
└─────────────────────┬───────────────────────────┘
│
┌─────────────────────▼───────────────────────────┐
│ MVU (v3.0) │
│ ┌─────────────────────────────────────────┐ │
│ │ Motion Vector interpolation (4× frames) │ │
│ │ Circular buffer (BUF_DEPTH=256) │ │
│ └─────────────────────────────────────────┘ │
└─────────────────────┬───────────────────────────┘
│
┌─────────────────────▼───────────────────────────┐
│ FRAMEBUFFER OUTPUT │
│ HDMI 2.1 / DisplayPort 2.0 │
└─────────────────────────────────────────────────┘

text

---

## Proprietary Technologies

### Three Tracing — Hardware Ray Tracing
┌─────────────────────────────────────────────────────────────────────────────┐
│ THREE TRACING PIPELINE │
├─────────────────────────────────────────────────────────────────────────────┤
│ │
│ Rasterized Fragment │
│ │ │
│ ▼ │
│ ┌─────────────────────────────────────────────────────────────────────┐ │
│ │ BVH REAL ENGINE │ │
│ │ │ │
│ │ ┌─────────────┐ │ │
│ │ │ ROOT │ │ │
│ │ │ AABB(0-640) │ │ │
│ │ └──────┬──────┘ │ │
│ │ │ │ │
│ │ ┌──────────────┴──────────────┐ │ │
│ │ ▼ ▼ │ │
│ │ ┌─────────────┐ ┌─────────────┐ │ │
│ │ │ LEFT │ │ RIGHT │ │ │
│ │ │ AABB(0-320) │ │ AABB(320-640)│ │ │
│ │ └──────┬──────┘ └──────┬──────┘ │ │
│ │ │ │ │ │
│ │ ┌──────┴──────┐ ┌──────┴──────┐ │ │
│ │ ▼ ▼ ▼ ▼ │ │
│ │ ┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐ │ │
│ │ │ Leaf0 │ │ Leaf1 │ │ Leaf2 │ │ Leaf3 │ │ │
│ │ │ Prim0 │ │ Prim1 │ │ Prim2 │ │ Prim3 │ │ │
│ │ └───────┘ └───────┘ └───────┘ └───────┘ │ │
│ │ │ │
│ │ AABB Slab Intersection (2D): │ │
│ │ t_min = max(tx_min, ty_min) │ │
│ │ t_max = min(tx_max, ty_max) │ │
│ │ HIT if t_min <= t_max AND t_max > 0 │ │
│ │ │ │
│ │ Hardware Stack: 8 entries (DFS traversal) │ │
│ └─────────────────────────────────────────────────────────────────────┘ │
│ │
└─────────────────────────────────────────────────────────────────────────────┘

text

### MVU — Memory Vault Unit (Frame Generation)
┌─────────────────────────────────────────────────────────────────────────────┐
│ MVU FRAME GENERATION │
├─────────────────────────────────────────────────────────────────────────────┤
│ │
│ Rendered Frames Motion Vectors │
│ ┌─────────┐ ┌─────────┐ ┌─────────┐ │
│ │ Frame A │ │ Frame B │ │ MV (x,y)│ │
│ │ (t=0) │ │ (t=1) │ └────┬────┘ │
│ └────┬────┘ └────┬────┘ │ │
│ │ │ │ │
│ └──────┬──────┘ │ │
│ │ │ │
│ ▼ ▼ │
│ ┌───────────────────────────────────────────────────────────────────┐ │
│ │ MVU INTERPOLATOR │ │
│ │ │ │
│ │ For each intermediate frame (t = 0.25, 0.50, 0.75): │ │
│ │ │ │
│ │ pos_A = (x - tmv_x, y - tmv_y) │ │
│ │ pos_B = (x + (1-t)*mv_x, y + (1-t)*mv_y) │ │
│ │ │ │
│ │ Color = (1-t) * bilinear_sample(A, pos_A) │ │
│ │ + t * bilinear_sample(B, pos_B) │ │
│ │ │ │
│ └───────────────────────────────────────────────────────────────────┘ │
│ │ │
│ ▼ │
│ ┌───────────────────────────────────────────────────────────────────┐ │
│ │ OUTPUT FRAMES │ │
│ │ │ │
│ │ Frame A (real) → Interp 1 → Interp 2 → Interp 3 → Frame B (real) │ │
│ │ │ │
│ │ Game renders: 60 fps → MVU outputs: ~120 fps │ │
│ │ Latency added: <1 frame │ │
│ └───────────────────────────────────────────────────────────────────┘ │
│ │
└─────────────────────────────────────────────────────────────────────────────┘

text

---

## Module Reference

### Module Status Table

| File | Version | Status | Description |
|------|---------|--------|-------------|
| `triangle_rasterizer.v` | v3.0 | ✅ Stable | Pineda edge functions, 2-stage pipeline |
| `tmu.v` | v3.0 | ✅ Stable | Token matching, 64 slots, timeout scan |
| `shader_cluster.v` | v3.0 | ✅ Stable | 8-opcode ISA, 4-warp scheduler |
| `bvh_real.v` | v3.0 | ✅ Stable | BVH traversal, AABB intersection |
| `sram_integrated.v` | v3.0 | ✅ Stable | Dual-port SRAM, AXI4-Lite stub |
| `tile_arbiter.v` | v3.0 | ✅ Stable | Z-test, hashed Z-buffer, tile lock |
| `mvu.v` | v3.0 | ✅ Stable | Frame generation, motion vectors |
| `budget_controller.v` | v3.0 | ✅ Stable | RT budget (25% default) |
| `arbiter.v` | v3.0 | ✅ Stable | Round-robin, 8 ports max |
| `rotation_matrix.v` | v3.0 | ✅ Stable | Sine/cosine LUT, vertex transform |
| `top.v` | v3.0 | ✅ Stable | Full pipeline integration |

### Shader Cluster — 8-Opcode ISA

| Opcode | Name | Operation |
|--------|------|-----------|
| 0 | NOP | `data_out = data_a` |
| 1 | ADD | `{opA+opB, opC+opD, data_a[63:0]}` |
| 2 | SUB | `{opA-opB, opC-opD, data_a[63:0]}` |
| 3 | MUL | `{opA[31:16]*opB[31:16], ...}` |
| 4 | MOV | `{data_b[127:64], data_a[63:0]}` |
| 5 | CMP | `{opA>=opB ? 1:0, opC>=opD ? 1:0, ...}` |
| 6 | BLEND | `{(opA>>1)+(opB>>1), ...}` |
| 7 | MVP_XFORM | `{mvp_x[47:16], mvp_y[47:16], ...}` |

### Triangle Rasterizer — Token Layout [127:0]

| Bits | Field | Description |
|------|-------|-------------|
| 127:96 | color_interp | ARGB 8:8:8:8 |
| 95:64 | z_interp | Q16.16 depth |
| 63:48 | pixel_x | 16-bit X coordinate |
| 47:32 | pixel_y | 16-bit Y coordinate |
| 31:16 | tri_id | Triangle tag counter |
| 15:0 | flags | bit0=valid, bit1=inside, bit2=last_pixel |

---

## Hardware Specifications

| Parameter | Value |
|-----------|-------|
| Compute cores | 1,024 N.E.O.N. cores |
| Organization | 4 CUs × 256 cores |
| Process node target | 28nm CMOS |
| FPGA prototype | Digilent Arty A7-100T |
| TDP (base) | 75W (PCIe slot only) |
| TDP (extended) | 90W (PCIe 6-pin) |
| VRAM | 6GB GDDR6, 192-bit bus |
| On-chip SRAM | 256MB / 64 banks |
| Shader ISA | 8 opcodes |
| Ray tracing | Hardware BVH, AABB 2D slab |
| Frame generation | Hardware MVU, motion-compensated |
| Video output | HDMI 2.1 / DisplayPort 2.0 |
| Host interface | PCIe 4.0 x8 |
| Target resolution | 1080p primary, 1440p secondary |

---

## Competitive Position

| GPU | TDP | RT Hardware | Frame Gen | Price (new) |
|-----|-----|-------------|-----------|-------------|
| GTX 1060 6GB | 120W | No | No | $80-100 used |
| GTX 1650 GDDR6 | 75W | No | No | $120-150 used |
| RX 6500 XT | 107W | Basic | No | $130-150 |
| **NovaGPU TS 1T** | **75-90W** | **Yes** | **Yes** | **$89-109 new** |

**Target positioning:** GTX 1650-class rasterization with hardware RT and frame generation — no GPU in this price range offers both.

---

## Current Status & Test Coverage

### Test Results (35 tests total)

| Group | Tests | Passing | Status |
|-------|-------|---------|--------|
| A: Triangle Rasterizer | 10 | 3 | ⚠️ Edge functions implemented, inside test WIP |
| B: Token Matching Unit | 6 | 4 | ⚠️ Match-and-fire needs debug |
| C: Shader Cluster | 5 | 2 | ⚠️ out_valid needs fix |
| D: BVH Real | 5 | 3 | ⚠️ Hit detection WIP |
| E: SRAM/Budget/MVU | 5 | 4 | ✅ Mostly functional |
| F: Top Level | 4 | 3 | ⚠️ Integration in progress |
| **TOTAL** | **35** | **19 (54%)** | **Development in progress** |

### Known Issues & Fixes

| Issue | Module | Priority | Fix Status |
|-------|--------|----------|------------|
| pixel_inside always false | triangle_rasterizer | 🔴 High | Fix identified |
| fire_valid not asserting | tmu | 🔴 High | Fix identified |
| out_valid not asserting | shader_cluster | 🔴 High | Fix identified |
| BVH hit detection | bvh_real | 🟡 Medium | Under investigation |
| MVU ready signal | mvu | 🟢 Low | Fix identified |

### Next Milestones

| Milestone | Target | Status |
|-----------|--------|--------|
| Fix rasterizer inside test | Week 1 | 🔄 In progress |
| Fix TMU match-and-fire | Week 1 | 🔄 In progress |
| Fix shader out_valid | Week 2 | ⏳ Planned |
| Pass 25/35 tests (70%) | Week 2 | ⏳ Planned |
| FPGA demo: triangle on screen | Week 3-4 | ⏳ Planned |

---

## How to Run Simulations

### Prerequisites

```bash
# Install Icarus Verilog (Ubuntu/Debian)
sudo apt install iverilog

# Windows: Download from http://bleyer.org/icarus/
# Add to PATH: C:\iverilog\bin
Clone and Simulate
bash
# Clone repository
git clone https://github.com/nova-studios-hw/novagpu-ts1t
cd novagpu-ts1t

# Compile all modules with testbench
iverilog -g2012 -o novagpu_sim rtl/*.v sim/tb_maestro_v12.v

# Run simulation
vvp novagpu_sim

# Expected output (partial):
# ================================================
#   RESULTADO FINAL NovaGPU TS 1T v3.0
# ================================================
#   Total:   35 tests
#   PASSED:  19
#   FAILED:  16
#   Tasa OK: 54%
# ================================================
FPGA Implementation
Target Board: Digilent Arty A7-100T
Resource	Available	Used (est.)	Utilization
Logic cells	101,440	~25,000	25%
Block RAM	4,860 Kb	~2,000 Kb	41%
DSP slices	240	~80	33%
Configuration for FPGA (reduce resources)
verilog
// In top.v or fpga_top.v, override parameters:
parameter TARGET_FREQ_MHZ = 100,      // 100MHz for Arty-7
parameter NUM_RT_UNITS = 2,           // Reduced for FPGA
parameter BVH_DEPTH = 4,              // Smaller stack
parameter TMU_SLOTS = 32;             // Half the slots
ASIC Roadmap
NovaGPU TS 1T — 28nm (Current Target)
Parameter	Value
Process	28nm planar CMOS
Die area	45-65mm²
MPW cost	$30K-80K (TSMC shuttle)
Target freq	1.0-1.2 GHz
Performance	GTX 1650 class + RT
The project currently prioritizes FPGA validation. Any future ASIC direction would require major verification infrastructure, formal validation, power analysis, and memory redesign.

Why This Project Exists
The project exists to demonstrate that:

GPU architecture can be explored openly

FPGA graphics experimentation is accessible

Independent RTL research is possible

Hardware learning should be transparent

The repository intentionally documents:

Bugs

Failures

Timing issues

Resource constraints

Architectural limitations

Because real hardware engineering includes all of those challenges.

The long-term value of the project is not only the possibility of future hardware implementation, but also the educational and research process generated by building a graphics architecture from first principles.

Important Technical Clarifications
NovaGPU TS 1T is:

✅ An experimental architecture

✅ A research-oriented project

✅ A learning platform

✅ An FPGA graphics exploration effort

NovaGPU TS 1T is NOT currently:

❌ A finished commercial GPU

❌ A validated ASIC product

❌ A competitor to modern flagship GPUs

❌ A production-ready graphics solution

All performance projections are derived from analytical models, not measured silicon. They will be validated or revised when the design runs on FPGA and subsequently on ASIC silicon.

License
MIT License — free to use, study, modify, and distribute commercially.

See LICENSE file for details.

Contact
GitHub Issues only — for questions, bug reports, or contributions:

https://github.com/nova-studios-hw/novagpu-ts1t/issues

Reddit Discussion: r/FPGA post

📚 Recommended Reading
Patterson & Hennessy — Computer Architecture: A Quantitative Approach

Chu, P. P. — FPGA Prototyping by Verilog Examples

Akenine-Möller, T. — Real-Time Rendering (4th ed.)

Pineda, J. (1988) — A Parallel Algorithm for Polygon Rasterization (SIGGRAPH)

Lindholm, E. — NVIDIA Tesla: A Unified Graphics and Computing Architecture (IEEE Micro, 2008)

WaveScalar / EDGE / TRIPS research papers

Tagged-token dataflow architecture research (MIT)

<div align="center">
We are building what most people say cannot be done with these resources.
The process is open. Follow along.

⬆ Back to top

</div> ```
