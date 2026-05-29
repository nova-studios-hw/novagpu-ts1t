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

**35 tests implemented · 19 passing · 54% functional coverage**  
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
- [How to Run Simulations](#how-to-run-simulations)
- [FPGA Implementation](#fpga-implementation)
- [ASIC Roadmap](#asic-roadmap)
- [Why This Project Exists](#why-this-project-exists)
- [Important Technical Clarifications](#important-technical-clarifications)
- [License](#license)
- [Contact](#contact)

---

# What is NovaGPU TS 1T?

**NovaGPU TS 1T** is an experimental GPU pipeline implemented entirely in synthesizable Verilog RTL.

The project targets:

- FPGA prototyping on the Digilent Arty A7-100T
- Graphics architecture experimentation
- Token-based execution research
- Long-term ASIC exploration

---

## Current Features

| Feature | Description |
|----------|-------------|
| **N.E.O.N. Architecture** | Token-driven execution model |
| **Three Tracing** | Experimental BVH traversal engine |
| **MVU** | Motion-vector frame interpolation |
| **Custom ISA** | 8-opcode shader instruction set |
| **Complete Pipeline** | Vertex → Rasterizer → Shader → SRAM → Output |
| **Open Source** | MIT licensed |

---

## Target Metrics (Research Goals)

| Parameter | Value |
|------------|------|
| Compute cores | 1,024 N.E.O.N. cores |
| Process node | 28nm CMOS |
| TDP target | 75–90W |
| VRAM target | 6GB GDDR6 |
| On-chip SRAM | 256MB |
| Target class | GTX 1650-class rasterization |

> These values are architectural goals and analytical estimates — not validated silicon measurements.

---

# Architecture — N.E.O.N.

**N.E.O.N.** (*Núcleo de Ejecución Optimizada Nativa*) explores a token-driven execution model where data availability triggers execution.

Unlike traditional SIMT execution:

- No centralized warp dispatch
- Reduced scheduling overhead
- Event-driven token matching
- Match-and-fire execution flow

---

## Conventional SIMT vs N.E.O.N.

### Conventional GPU Core

```text
┌────────────────────────────────────────────────────────────┐
│ CONVENTIONAL GPU CORE (SIMT)                              │
├────────────────────────────────────────────────────────────┤
│ Instruction Fetch                                          │
│ Instruction Decode                                         │
│ Warp Scheduler                                             │
│ Register File                                              │
│ Branch Divergence Logic                                    │
│ Cache Infrastructure                                       │
└────────────────────────────────────────────────────────────┘
```

### N.E.O.N. Core

```text
┌────────────────────────────────────────────────────────────┐
│ N.E.O.N. GPU CORE                                          │
├────────────────────────────────────────────────────────────┤
│ Token Input Buffer                                         │
│ Token Matching Unit                                        │
│ Match-and-Fire Logic                                       │
│ Compute Units (ALU / TEX / MOV / CMP)                      │
└────────────────────────────────────────────────────────────┘
```

---

## Analytical Projections

| Metric | Conventional SIMT | N.E.O.N. |
|--------|-------------------|----------|
| Scheduling overhead | High | Reduced |
| Warp divergence | Present | Reduced |
| Activity factor | High | Event-driven |
| Execution model | Instruction-driven | Token-driven |

> Hardware validation is currently in progress.

---

# Full Pipeline Diagram

```text
HOST (PCIe)
    │
    ▼
┌──────────────────────┐
│ COMMAND PROCESSOR    │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ ROTATION MATRIX      │
│ Vertex Transform     │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ TRIANGLE RASTERIZER  │
│ Pineda Edge Functions│
└───────┬──────────────┘
        │
 ┌──────┴──────────┐
 │                 │
 ▼                 ▼
TMU           BVH ENGINE
 │                 │
 └──────┬──────────┘
        ▼
┌──────────────────────┐
│ BUDGET CONTROLLER    │
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ SHADER CLUSTER       │
│ 8-Opcode ISA         │
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ TILE ARBITER         │
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ SRAM INTEGRATED      │
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ MVU                  │
│ Frame Interpolation  │
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ FRAMEBUFFER OUTPUT   │
└──────────────────────┘
```

---

# Experimental Technologies

## Three Tracing — Experimental BVH Traversal

```text
                ┌──────────────────────────────┐
                │       BVH ROOT NODE          │
                └──────────────┬───────────────┘
                               │
                ┌──────────────┴───────────────┐
                │                              │
         ┌──────▼──────┐               ┌──────▼──────┐
         │   LEFT      │               │    RIGHT    │
         │ AABB NODE   │               │ AABB NODE   │
         └──────┬──────┘               └──────┬──────┘
                │                              │
         ┌──────▼──────┐               ┌──────▼──────┐
         │   LEAFS     │               │   LEAFS     │
         └─────────────┘               └─────────────┘
```

### Current Capabilities

- BVH traversal
- AABB slab intersection
- DFS traversal
- Hardware traversal stack
- Experimental RT budgeting

---

## MVU — Memory Vault Unit

```text
Frame A ─────┐
             ├──► Motion Vectors ───► Interpolator ───► Output Frames
Frame B ─────┘
```

### MVU Goals

- Motion-compensated interpolation
- Intermediate frame synthesis
- Low-latency experimentation
- FPGA-compatible implementation

> Current latency/performance values are design targets only.

---

# Module Reference

| File | Version | Status | Description |
|------|----------|--------|-------------|
| `triangle_rasterizer.v` | v3.0 | ✅ Stable | Pineda rasterizer |
| `tmu.v` | v3.0 | ✅ Stable | Token matching unit |
| `shader_cluster.v` | v3.0 | ✅ Stable | 8-opcode shader ISA |
| `bvh_real.v` | v3.0 | ✅ Stable | BVH traversal |
| `tile_arbiter.v` | v3.0 | ✅ Stable | Z-test & arbitration |
| `sram_integrated.v` | v3.0 | ✅ Stable | Dual-port SRAM |
| `mvu.v` | v3.0 | ✅ Stable | Frame interpolation |
| `arbiter.v` | v3.0 | ✅ Stable | Round-robin arbiter |
| `rotation_matrix.v` | v3.0 | ✅ Stable | Vertex transforms |
| `top.v` | v3.0 | ✅ Stable | Top-level integration |

---

# Shader Cluster — 8 Opcode ISA

| Opcode | Name | Operation |
|--------|------|-----------|
| 0 | NOP | Pass-through |
| 1 | ADD | Addition |
| 2 | SUB | Subtraction |
| 3 | MUL | Multiply |
| 4 | MOV | Move |
| 5 | CMP | Compare |
| 6 | BLEND | Blend |
| 7 | MVP_XFORM | Matrix transform |

---

# Hardware Specifications

| Parameter | Value |
|------------|------|
| FPGA Prototype | Digilent Arty A7-100T |
| Process Target | 28nm CMOS |
| ISA | Custom 8-opcode |
| RT Support | Experimental |
| Frame Generation | Experimental |
| Video Output | HDMI / DisplayPort |
| Host Interface | PCIe |

---

# Current Status & Test Coverage

## Verification Results

| Group | Tests | Passing | Status |
|-------|------|----------|--------|
| Rasterizer | 10 | 3 | ⚠️ WIP |
| TMU | 6 | 4 | ⚠️ Debugging |
| Shader Cluster | 5 | 2 | ⚠️ WIP |
| BVH | 5 | 3 | ⚠️ WIP |
| SRAM / MVU | 5 | 4 | ✅ Mostly stable |
| Integration | 4 | 3 | ⚠️ In progress |
| **TOTAL** | **35** | **19 (54%)** | **Active Development** |

---

## Known Issues

| Issue | Module | Status |
|-------|--------|--------|
| pixel_inside false | Rasterizer | Investigating |
| fire_valid issue | TMU | Investigating |
| out_valid issue | Shader Cluster | Investigating |
| BVH hit logic | BVH Engine | WIP |

---

# How to Run Simulations

## Install Icarus Verilog

### Ubuntu / Debian

```bash
sudo apt install iverilog
```

### Windows

Download from:

```text
http://bleyer.org/icarus/
```

---

## Clone Repository

```bash
git clone https://github.com/nova-studios-hw/novagpu-ts1t
cd novagpu-ts1t
```

---

## Compile

```bash
iverilog -g2012 -o novagpu_sim rtl/*.v sim/tb_maestro_v12.v
```

---

## Run Simulation

```bash
vvp novagpu_sim
```

Expected output:

```text
========================================
RESULTADO FINAL NovaGPU TS 1T v3.0
========================================
Total Tests : 37
PASSED      : 19
FAILED      : 18
Coverage    : 51%
========================================
```

---

# FPGA Implementation

## Target Board

**Digilent Arty A7-100T**

---

## Estimated FPGA Usage

| Resource | Available | Estimated Usage |
|----------|------------|----------------|
| Logic Cells | 101,440 | ~25,000 |
| Block RAM | 4,860 Kb | ~2,000 Kb |
| DSP Slices | 240 | ~80 |

---

## FPGA Configuration Example

```verilog
parameter TARGET_FREQ_MHZ = 100;
parameter NUM_RT_UNITS    = 2;
parameter BVH_DEPTH       = 4;
parameter TMU_SLOTS       = 32;
```

---

# ASIC Roadmap

| Parameter | Target |
|-----------|-------|
| Process | 28nm CMOS |
| Target Frequency | 1.0–1.2 GHz |
| Die Area | 45–65mm² |
| Tapeout Path | MPW Shuttle |

> ASIC implementation would require substantial additional verification, physical design, timing closure, and memory subsystem redesign.

---

# Why This Project Exists

NovaGPU TS 1T exists to demonstrate:

- Open GPU experimentation
- Accessible FPGA graphics research
- Independent RTL development
- Transparent hardware engineering

The repository intentionally documents:

- Bugs
- Failures
- Timing issues
- Verification limitations
- Architectural constraints

Because real hardware engineering includes all of those challenges.

---

# Important Technical Clarifications

NovaGPU TS 1T is:

- ✅ Experimental
- ✅ Research-oriented
- ✅ FPGA-focused
- ✅ Educational

NovaGPU TS 1T is NOT currently:

- ❌ A commercial GPU
- ❌ A validated ASIC
- ❌ Production-ready hardware
- ❌ A competitor to flagship GPUs

---

# License

MIT License.

See `LICENSE` for details.

---

# Contact

GitHub Issues:

```text
https://github.com/nova-studios-hw/novagpu-ts1t/issues
```

Reddit discussion:

```text
r/FPGA
```

---

# 📚 Recommended Reading

- Patterson & Hennessy — Computer Architecture
- FPGA Prototyping by Verilog Examples
- Real-Time Rendering (4th Edition)
- NVIDIA Tesla Architecture Paper
- WaveScalar / EDGE / TRIPS Papers
- Tagged-token dataflow architecture research

---

<div align="center">

### Building experimental graphics hardware in the open.

⬆ Back to top

</div>
