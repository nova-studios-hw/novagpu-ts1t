# NovaGPU TS 1T

**An open source GPU architecture built from scratch in Verilog.**  
Nova Studios / Maximal Technology

> ⚠️ Active development. This project is in RTL validation phase.  
> 10/29 testbench cases passing (34%). Not yet running on physical FPGA.  
> We document the process openly — including what is not working yet.

---

## Table of Contents

- [What is this?](#what-is-this)
- [Architecture — N.E.O.N.](#architecture--neon)
- [Full Pipeline Diagram](#full-pipeline-diagram)
- [Proprietary Technologies](#proprietary-technologies)
  - [Three Tracing (BVH RT)](#three-tracing)
  - [MVU — Frame Generation](#mvu--memory-vault-unit)
  - [N.E.O.N. Memory Bridge](#neon-memory-bridge)
- [RTL Module Reference](#rtl-module-reference)
- [Hardware Specifications](#hardware-specifications)
- [Competitive Position](#competitive-position)
- [Current Status](#current-status)
- [How to Run](#how-to-run)
- [Roadmap](#roadmap)
- [License](#license)

---

## What is this?

The NovaGPU TS 1T is a complete GPU pipeline implemented in Verilog RTL,  
targeting FPGA prototyping on the Digilent Arty A7-100T and eventual ASIC  
tapeout at 28nm process node.

This is not a simulation of a GPU. It is a real hardware design with:

- A proprietary token dataflow execution architecture (N.E.O.N.)
- Hardware ray tracing via BVH stack traversal
- Hardware frame generation (MVU)
- A custom 8-opcode shader ISA
- Full pipeline from vertex to framebuffer

The project is built by a single developer with open source tools.  
Every architectural decision is documented. Every bug is logged.  
The goal is to demonstrate that serious GPU architecture work  
can happen outside of large corporations.

**What does the name mean?**

- **Nova** — New. A star that suddenly increases in brightness. The idea of something powerful emerging from nothing.
- **GPU** — Graphics Processing Unit. That is exactly what this is.
- **TS** — Three Tracing. The proprietary ray tracing and path tracing system that defines this architecture.
- **1T** — First generation. The T stands for the beginning. There will be a TS 1 after this — same architecture, 14nm, more cores.

---

## Architecture — N.E.O.N.

**N.E.O.N.** (Núcleo de Ejecución Optimizada Nativa) is the core  
execution model of this GPU. It replaces the Von Neumann instruction  
dispatch model used by NVIDIA CUDA and AMD GCN with a **token dataflow  
model** where data itself triggers execution.

In a conventional GPU shader core, approximately 63% of silicon area  
is dedicated to infrastructure that does not compute pixels:  
instruction fetch, decode, warp scheduler, general purpose registers,  
FP64 units. N.E.O.N. eliminates all of this for rasterization workloads.

When a fragment token arrives at a N.E.O.N. core with **both operands  
ready**, execution fires automatically. No scheduler. No idle cycles  
waiting for data. No warp divergence in the classical sense.

### N.E.O.N. vs Conventional GPU Core

```
CONVENTIONAL GPU CORE (CUDA / GCN)          N.E.O.N. CORE
─────────────────────────────────────        ─────────────────────────────
┌─────────────────────────────────┐          ┌─────────────────────────┐
│  Instruction Fetch Unit         │          │  Token Input Buffer     │
│  Instruction Decode Unit        │  ~63%    │                         │
│  Warp Scheduler                 │  AREA    │  ┌───────────────────┐  │
│  General Purpose Register File  │  WASTED  │  │  TMU              │  │
│  FP64 Units                     │          │  │  (Token Matching) │  │
│  Branch Divergence Logic        │          │  └────────┬──────────┘  │
│─────────────────────────────────│          │           │             │
│  ALU / FPU  (actual compute)    │          │  FIRE when both         │
│  Texture Sampler                │          │  operands READY         │
│  Special Function Unit          │          │           │             │
└─────────────────────────────────┘          │  ┌────────▼──────────┐  │
                                              │  │  Compute Unit     │  │
 Activity factor: 75–95% power draw           │  │  ALU / FPU / TEX  │  │
 even at low utilization                      │  └───────────────────┘  │
                                              └─────────────────────────┘

                                               Activity factor: 40–55%
                                               Zero idle scheduler cycles
```

**Theoretical advantages over equivalent CUDA cores at 28nm:**

| Metric | Conventional | N.E.O.N. | Delta |
|--------|-------------|----------|-------|
| Area per core | 1.0× | ~0.37× | −63% |
| Activity factor (rasterization) | 75–95% | 40–55% | −42% |
| Perf/Watt (rasterization) | 1.0× | ~7.4× | +640% |
| Warp divergence overhead | Present | Eliminated | — |

> These numbers are derived from analytical models, not measured silicon.  
> They will be validated or corrected when the design closes timing on FPGA.

---

## Full Pipeline Diagram

This is how a frame is produced from start to finish inside the NovaGPU TS 1T.

```
HOST (PCIe 4.0 x8)
        │
        ▼
┌───────────────────────────────────────────────────────────────────┐
│                        COMMAND PROCESSOR                          │
│              Receives draw calls, dispatches tokens               │
└───────────────────────────┬───────────────────────────────────────┘
                            │
              ┌─────────────▼─────────────┐
              │      ROTATION MATRIX      │
              │  Vertex Transform Stage   │
              │  Sine/Cosine LUT 256 entries│
              │  Model → Clip space        │
              └─────────────┬─────────────┘
                            │  Transformed Vertices
              ┌─────────────▼─────────────┐
              │   TRIANGLE RASTERIZER     │
              │  Pineda edge functions    │
              │  Barycentric interpolation│
              │  Perspective-correct Z    │
              │  Outputs: fragment tokens │
              └──────┬──────────┬─────────┘
                     │          │
           ┌─────────▼──┐   ┌───▼──────────────┐
           │    TMU      │   │  BVH RT ENGINE   │
           │  Token      │   │  AABB 3D slab    │
           │  Matching   │   │  intersection    │
           │  Unit       │   │  Hardware stack  │
           │  2-way set  │   │  8 entries deep  │
           │  associative│   │  Fixed latency   │
           └─────┬───────┘   └───────┬──────────┘
                 │                   │
                 │    ┌──────────────▼──────────┐
                 │    │   BUDGET CONTROLLER     │
                 │    │  RT frame time cap 25%  │
                 │    │  Adaptive path tracing  │
                 │    │  High-contrast tiles    │
                 │    └──────────────┬──────────┘
                 │                   │
              ┌──▼───────────────────▼──┐
              │     SHADER CLUSTER      │
              │  8-opcode mini-ISA:     │
              │  NOP ADD MUL MAD MOV   │
              │  TEX RAY FRAG          │
              │  4-warp scheduler      │
              │  MVP matrix pipeline   │
              │  Z-test per fragment   │
              └────────────┬───────────┘
                           │  Shaded fragments
              ┌────────────▼───────────┐
              │     TILE ARBITER       │
              │  8×8 pixel tiles       │
              │  Atomic Z-test         │
              │  Tile lock mechanism   │
              │  Deterministic output  │
              └────────────┬───────────┘
                           │
              ┌────────────▼───────────┐
              │    SRAM INTEGRATED     │
              │  Dual-port 64 banks    │
              │  Address striping      │
              │  AXI4-Lite interface   │
              │  256MB on-chip buffer  │
              └────────┬───────────────┘
                       │
          ┌────────────▼────────────────┐
          │         MVU                 │
          │  Frame Generation Engine    │
          │  Input: Frame A + Frame B   │
          │  Motion vector per block    │
          │  Bilinear interpolation     │
          │  Output: 4× interpolated    │
          │  60fps native → 144fps      │
          └────────────┬────────────────┘
                       │
          ┌────────────▼────────────────┐
          │       FRAMEBUFFER           │
          │  HDMI 2.1 / DP 2.0 output   │
          │  1080p primary              │
          │  1440p secondary            │
          └─────────────────────────────┘
```

---

## Proprietary Technologies

### Three Tracing

Hybrid Ray Tracing and adaptive Path Tracing system.

```
TRIANGLE RASTERIZER
        │
        │ fragment token + hit surface
        ▼
┌───────────────────────────────────────────┐
│            BVH RT ENGINE (bvh_real.v)     │
│                                           │
│  ┌─────────────────────────────────────┐  │
│  │  BVH Tree (Bounding Volume Hierarchy│  │
│  │                                     │  │
│  │         [Root AABB]                 │  │
│  │        /           \                │  │
│  │  [Node AABB]   [Node AABB]          │  │
│  │   /      \      /      \            │  │
│  │ [Leaf] [Leaf] [Leaf] [Leaf]         │  │
│  │ Tri 0  Tri 1  Tri 2  Tri 3          │  │
│  └─────────────────────────────────────┘  │
│                                           │
│  AABB Slab Intersection (3D):             │
│  t_min = max(tx_min, ty_min, tz_min)      │
│  t_max = min(tx_max, ty_max, tz_max)      │
│  HIT if t_min <= t_max AND t_max > 0      │
│                                           │
│  Hardware Stack: 8 entries               │
│  → No recursion. Fixed latency pipeline  │
│                                           │
│  On MISS: pop stack, continue traversal  │
│  On HIT leaf: shade intersection         │
└───────────────────┬───────────────────────┘
                    │
        ┌───────────▼────────────┐
        │   BUDGET CONTROLLER    │
        │  (budget_controller.v) │
        │                        │
        │  Frame budget: 100%    │
        │  RT allocation: 25%    │
        │  Raster: 75%           │
        │                        │
        │  Adaptive path tracing:│
        │  → Only fires on tiles │
        │    with high luminance │
        │    contrast            │
        │  → Saves 35-50% of     │
        │    RT budget           │
        └────────────────────────┘

ESTIMATED FPS IMPACT: 10–15% vs 60%+ software RT
GTX 1060 / GTX 1650: NO ray tracing hardware at all.
```

---

### MVU — Memory Vault Unit

Hardware frame generation engine.

```
RENDERED FRAMES FROM GPU PIPELINE
          │
    ┌─────▼──────┐     ┌────────────┐
    │  FRAME A   │     │  FRAME B   │
    │  (t=0)     │     │  (t=1)     │
    └─────┬──────┘     └─────┬──────┘
          │                   │
          └────────┬──────────┘
                   │
    ┌──────────────▼──────────────────────┐
    │          MVU (mvu.v)                │
    │                                     │
    │  1. Divide frame into NxN blocks    │
    │                                     │
    │  2. Per-block motion estimation:    │
    │     Block A → search in Frame B     │
    │     → motion vector (dx, dy)        │
    │                                     │
    │  3. Interpolate 4 frames:           │
    │     t=0.25 → bilinear interp        │
    │     t=0.50 → bilinear interp        │
    │     t=0.75 → bilinear interp        │
    │     t=1.00 → Frame B (real)         │
    │                                     │
    │  Bilinear formula per pixel:        │
    │  P(t) = A*(1-t) + B*t              │
    │  + motion vector offset             │
    └──────────────┬──────────────────────┘
                   │
    ┌──────────────▼──────────────────────┐
    │  OUTPUT: 4 frames per 2 rendered    │
    │                                     │
    │  Game renders at:    60 fps         │
    │  MVU outputs at:    ~144 fps        │
    │  Latency added:     <1 frame        │
    └─────────────────────────────────────┘

NO GPU in the $89–109 price range offers this.
Neither GTX 1650 nor GTX 1060.
```

---

### N.E.O.N. Memory Bridge

Predictive SRAM prefetch controller.

```
COMPUTE PIPELINE
(TMU / BVH / Rasterizer / MVU)
          │
          │ memory requests
          ▼
┌─────────────────────────────────────────────┐
│        N.E.O.N. MEMORY BRIDGE               │
│         (sram_integrated.v)                 │
│                                             │
│  256MB On-Chip SRAM — 64 banks              │
│  Address striping across banks              │
│  Dual-port access (read + write simultaneous│
│                                             │
│  PREDICTIVE PREFETCH ENGINE:                │
│                                             │
│  ┌──────────────────────────────────────┐   │
│  │ BVH traversal pattern:               │   │
│  │   → Always requests nodes in order   │   │
│  │   → Prefetch child nodes on parent   │   │
│  │     hit, before they are requested   │   │
│  └──────────────────────────────────────┘   │
│  ┌──────────────────────────────────────┐   │
│  │ Rasterizer pattern:                  │   │
│  │   → Always requests 8×8 pixel tiles  │   │
│  │   → Prefetch adjacent tiles on       │   │
│  │     tile boundary crossing           │   │
│  └──────────────────────────────────────┘   │
│  ┌──────────────────────────────────────┐   │
│  │ MVU pattern:                         │   │
│  │   → Always requests Frame A + B      │   │
│  │     together                         │   │
│  │   → Prefetch both on frame start     │   │
│  └──────────────────────────────────────┘   │
│                                             │
│  Result:                                    │
│  SRAM hit rate:  ~85% (projected)           │
│  AMD Infinity Cache hit rate: ~58%          │
│  6GB physical GDDR6 → ~10–11GB effective    │
└──────────────────────────────────────────┬──┘
                                           │  MISS
                                           ▼
                              ┌────────────────────┐
                              │   GDDR6 VRAM       │
                              │   6GB, 192-bit bus │
                              │   AXI4-Lite bridge │
                              └────────────────────┘
```

---

## RTL Module Reference

Each module, what it does internally, and its connections.

### Token Matching Unit — `tmu.v`

```
INPUTS                    TMU INTERNALS               OUTPUTS
──────                    ─────────────               ───────
token_a (operand A)  ─►  ┌──────────────────────┐
token_b (operand B)  ─►  │  2-way set-associative│  ─► match_fire (pulse)
token_valid          ─►  │  matching buffer      │  ─► operand_a_out
clk, rst             ─►  │                       │  ─► operand_b_out
                         │  When BOTH operands    │  ─► token_id_out
                         │  arrive for same       │
                         │  token ID:             │
                         │  → Assert match_fire   │
                         │  → Forward operands    │
                         │  → Clear buffer slot   │
                         └──────────────────────┘

No scheduler. No warp manager. Data arrival = execution trigger.
```

### Triangle Rasterizer — `triangle_rasterizer.v`

```
INPUTS                    RASTERIZER INTERNALS             OUTPUTS
──────                    ────────────────────             ───────
v0, v1, v2 (vertices) ─► ┌──────────────────────────┐
w0,w1,w2 (weights)    ─► │  1. Pineda edge functions │  ─► fragment_x
z0,z1,z2 (depth)      ─► │     E(x,y) = (x-vx)*dy   │  ─► fragment_y
                         │            - (y-vy)*dx    │  ─► fragment_z
                         │     Point inside triangle │  ─► frag_valid
                         │     if E0≥0, E1≥0, E2≥0  │
                         │                           │
                         │  2. Barycentric interp:   │
                         │     λ0 = E0/area           │
                         │     λ1 = E1/area           │
                         │     λ2 = 1 - λ0 - λ1      │
                         │     Uses reciprocal_lut.v  │
                         │     (division-free)        │
                         │                           │
                         │  3. Perspective-correct Z: │
                         │     z = λ0*z0 + λ1*z1      │
                         │         + λ2*z2            │
                         └──────────────────────────┘
```

### Shader Cluster — `shader_cluster.v`

```
INPUTS                  SHADER CLUSTER INTERNALS           OUTPUTS
──────                  ────────────────────────           ───────
frag tokens        ─►  ┌──────────────────────────────┐
shader_program     ─►  │  4-WARP SCHEDULER            │  ─► shaded_color
                        │  Round-robin warp select      │  ─► depth_out
                        │                              │  ─► frag_done
                        │  8-OPCODE ISA:               │
                        │  ┌──────────────────────┐    │
                        │  │ NOP  → no-op         │    │
                        │  │ ADD  → fp add        │    │
                        │  │ MUL  → fp multiply   │    │
                        │  │ MAD  → multiply-add  │    │
                        │  │ MOV  → register move │    │
                        │  │ TEX  → texture fetch │    │
                        │  │ RAY  → invoke BVH RT │    │
                        │  │ FRAG → output pixel  │    │
                        │  └──────────────────────┘    │
                        │                              │
                        │  MVP MATRIX PIPELINE:        │
                        │  Model → View → Projection   │
                        │  Using rotation_matrix.v     │
                        │                              │
                        │  Z-TEST per fragment:        │
                        │  if z_new < z_buffer[x,y]   │
                        │    → write pixel             │
                        │  else → discard              │
                        └──────────────────────────────┘
```

### Tile Arbiter — `tile_arbiter.v`

```
MULTIPLE SHADER OUTPUTS       TILE ARBITER              SRAM WRITE
───────────────────────       ────────────              ──────────
shard_0 pixel (x,y,z,c) ─►  ┌────────────────────┐
shard_1 pixel (x,y,z,c) ─►  │  Divide framebuffer│  ─► tile_data_out
shard_2 pixel (x,y,z,c) ─►  │  into 8×8 tiles    │  ─► tile_addr
shard_3 pixel (x,y,z,c) ─►  │                    │  ─► write_enable
                              │  Per tile:         │
                              │  → Acquire tile    │
                              │    lock            │
                              │  → Atomic Z-test   │
                              │  → Write winner    │
                              │  → Release lock    │
                              │                    │
                              │  Deterministic:    │
                              │  Same scene always │
                              │  produces same     │
                              │  output frame      │
                              └────────────────────┘
```

### SRAM + AXI Bridge — `sram_integrated.v` + `memory_and_handshake.v`

```
AXI4-Lite Master         SRAM CONTROLLER              PHYSICAL SRAM
(from pipeline)          ───────────────              ─────────────
                         ┌──────────────────────┐
AWADDR, AWVALID    ─►   │  64 banks             │  ─► bank_0[...]
WDATA,  WVALID     ─►   │  Address striping:    │  ─► bank_1[...]
ARADDR, ARVALID    ─►   │  addr[7:0] → bank sel │  ─► ...
                         │  addr[N:8] → offset   │  ─► bank_63[...]
RDATA,  RVALID     ◄─   │                       │
BRESP              ◄─   │  Dual-port:           │
                         │  Port A: read         │
                         │  Port B: write        │
                         │  Simultaneous access  │
                         │  to different banks   │
                         │                       │
                         │  AXI4-Lite handshake: │
                         │  VALID/READY protocol  │
                         │  No data loss on       │
                         │  backpressure          │
                         └──────────────────────┘
```

---

## Hardware Specifications

| Parameter            | Value                                        |
| -------------------- | -------------------------------------------- |
| Compute cores        | 1,024 N.E.O.N. cores                         |
| Organization         | 4 CUs × 256 cores, 4 blocks × 64 per CU     |
| Process node target  | 28nm                                         |
| FPGA prototype board | Digilent Arty A7-100T                        |
| TDP (base)           | 75W — PCIe slot only, no external connector  |
| TDP (extended)       | 90W — PCIe 6-pin connector                   |
| VRAM                 | 6GB GDDR6, 192-bit bus                       |
| On-chip SRAM         | 256MB / 64 banks (512MB at 90W)              |
| Shader ISA           | 8 opcodes: NOP ADD MUL MAD MOV TEX RAY FRAG  |
| Ray tracing          | Hardware BVH, AABB 3D slab intersection      |
| Frame generation     | Hardware MVU, motion-compensated             |
| Video output         | HDMI 2.1 / DisplayPort 2.0                   |
| Host interface       | PCIe 4.0 x8 functional, x16 physical         |
| Target resolution    | 1080p primary, 1440p secondary               |

---

## Competitive Position

| GPU               | TDP        | RT Hardware | Frame Gen | Approx. Price   |
| ----------------- | ---------- | ----------- | --------- | --------------- |
| GTX 1060 6GB      | 120W       | No          | No        | $80–100 used    |
| GTX 1650 GDDR6    | 75W        | No          | No        | $120–150 used   |
| RX 6500 XT        | 107W       | Basic       | No        | $130–150        |
| **NovaGPU TS 1T** | **75–90W** | **Yes**     | **Yes**   | **$89–109 new** |

Target positioning: rasterization performance comparable to GTX 1650,  
with RT hardware and frame generation that no GPU in this price range offers.  
Superior performance-per-watt versus GTX 1060 at 30W lower consumption.

> These are design targets, not measured results.

---

## RTL Module Status

| File                     | Description                                                     | Status |
| ------------------------ | --------------------------------------------------------------- | ------ |
| `triangle_rasterizer.v`  | Pineda edge functions, barycentric interpolation, perspective Z | ✅      |
| `shader_cluster.v`       | 8-opcode ISA, 4-warp scheduler, MVP pipeline, Z-test            | ✅      |
| `bvh_real.v`             | AABB 3D slab intersection, hardware stack, fixed latency        | ✅      |
| `sram_integrated.v`      | Dual-port, 64 banks, address striping, AXI4-Lite                | ✅      |
| `tmu.v`                  | Token Matching Unit, match-and-fire, 2-way set-associative      | ✅      |
| `mvu.v`                  | Frame generation, motion vectors, bilinear interpolation        | ✅      |
| `budget_controller.v`    | RT frame budget limiter, configurable percentage                | ✅      |
| `tile_arbiter.v`         | Atomic Z-test, tile lock, deterministic output                  | ✅      |
| `arbiter.v`              | Priority arbiter, Z-test priority, round-robin                  | ✅      |
| `reciprocal_lut.v`       | Division-free reciprocal for rasterizer                         | ✅      |
| `rotation_matrix.v`      | Sine/cosine LUT, 256 entries, vertex transform                  | ✅      |
| `memory_and_handshake.v` | AXI handshake, dual-port memory bridge                          | ✅      |
| `top.v`                  | System integration, parameter master                            | ✅      |
| `fpga_top.v`             | Arty A7-100T integration, VGA, UART, clock                      | ✅      |

---

## Current Status

| Milestone                   | Status                    |
| --------------------------- | ------------------------- |
| RTL complete (14 modules)   | ✅ Done                    |
| Master testbench (29 tests) | 🔄 10/29 passing (34%)     |
| Known bugs documented       | ✅ Yes — fixes identified  |
| Timing closure on FPGA      | ⏳ Not started             |
| Physical demo on screen     | ⏳ Not started             |
| First silicon               | ⏳ Pending funding         |

**Known testbench failures and root causes:**

| Issue | Module | Fix Status |
|-------|--------|------------|
| 1-cycle pipeline gap in area calculation | `triangle_rasterizer.v` | Fix identified |
| Regfile latency not absorbed in decode stage | `shader_cluster.v` | Fix identified |
| BVH stack pointer without underflow protection | `bvh_real.v` | Fix identified |
| MVU ready signal not active in IDLE state | `mvu.v` | Fix identified |

We publish the current state honestly. The architecture is sound.  
The RTL needs stabilization. That work is in progress.

---

## How to Run

```bash
# Install Icarus Verilog
sudo apt install iverilog

# Clone repository
git clone https://github.com/nova-studios-hw/novagpu-ts1t
cd novagpu-ts1t

# Run master testbench (29 tests)
iverilog -g2012 -o nova_sim rtl/*.v sim/tb_novagpu_v12.v
vvp nova_sim

# Run static analysis and error detector
python3 scripts/errordetect1.py
```

---

## Roadmap

**Now — RTL stabilization**  
Bring testbench from 34% to 100%. Apply documented fixes module by module.

**Next — FPGA physical demo**  
Triangle on screen with Z-buffer, color interpolation, and basic ray tracing visible.  
This is the milestone that opens real conversations with investors and fabricators.

**Then — Open publication**  
Technical paper on arXiv describing the N.E.O.N. architecture.  
GitHub as primary technical reference.

**Later — First silicon**  
28nm MPW shuttle tapeout. Funded by investment raised after FPGA demo.

**Future — NovaGPU TS 1 (14nm)**  
4,096 N.E.O.N. cores. RTX 2070-class performance target.  
Full N.E.O.N. Memory Bridge with dedicated cache chiplets.

---

## License

MIT License — free to use, study, modify, and distribute.  
See `LICENSE` file.

---

## Contact

Nova Studios / Maximal Technology  
GitHub Issues: github.com/nova-studios-hw/novagpu-ts1t/issues

---

*We are building what most people say cannot be done with these resources.*  
*The process is open. Follow along.*
