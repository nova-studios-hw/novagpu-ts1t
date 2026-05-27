# NovaGPU TS 1T

**An open source GPU architecture built from scratch in Verilog.**  
Nova Studios / Maximal Technology

> ⚠️ Active development. This project is in RTL validation phase.  
> 10/29 testbench cases passing (34%). Not yet running on physical FPGA.  
> We document the process openly — including what is not working yet.

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

What does the name mean?
Nova — New. A star that suddenly increases in brightness.
The idea of something powerful emerging from nothing.
GPU — Graphics Processing Unit. That is exactly what this is.
TS — Three Tracing. The proprietary ray tracing and path tracing
system that defines this architecture. The technology that separates
this GPU from everything in its price range.
1T — First generation. The T stands for the beginning.
There will be a TS 1 after this — same architecture, 14nm, more cores.
---

## Architecture — N.E.O.N.

**N.E.O.N.** (Núcleo de Ejecución Optimizada Nativa) is the core
execution model of this GPU. It replaces the Von Neumann instruction
dispatch model used by NVIDIA CUDA and AMD GCN with a token dataflow
model where data itself triggers execution.

In a conventional GPU shader core, approximately 63% of silicon area
is dedicated to infrastructure that does not compute pixels:
instruction fetch, decode, warp scheduler, general purpose registers,
FP64 units. N.E.O.N. eliminates all of this for rasterization workloads.

When a fragment token arrives at a N.E.O.N. core with both operands
ready, execution fires automatically. No scheduler. No idle cycles
waiting for data. No warp divergence in the classical sense.

**Theoretical advantages over equivalent CUDA cores at 28nm:**
- ~63% area reduction per core
- Activity factor of 40–55% under rasterization load vs 75–95% conventional
- 7.4× better performance-per-watt in specific rasterization workloads

These numbers are derived from analytical models, not measured silicon.
They will be validated or corrected when the design closes timing on FPGA.

---

## Proprietary Technologies

### Three Tracing
Hybrid Ray Tracing and adaptive Path Tracing system.

Hardware BVH traversal with real 3D AABB slab intersection.
Stack of 8 entries in physical registers. Fixed-latency pipeline.
Adaptive path tracing activates only in high-luminance-contrast tiles,
controlled by a budget controller that caps RT time at 25% of frame budget.
Estimated FPS impact: 10–15% versus 60%+ for software RT on equivalent GPUs.

The GTX 1650 and GTX 1060 — the competitive reference GPUs for this
project — have no ray tracing hardware of any kind.

### MVU — Memory Vault Unit
Hardware frame generation.

Receives 2 real rendered frames. Outputs 4 motion-compensated
interpolated frames using bilinear interpolation with per-block
motion vectors. A game running at 60fps native is perceived at
up to 144fps on screen.

No GPU in the $89–109 price target range offers hardware frame
generation. Neither the GTX 1650 nor the GTX 1060.

### N.E.O.N. Memory Bridge
Predictive SRAM prefetch controller.

256MB of on-chip SRAM acts as an intelligent buffer between the
compute die and the GDDR6 VRAM. Unlike AMD Infinity Cache or NVIDIA
L2 cache — which use generic LRU replacement policies because they
cannot predict access patterns — N.E.O.N. dataflow architecture knows
exactly what data will be requested next:

- BVH traversal always requests nodes in hierarchical order
- Rasterizer always requests 8×8 pixel tiles
- MVU always requests frame A and frame B together

This enables anticipatory prefetch instead of reactive caching.
Projected SRAM hit rate: ~85% versus ~58% AMD Infinity Cache.
Effective result: 6GB physical GDDR6 behaves as ~10–11GB effective
in ray tracing and rasterization workloads.

This is a projection. It will be measured when the design runs on hardware.

---

## Hardware Specifications

| Parameter | Value |
|-----------|-------|
| Compute cores | 1,024 N.E.O.N. cores |
| Organization | 4 CUs × 256 cores, 4 blocks × 64 per CU |
| Process node target | 28nm |
| FPGA prototype board | Digilent Arty A7-100T |
| TDP (base) | 75W — PCIe slot only, no external connector |
| TDP (extended) | 90W — PCIe 6-pin connector |
| VRAM | 6GB GDDR6, 192-bit bus |
| On-chip SRAM | 256MB / 64 banks (512MB at 90W) |
| Shader ISA | 8 opcodes: NOP ADD MUL MAD MOV TEX RAY FRAG |
| Ray tracing | Hardware BVH, AABB 3D slab intersection |
| Frame generation | Hardware MVU, motion-compensated |
| Video output | HDMI 2.1 / DisplayPort 2.0 |
| Host interface | PCIe 4.0 x8 functional, x16 physical |
| Target resolution | 1080p primary, 1440p secondary |

---

## RTL Modules

| File | Description | Status |
|------|-------------|--------|
| `triangle_rasterizer.v` | Pineda edge functions, barycentric interpolation, perspective Z | ✅ |
| `shader_cluster.v` | 8-opcode ISA, 4-warp scheduler, MVP pipeline, Z-test | ✅ |
| `bvh_real.v` | AABB 3D slab intersection, hardware stack, fixed latency | ✅ |
| `sram_integrated.v` | Dual-port, 64 banks, address striping, AXI4-Lite | ✅ |
| `tmu.v` | Token Matching Unit, match-and-fire, 2-way set-associative | ✅ |
| `mvu.v` | Frame generation, motion vectors, bilinear interpolation | ✅ |
| `budget_controller.v` | RT frame budget limiter, configurable percentage | ✅ |
| `tile_arbiter.v` | Atomic Z-test, tile lock, deterministic output | ✅ |
| `arbiter.v` | Priority arbiter, Z-test priority, round-robin | ✅ |
| `reciprocal_lut.v` | Division-free reciprocal for rasterizer | ✅ |
| `rotation_matrix.v` | Sine/cosine LUT, 256 entries, vertex transform | ✅ |
| `memory_and_handshake.v` | AXI handshake, dual-port memory bridge | ✅ |
| `top.v` | System integration, parameter master | ✅ |
| `fpga_top.v` | Arty A7-100T integration, VGA, UART, clock | ✅ |

---

## Current Status

| Milestone | Status |
|-----------|--------|
| RTL complete (14 modules) | ✅ Done |
| Master testbench (29 tests) | 🔄 10/29 passing |
| Coverage | 🔄 34% |
| Known bugs documented | ✅ Yes — fixes identified |
| Timing closure on FPGA | ⏳ Not started |
| Physical demo on screen | ⏳ Not started |
| First silicon | ⏳ Pending funding |

The testbench failures are documented with root cause and fixes ready.
Primary issues: 1-cycle pipeline gap in rasterizer area calculation,
regfile latency not absorbed in shader decode stage, BVH stack pointer
without underflow protection, MVU ready signal not active in IDLE state.

We publish the current state honestly. The architecture is sound.
The RTL needs stabilization. That work is in progress.

---

## Competitive Position

| GPU | TDP | RT Hardware | Frame Gen | Approx. Price |
|-----|-----|-------------|-----------|---------------|
| GTX 1060 6GB | 120W | No | No | $80–100 used |
| GTX 1650 GDDR6 | 75W | No | No | $120–150 used |
| RX 6500 XT | 107W | Basic | No | $130–150 |
| **NovaGPU TS 1T** | **75–90W** | **Yes** | **Yes** | **$89–109 new** |

Target positioning: rasterization performance comparable to GTX 1650,
with RT hardware and frame generation that no GPU in this price range offers.
Superior performance-per-watt versus GTX 1060 at 30W lower consumption.

These are design targets, not measured results.

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
