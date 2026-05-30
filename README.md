<div align="center">

<img src="https://img.shields.io/badge/NovaGPU-TS%201T-FF6B35?style=for-the-badge&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0id2hpdGUiIGQ9Ik0xMiAyTDIgN2wxMCA1IDEwLTVMMTIgMnpNMiAxN2wxMCA1IDEwLTVNMiAxMmwxMCA1IDEwLTUiLz48L3N2Zz4=" alt="NovaGPU TS 1T"/>

# NovaGPU TS 1T

**A full GPU rendering pipeline built from scratch in Verilog RTL**
*Nova Studios / Maximal Technology*

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](https://opensource.org/licenses/MIT)
[![Verilog](https://img.shields.io/badge/RTL-Verilog%202001-blue.svg?style=flat-square)](https://ieeexplore.ieee.org/document/6012607)
[![FPGA](https://img.shields.io/badge/FPGA-Arty%20A7--100T-orange.svg?style=flat-square)](https://digilent.com/reference/programmable-logic/arty-a7/start)
[![Vivado](https://img.shields.io/badge/Vivado-2023.1-76B900?style=flat-square)](https://www.xilinx.com/products/design-tools/vivado.html)
[![Reddit](https://img.shields.io/badge/Reddit-r%2FFPGA-FF4500?style=flat-square)](https://www.reddit.com/r/FPGA)
[![Status](https://img.shields.io/badge/Status-FPGA%20Implemented-brightgreen?style=flat-square)]()

---

### 🏆 MILESTONE ACHIEVED — Full FPGA Implementation Complete

**Synthesis ✅ · Place & Route ✅ · Bitstream Generated ✅**
*Vivado 2023.1 · xc7a100tcsg324-1 (Arty A7-100T) · 100 MHz*

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| Slice LUTs | 2,602 | 63,400 | **4.10%** |
| Slice Registers | 2,380 | 126,800 | **1.88%** |
| RAMB36E1 | 120 | 135 | **88.89%** |
| DSP48E1 | 19 | 240 | **7.92%** |
| Bonded IOB | 20 | 210 | **9.52%** |
| Total Power | — | — | **171 mW** |

</div>

---

## Table of Contents

- [What is NovaGPU TS 1T?](#what-is-novagpu-ts-1t)
- [Architecture Overview](#architecture-overview)
- [Full Pipeline](#full-pipeline)
- [Module Reference](#module-reference)
- [Hardware Specifications](#hardware-specifications)
- [FPGA Implementation — Vivado 2023.1](#fpga-implementation--vivado-20231)
- [Key Engineering Challenges Solved](#key-engineering-challenges-solved)
- [FPGA Wrapper Design](#fpga-wrapper-design)
- [Dual-Port SRAM — BRAM Inference](#dual-port-sram--bram-inference)
- [Note on Yosys](#note-on-yosys)
- [How to Implement on Hardware](#how-to-implement-on-hardware)
- [Constraints File (XDC)](#constraints-file-xdc)
- [ASIC Roadmap](#asic-roadmap)
- [Why This Project Exists](#why-this-project-exists)
- [License](#license)

---

## What is NovaGPU TS 1T?

NovaGPU TS 1T is a **complete GPU rendering pipeline implemented in synthesizable Verilog RTL**, targeting the Xilinx Artix-7 FPGA family. It is not a soft-core CPU pretending to do graphics — it is a purpose-built hardware pipeline that performs triangle rasterization, ray tracing budget management, shader execution, motion-vector-based upscaling, and VGA output, all in actual register-transfer level logic.

Every module in this project maps to real hardware primitives: RAMB36E1 for memory, DSP48E1 for multiply-accumulate, FDRE/FDPE for registers, CARRY4 for arithmetic. The full design synthesizes, implements, and generates a bitstream in Vivado 2023.1 with **zero critical warnings** and runs on a physical Arty A7-100T board.

**This is what the pipeline looks like end-to-end:**

```
PCIe data → [TMU] → [Shader Cluster] → [Budget Controller] → [Three Tracing Unit]
                                                                        ↓
VGA Output ← [MVU] ←──────────────────────────────────────────── frame_out
                                              ↑
Rasterizer Input → [Triangle Rasterizer] → [Tile Arbiter] → [SRAM] → fb_write
```

The top-level module `novagpu_ts1t_top` is wrapped by `fpga_top`, which provides the physical FPGA boundary with only 20 I/O pins — everything else is driven internally.

---

## Architecture Overview

The design follows a **token-driven, pipeline-staged** architecture. Data enters as 256-bit tokens through a PCIe-like interface, gets matched and dispatched by the Token Matching Unit, processed through shader and ray tracing stages, rasterized, written to a dual-port SRAM framebuffer, upscaled by the Motion Vector Unit, and finally output over VGA.

The key design principle is **pipeline independence**: each stage communicates through valid/ready handshakes and does not stall upstream stages. The Budget Controller enforces a real-time constraint on ray tracing workload so the pipeline always meets frame deadlines.

### Clock Architecture

| Domain | Frequency | Source | Purpose |
|--------|-----------|--------|---------|
| `clk_core` | 100 MHz | MMCME2_BASE ÷10 | GPU pipeline, all RTL logic |
| `clk_pixel` | 25 MHz | MMCME2_BASE ÷40 | VGA pixel clock (640×480@60Hz) |

VCO runs at 1000 MHz. Cross-domain signals are synchronized with 2-flip-flop synchronizers. False paths are declared between domains in the XDC.

---

## Full Pipeline

```
                           ┌─────────────────────────────────────────────────────────────────────┐
                           │                    novagpu_ts1t_top                                 │
                           │                                                                     │
  pcie_data_in[255:0] ────►│─► [TMU] ─────────────────────────────────────────────────────────► │
  pcie_valid          ────►│   Token Matching Unit                  fire_data_a / fire_data_b    │
                           │   (16 slots, 16-bit tags)                          │                │
                           │                                                    ▼                │
                           │                                         [Shader Cluster]            │
                           │                                         4 Compute Units             │
                           │                                         4 Warps each               │
                           │                                         MVP 4×4 matrix transform    │
                           │                                                    │                │
                           │                                                    ▼                │
                           │                               [Budget Controller] ◄──── frame_start │
                           │                               RT load monitoring                    │
                           │                               25% RT budget @ 100 MHz              │
                           │                                          │ budget_ok                │
                           │                                          ▼                          │
                           │                               [Three Tracing Unit]                 │
                           │                               BVH depth 4, 4 RT units              │
                           │                               Ray budget 4 rays/frag               │
                           │                                          │ tt_out / tt_valid        │
                           │                    ┌─────────────────── ┘                          │
                           │                    │                     │                          │
  v0,v1,v2 ─────────────► │  [Rasterizer] ─────► [Tile Arbiter] ────►│                         │
  c0,c1,c2,z0,z1,z2 ─────►│  640×480 screen      Priority mux        │                         │
  rast_start          ────►│  Barycentric interp  Depth test          │                         │
                           │                                          ▼                          │
                           │                                [SRAM Integrated]                   │
                           │                                Dual-port 128b×4096                 │
                           │                                120× RAMB36E1                       │
                           │                                Port A: R/W (framebuffer write)     │
                           │                                Port B: R-only (readback)           │
                           │                                          │                          │
  mv_x, mv_y ────────────►│                             [MVU] ◄──────┘ tt_out                  │
  mv_valid            ────►│                             Motion Vector Upscaler                 │
                           │                             2 real + 2 gen frames                  │
                           │                                          │                          │
                           │◄─────────────────────────────────────── │ frame_out[127:0]         │
  frame_out[127:0]        ◄│                                          │ frame_valid              │
  frame_valid             ◄│                                                                     │
                           └─────────────────────────────────────────────────────────────────────┘
                                                          │
                                                          ▼
                                                   [fpga_top wrapper]
                                                   VGA 640×480@60Hz
                                                   20 physical pins
```

---

## Module Reference

### `token_matching_unit` — TMU

The Token Matching Unit is the entry point of the pipeline. It receives 256-bit data tokens tagged with 16-bit identifiers and holds them in a slot array until both operands of a computation pair arrive. When both data words for a given tag are present, it "fires" them downstream as `fire_data_a` and `fire_data_b`.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NUM_SLOTS` | 16 | Number of concurrent in-flight token pairs |
| `TAG_WIDTH` | 16 | Width of the token identifier |
| `DATA_WIDTH` | 128 | Width of each data word |

**Key signals:**

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `in_tag` | Input | 16 | Tag identifier for incoming token |
| `in_data` | Input | 128 | Data payload |
| `in_valid` | Input | 1 | Token present on input |
| `in_ready` | Output | 1 | TMU can accept a new token |
| `fire_tag` | Output | 16 | Tag of the matched pair |
| `fire_data_a` | Output | 128 | First operand |
| `fire_data_b` | Output | 128 | Second operand |
| `fire_valid` | Output | 1 | Matched pair is valid |

---

### `shader_cluster` — Shader

The shader cluster contains 4 compute units (CUs), each capable of running 4 warps in parallel. It accepts paired operands from the TMU and applies a full 4×4 MVP matrix transformation to each fragment. The MVP matrix is loaded via 16 individual 32-bit registers (`mvp_m00` through `mvp_m33`) using a fixed-point Q16.16 format.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NUM_CU` | 4 | Number of compute units |
| `DATA_WIDTH` | 128 | Fragment data width |
| `NUM_WARPS` | 4 | Warps per compute unit |

The shader uses **19 DSP48E1 blocks** for multiply-accumulate operations in the matrix transform, confirmed in the Vivado implementation report. This is critical — it means the heavy arithmetic lands on dedicated silicon, not LUT-based multipliers.

---

### `budget_controller` — RT Budget

The budget controller enforces a real-time constraint on ray tracing work. It monitors what percentage of clock cycles are spent on active ray tracing (`rt_active`) within a frame boundary (`frame_start`) and outputs `budget_ok` to gate the Three Tracing Unit when the budget is exhausted.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `CLK_MHZ` | 100 | Clock frequency (used to compute frame cycles) |
| `RT_PERCENT` | 25 | Maximum % of frame time allowed for RT |

At 100 MHz and 60 fps, a frame is ~1.67 million cycles. 25% of that is ~416,000 cycles of ray tracing budget per frame. The 8-bit `rt_load` output gives the current utilization percentage, which is routed to the diagnostic LEDs.

---

### `three_tracing_unit` — TTU

The Three Tracing Unit (TTU) implements hardware ray tracing using a BVH (Bounding Volume Hierarchy) tree traversal. It accepts fragment data from the shader, traces rays against a preloaded BVH structure, and outputs shaded fragment results.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `BVH_DEPTH` | 4 | Maximum BVH tree depth (reduced from 8 for Artix-7) |
| `RAY_BUDGET` | 4 | Maximum rays per fragment |
| `DATA_WIDTH` | 128 | Fragment data width |
| `NUM_RT_UNITS` | 2 | Parallel ray tracing units (reduced from 4) |

The `sram_ack` input is tied to `1'b1` in the current FPGA demo, meaning the TTU assumes SRAM is always available. A full implementation would connect this to the SRAM arbiter.

---

### `triangle_rasterizer` — Rasterizer

The triangle rasterizer implements barycentric coordinate interpolation for triangle coverage testing across a 640×480 pixel grid. It accepts three vertex positions in screen space plus per-vertex color and depth values, and emits pixel tokens for every covered sample.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DATA_WIDTH` | 128 | Output token width |
| `SCREEN_W` | 640 | Screen width in pixels |
| `SCREEN_H` | 480 | Screen height in pixels |

**Rasterizer pipeline stages:**

```
Vertex input → Edge equation setup → Bounding box clamp →
Scanline iteration → Barycentric test → Depth interpolation →
Color interpolation → Token emit
```

**Performance counters** (visible in the Vivado power hierarchy under `u_rast`):
- `rast_pixels_emitted` [19:0] — total pixels that passed coverage test
- `rast_pixels_skipped` [19:0] — total pixels that failed (outside triangle or depth culled)
- `rast_frame_done` — pulse when all pixels of a triangle have been processed

The rasterizer consumes **0.014 W** of dynamic power, making it the dominant block in the GPU pipeline by power. This is consistent with it being the most continuously active unit during rendering.

---

### `tile_arbiter` — Arbiter

The tile arbiter receives pixel tokens from two sources — the rasterizer and the TTU — and arbitrates between them using a priority scheme. When both produce output simultaneously, the rasterizer output takes priority (rasterized geometry overrides ray-traced contributions for the same pixel). The arbiter also performs a final depth test before committing pixels to the SRAM framebuffer.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DATA_WIDTH` | 128 | Fragment token width |
| `SCREEN_W` | 640 | Screen width |
| `SCREEN_H` | 480 | Screen height |

**Output to SRAM:**
- `pixel_color` [31:0] — RGBA8 color of the winning fragment
- `pixel_addr` [18:0] — linear framebuffer address (y × 640 + x)
- `pixel_write` — write enable

---

### `sram_integrated` — Dual-Port SRAM

The integrated SRAM is a 128-bit wide, 4096-entry dual-port memory that maps to **120 RAMB36E1 tiles** in the Vivado placed design. This is the most memory-intensive module in the design at 88.89% of total available block RAM.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DATA_WIDTH` | 128 | Word width in bits |
| `ADDR_WIDTH` | 32 | Address bus width |
| `MEM_DEPTH` | 4096 | Number of entries |

**Port A (Read/Write):** Used by the tile arbiter to write pixel data. One cycle latency. Reset-synchronous control, pure-synchronous RAM block.

**Port B (Read-only):** Used by the MVU to read frame data for upscaling. Includes automatic 1-cycle stall on address conflict with Port A.

**BRAM inference:** Getting Vivado to correctly infer BRAM required three specific RTL patterns. See [Dual-Port SRAM — BRAM Inference](#dual-port-sram--bram-inference) for the full technical explanation.

---

### `mvu` — Motion Vector Unit

The Motion Vector Unit implements a simplified temporal upscaling pass. It receives completed frames from the TTU, applies motion vectors to warp pixels from previous frames, and generates interpolated output frames. The MVU is the primary consumer of BRAM in this design.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `REAL_FRAMES` | 2 | Number of real (rendered) frames buffered |
| `GEN_FRAMES` | 2 | Number of generated (interpolated) frames |
| `DATA_WIDTH` | 128 | Frame token width |

**Motion vector interface:**
- `mv_x` [15:0], `mv_y` [15:0] — per-frame motion vector
- `mv_valid` — motion vector is valid for current frame

In the FPGA demo, motion vectors are driven to zero (`mv_x = 0`, `mv_y = 0`) since there is no external motion estimation source. The MVU still operates but produces zero-displacement warped frames.

---

## Hardware Specifications

| Specification | Value |
|---------------|-------|
| Target Device | Xilinx Artix-7 xc7a100tcsg324-1 |
| Package | CSG324 |
| Speed Grade | -1 |
| Core Clock | 100 MHz |
| Pixel Clock | 25 MHz |
| Screen Resolution | 640 × 480 @ 60 Hz |
| Data Path Width | 128 bits |
| Frame Buffer | 4096 × 128-bit (512 Kbits) |
| Physical I/O Pins | 20 |
| Total On-Chip Power | 171 mW |
| Dynamic Power | 68 mW |
| Junction Temperature | 25.8 °C |
| Tool | Vivado 2023.1 |

---

## FPGA Implementation — Vivado 2023.1

### Synthesis Report (Post-Synthesis)

```
+-------------------------+------+-------+------------+-----------+-------+
|        Site Type        | Used | Fixed | Prohibited | Available | Util% |
+-------------------------+------+-------+------------+-----------+-------+
| Slice LUTs*             | 2637 |     0 |          0 |     63400 |  4.16 |
|   LUT as Logic          | 2637 |     0 |          0 |     63400 |  4.16 |
|   LUT as Memory         |    0 |     0 |          0 |     19000 |  0.00 |
| Slice Registers         | 2381 |     0 |          0 |    126800 |  1.88 |
| F7 Muxes                |  256 |     0 |          0 |     31700 |  0.81 |
| F8 Muxes                |  128 |     0 |          0 |     15850 |  0.81 |
+-------------------------+------+-------+------------+-----------+-------+
```

### Placed Utilization Report (Post-Implementation)

```
+-------------------+------+-------+------------+-----------+-------+
|     Site Type     | Used | Fixed | Prohibited | Available | Util% |
+-------------------+------+-------+------------+-----------+-------+
| Block RAM Tile    |  120 |     0 |          0 |       135 | 88.89 |
|   RAMB36/FIFO*    |  120 |     0 |          0 |       135 | 88.89 |
|     RAMB36E1 only |  120 |       |            |           |       |
|   RAMB18          |    0 |     0 |          0 |       270 |  0.00 |
+-------------------+------+-------+------------+-----------+-------+

+----------------+------+-------+------------+-----------+-------+
|    Site Type   | Used | Fixed | Prohibited | Available | Util% |
+----------------+------+-------+------------+-----------+-------+
| DSPs           |   19 |     0 |          0 |       240 |  7.92 |
|   DSP48E1 only |   19 |       |            |           |       |
+----------------+------+-------+------------+-----------+-------+

+-----------------------------+------+-------+------------+-----------+-------+
|          Site Type          | Used | Fixed | Prohibited | Available | Util% |
+-----------------------------+------+-------+------------+-----------+-------+
| Bonded IOB                  |   20 |    20 |          0 |       210 |  9.52 |
+-----------------------------+------+-------+------------+-----------+-------+
```

### Primitives Breakdown

| Primitive | Count | Category | Notes |
|-----------|-------|----------|-------|
| FDPE | 2,051 | Flip-Flop (preset) | Shader and MVU state registers |
| LUT3 | 1,695 | Logic | Control and mux logic |
| LUT6 | 672 | Logic | Wide combinational paths |
| CARRY4 | 473 | Arithmetic | Adder chains in rasterizer |
| FDRE | 275 | Flip-Flop (reset) | Pipeline registers |
| MUXF7 | 256 | Mux | Address decode (SRAM arbiter) |
| LUT2 | 194 | Logic | Enable and gate logic |
| MUXF8 | 128 | Mux | Wide mux chains |
| RAMB36E1 | 120 | Block RAM | Framebuffer + MVU frame buffers |
| DSP48E1 | 19 | Arithmetic | MVP matrix multiply-accumulate |
| BUFG | 2 | Clock | clk_core, clk_pixel |

### Power Report (Post-Route)

```
+--------------------------+--------------+
| Total On-Chip Power (W)  | 0.171        |
| Dynamic (W)              | 0.068        |
| Device Static (W)        | 0.103        |
| Junction Temperature (C) | 25.8         |
| Max Ambient (C)          | 84.2         |
+--------------------------+--------------+

+----------------+-----------+----------+-----------+-----------------+
| On-Chip        | Power (W) | Used     | Available | Utilization (%) |
+----------------+-----------+----------+-----------+-----------------+
| Clocks         |    <0.001 |        3 |       --- |             --- |
| Slice Logic    |     0.016 |     6135 |       --- |             --- |
| Block RAM      |     0.009 |      120 |       135 |           88.89 |
| DSPs           |     0.010 |       19 |       240 |            7.92 |
| I/O            |     0.013 |       20 |       210 |            9.52 |
+----------------+-----------+----------+-----------+-----------------+
```

**Power by hierarchy:**

```
+------------+-----------+
| Name       | Power (W) |
+------------+-----------+
| fpga_top   |     0.068 |
|   u_gpu    |     0.014 |
|     u_rast |     0.014 |  ← Triangle rasterizer, most active block
+------------+-----------+
```

---

## Key Engineering Challenges Solved

Getting this design from RTL to bitstream was not straightforward. Three problems caused implementation failures that required careful diagnosis and architectural changes.

### Challenge 1 — The I/O Pin Explosion (1,601 → 20)

The original `novagpu_ts1t_top` module had every internal bus signal exposed as a top-level port. This is normal practice for RTL simulation — you want to observe everything. But Vivado's placer treats every port as a physical FPGA pin.

**What Vivado reported:**
```
[Place 30-415] IO Placement failed due to overutilization.
This design contains 1601 I/O ports
Target device has 210 usable I/O pins
```

**Root cause analysis:**

| Signal group | Bits |
|---|---|
| `pcie_data_in` | 256 |
| `pcie_data_out` | 256 |
| MVP matrix (16 × 32-bit registers) | 512 |
| Vertex coordinates (v0,v1,v2 × x,y) | 66 |
| Per-vertex color + depth (c0–c2, z0–z2) | 192 |
| `frame_out` | 128 |
| AXI4-Lite | 258 |
| Bandwidth counters | 64 |
| Rasterizer stats | 41 |
| Miscellaneous | ~328 |
| **Total** | **~1,601** |

**Solution:** A dedicated FPGA wrapper (`fpga_top`) that drives all internal signals synthetically. The wrapper exposes exactly 20 physical pins — clock, reset, VGA (14 pins), and LEDs (4 pins). All GPU inputs are generated internally: a 32-bit Galois LFSR produces synthetic PCIe data, the MVP matrix is hardcoded as an identity matrix in Q16.16 fixed-point, the demo triangle vertices are constants, and motion vectors are zero. Vivado sees 20 ports and places all 20 IOBs without issue.

---

### Challenge 2 — BRAM Inference Failure

The dual-port SRAM initially synthesized as **32,768 FDRE flip-flops + 38,415 MUXF7 + 19,206 MUXF8** instead of RAMB36E1 blocks. This made synthesis of even 512 entries take several minutes and 4096 entries completely impractical.

**Root cause:** Vivado's memory inference engine requires the memory array to be accessed in a `always @(posedge clk)` block with no asynchronous reset in the same sensitivity list, and with unconditional read statements. The original RTL had:

```verilog
// BROKEN — conditional read introduces a MUX that Vivado cannot absorb
// into a RAMB output register
always @(posedge clk or negedge rst_n) begin   // ← rst in same block: FATAL
    if (!rst_n) begin
        ...
    end else begin
        if (a_wen) mem[a_idx] <= a_wdata;
        if (a_re)  ram_a_q <= mem[a_idx];     // ← conditional read: FATAL
    end
end
```

The `if (a_re)` creates an implicit MUX: `ram_a_q_next = a_re ? mem[a_idx] : ram_a_q`. Vivado sees a flip-flop with a non-trivial clock enable that does not match the transparency logic it expects for RAMB output registers, and falls back to LUT+FF expansion.

**Solution:** Separate the memory block completely from the control logic. The RAM block uses only `posedge clk`, and reads are unconditional:

```verilog
// CORRECT — pure synchronous block, unconditional reads
// Vivado infers this as RAMB36E1 with output register
always @(posedge clk) begin
    if (a_req & a_wen)
        mem[a_idx] <= a_wdata;

    ram_a_q <= mem[a_idx];      // always read — no enable
    ram_b_q <= mem[b_idx_eff];  // always read — no enable
end

// Separate block handles reset and valid pipeline
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        a_ack <= 0; b_ack <= 0; ...
    end else begin
        a_rd_valid_q <= a_req;           // pipeline the valid, not the data
        a_ack <= a_rd_valid_q;
        if (a_rd_valid_q) a_rdata <= ram_a_q;
    end
end
```

**Result:** 120 RAMB36E1, 0 FDRE from memory expansion, MUXF7 down to 256 (only for SRAM address decode, not for memory cells).

---

### Challenge 3 — Double-Driver on Statistics Counters

The hit counter (`hit_count`) was assigned in two separate `always` blocks in the same Verilog module — one for Port A accesses and one for Port B accesses. In IEEE Verilog-2001, when two procedural blocks assign the same variable in the same simulation timestep, the result is non-deterministic (the last assignment "wins" based on simulator scheduling order, which is undefined). Vivado's synthesizer detected the multi-driver and produced incorrect logic.

**Solution:** Compute the increment combinationally before the clock edge, then do a single atomic registered addition:

```verilog
// Combinational — compute how many hits THIS cycle (0, 1, or 2)
always @(*) begin
    hit_inc = 2'd0;
    if (a_req)                   hit_inc = hit_inc + 2'd1;
    if (b_req && !conflict_o)    hit_inc = hit_inc + 2'd1;
end

// One driver, one always block
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) hit_count <= 16'd0;
    else        hit_count <= hit_count + {{14{1'b0}}, hit_inc};
end
```

---

## FPGA Wrapper Design

`fpga_top` is the physical boundary of the design. It:

1. **Instantiates MMCME2_BASE** to generate 100 MHz core clock and 25 MHz pixel clock from the 100 MHz crystal oscillator on E3.
2. **Generates a 2-FF reset synchronizer** for each clock domain, gated by `pll_locked` — the GPU does not come out of reset until the PLL is stable.
3. **Drives all GPU inputs synthetically** so no internal signals become physical pins.
4. **Instantiates a VGA timing generator** running at 25 MHz with 640×480@60Hz standard timing (H total: 800, V total: 525).
5. **Routes frame_out to VGA output** using a 2-FF cross-domain synchronizer.
6. **Exposes 4 diagnostic LEDs**: PLL locked, frame valid, SRAM hit MSB, SRAM miss LSB.

**Physical pin count: 20**

```
Pin function      Count   Pins (Arty A7)
─────────────────────────────────────────
clk_100mhz          1    E3
btn_rst_n           1    C2
vga_r[3:0]          4    JB connector
vga_g[3:0]          4    JB connector
vga_b[3:0]          4    JC connector
vga_hsync           1    JB connector
vga_vsync           1    JC connector
led[3:0]            4    H5, J5, T9, T10
─────────────────────────────────────────
TOTAL              20    (9.52% of 210 available)
```

---

## Dual-Port SRAM — BRAM Inference

The `sram_integrated` module implements a 128-bit × 4096-entry dual-port SRAM. At 512 Kbits, this requires 15 RAMB36 tiles per read/write port pair. The design uses two ports (one R/W, one R-only), so the total is higher due to how Vivado packs the 128-bit width across multiple 36-bit-wide RAMB36 primitives.

**Memory geometry:**
- 128 bits wide = 4 RAMB36 tiles in 32-bit-wide mode, or 2 in 64-bit-wide mode
- 4096 entries fit in a single RAMB36 in 36K mode with 12-bit addresses
- Total: Vivado uses 120 RAMB36E1 tiles (88.89% of the 135 available)

The large BRAM count is dominated by the MVU frame buffers, not just the SRAM. If you need more headroom, reduce `MVU_REAL_FRAMES` and `MVU_GEN_FRAMES`, or migrate to a Kintex-7 with 325 RAMB36 tiles.

---

## Note on Yosys

During early development, Yosys (the open-source synthesis tool) was tested as an alternative to Vivado. However, the version available at the time had been downloaded incompletely and the installation was missing critical files needed for the synthesis flow to complete correctly. Rather than troubleshoot a broken installation, development moved to Vivado 2023.1, which provides a complete, validated environment with proper BRAM inference rules for Xilinx 7-Series devices, a professional timing analyzer, and the full implementation flow through bitstream generation.

Vivado turned out to be the better tool for this target device in any case, as it has native knowledge of Artix-7 BRAM geometries and DSP primitives that Yosys requires manual rule files to replicate.

---

## How to Implement on Hardware

### Requirements

- Vivado 2023.1 (or later)
- Arty A7-100T board
- Pmod VGA adapter (Digilent 410-321 or compatible) connected to JB+JC

### Step 1 — Clone and open in Vivado

```bash
git clone https://github.com/nova-studios/novagpu-ts1t.git
cd novagpu-ts1t
```

Open Vivado, create a new project targeting `xc7a100tcsg324-1`, and add all `.v` files from the `rtl/` directory plus `fpga_top.xdc`.

### Step 2 — Set fpga_top as top module

In the Sources panel, right-click `fpga_top` → **Set as Top**.

### Step 3 — Run implementation

```
Flow → Run Implementation
```

Or in Tcl console:

```tcl
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
```

### Step 4 — Program the board

```
Flow → Open Hardware Manager → Program Device
```

Select `fpga_top.bit` from `<project>/novagpu_ts1t.runs/impl_1/`.

### Step 5 — Connect VGA monitor

Connect a VGA monitor to the Pmod VGA adapter on JB+JC. You should see:

- **LED 0** solid ON — PLL locked, design running
- **LED 1** blinking — MVU generating frames
- **VGA** — color output from the rasterized demo triangle

---

## Constraints File (XDC)

```tcl
# Clock — 100 MHz crystal
set_property PACKAGE_PIN E3 [get_ports clk_100mhz]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100mhz]
create_clock -period 10.000 -name sys_clk [get_ports clk_100mhz]

# Reset button (BTN0, active low)
set_property PACKAGE_PIN C2 [get_ports btn_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports btn_rst_n]

# VGA — Pmod JB (upper row) — Red channel
set_property PACKAGE_PIN A14 [get_ports {vga_r[0]}]
set_property PACKAGE_PIN A13 [get_ports {vga_r[1]}]
set_property PACKAGE_PIN B13 [get_ports {vga_r[2]}]
set_property PACKAGE_PIN C13 [get_ports {vga_r[3]}]

# VGA — Pmod JB (upper row) — Green channel
set_property PACKAGE_PIN D13 [get_ports {vga_g[0]}]
set_property PACKAGE_PIN E13 [get_ports {vga_g[1]}]
set_property PACKAGE_PIN E12 [get_ports {vga_g[2]}]
set_property PACKAGE_PIN D12 [get_ports {vga_g[3]}]

# VGA — Pmod JC (upper row) — Blue channel
set_property PACKAGE_PIN G13 [get_ports {vga_b[0]}]
set_property PACKAGE_PIN H13 [get_ports {vga_b[1]}]
set_property PACKAGE_PIN J13 [get_ports {vga_b[2]}]
set_property PACKAGE_PIN K13 [get_ports {vga_b[3]}]

# VGA sync
set_property PACKAGE_PIN B11 [get_ports vga_hsync]
set_property PACKAGE_PIN C11 [get_ports vga_vsync]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_*}]

# LEDs — LD0–LD3
set_property PACKAGE_PIN H5  [get_ports {led[0]}]
set_property PACKAGE_PIN J5  [get_ports {led[1]}]
set_property PACKAGE_PIN T9  [get_ports {led[2]}]
set_property PACKAGE_PIN T10 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

# Cross-domain false paths (core ↔ pixel)
set_false_path -from [get_clocks clk_pixel] -to [get_clocks sys_clk]
set_false_path -from [get_clocks sys_clk]   -to [get_clocks clk_pixel]
```

---

## ASIC Roadmap

The RTL is written to be technology-independent. BRAM primitives are instantiated through inference (no Xilinx-specific primitives in the RTL itself), and DSP usage comes from arithmetic inference, not vendor-specific instantiation. The path to ASIC would involve:

| Phase | Description |
|-------|-------------|
| **Phase 1** | Replace MMCME2_BASE with a technology-specific PLL or remove it for ASIC flow |
| **Phase 2** | Replace BRAM inference with a standard-cell SRAM macro from the target PDK |
| **Phase 3** | Run through an open-source ASIC flow (OpenLane / Sky130) for area estimation |
| **Phase 4** | Full custom layout with a commercial PDK (GF22 or TSMC N7) |

The design's 171 mW total power at 100 MHz on a 28nm planar FPGA would likely drop to under 20 mW at 500 MHz on a 7nm FinFET process with equivalent workload.

---

## Why This Project Exists

Modern GPU architectures are complex enough that understanding them from documentation alone has limits. Building one from scratch in RTL — writing every register, every state machine, every memory interface from first principles — produces a kind of understanding that reading architecture manuals does not.

NovaGPU TS 1T is not trying to compete with commercial GPUs. It is an engineering study: what does a coherent GPU pipeline look like when you can see every wire? What happens when you try to map it to a real FPGA with finite resources? What are the actual bottlenecks (BRAM at 88.89%, as it turns out)? These are questions that only running real hardware can answer.

The fact that it generates a bitstream, programs a physical board, and produces VGA output is not a destination — it is a validation that the questions being asked are real ones.

---

## License

MIT License — see [LICENSE](LICENSE) for full terms.

Copyright © 2026 Nova Studios / Maximal Technology

---

<div align="center">

**Nova Studios / Maximal Technology**

*Built in RTL. Proven in silicon.*

</div>
