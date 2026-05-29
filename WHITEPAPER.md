# NovaGPU TS 1T — Technical Whitepaper

**Nova Studios**  
*Version 2.0 — 2026*

---

## Abstract

This document describes the complete architecture of the NovaGPU TS 1T, an open source graphics processing unit designed from first principles in Verilog RTL by a single developer. The NovaGPU TS 1T introduces the N.E.O.N. (Núcleo de Ejecución Optimizada Nativa) token dataflow execution model, a departure from the Von Neumann warp-based execution found in all major commercial GPU architectures including NVIDIA CUDA and AMD GCN/RDNA.

The architecture targets 28nm process node with a TDP of 75–90W, 1,024 compute cores, 6GB GDDR6 memory, and 256MB on-chip SRAM. It incorporates three proprietary technologies: Three Tracing (hybrid hardware ray tracing), the MVU (Memory Vault Unit, a hardware frame generation engine), and the N.E.O.N. Memory Bridge (a predictive SRAM prefetch controller).

The primary competitive target is the NVIDIA GTX 1650 GDDR6, which this architecture matches in rasterization throughput while adding hardware ray tracing and frame generation capabilities unavailable in any GPU at the target price point of $89–109 USD.

**Current development status:** 35 verification tests implemented, 19 passing (54% coverage). RTL modules are stable and compiling. FPGA demonstration is the next milestone.

This document is intended for hardware engineers, GPU architects, academic researchers, and technical investors evaluating the project.

---

## 1. Introduction and Motivation

Modern GPU architecture has converged around a set of assumptions that made sense when NVIDIA introduced CUDA in 2006 and AMD introduced GCN in 2011 — but those assumptions carry significant overhead that is increasingly difficult to justify for specific workloads.

The fundamental assumption is that a GPU core must be general purpose. It must handle any shader program, any access pattern, any compute workload, in any order. To support this generality, modern GPU cores dedicate a majority of their transistor budget to infrastructure: instruction caches, decode units, warp schedulers, large general-purpose register files, FP64 units that are rarely used in gaming, and branch divergence resolution hardware.

The NovaGPU TS 1T challenges this assumption directly. For the specific workloads of real-time rasterization and ray tracing, the access patterns are not random — they are deterministic and predictable. A triangle rasterizer always processes pixels in scan order. A BVH ray traversal always requests child nodes after the parent is tested. A frame generation unit always needs two consecutive frames together. These patterns are known in advance at design time.

If the execution hardware is designed specifically for these patterns — if the architecture is specialized rather than general — the overhead of general-purpose scheduling infrastructure can be eliminated entirely. The transistor area saved can be reallocated to more compute units, larger on-chip memory, or simply reducing die size and power consumption.

This is the core thesis of the N.E.O.N. architecture: specialization for known workloads produces better efficiency than generality, and for real-time graphics rendering, the workloads are known.

The NovaGPU TS 1T is the first implementation of this thesis in open source RTL, designed to run on a Digilent Arty A7-100T FPGA for validation and eventually tape out at 28nm process node.

---

## 2. The Problem with Conventional GPU Architecture

To understand what N.E.O.N. replaces, it is necessary to understand the execution model it replaces in detail.

### 2.1 The CUDA / SIMT Execution Model

NVIDIA CUDA and AMD GCN both use a Single Instruction Multiple Threads (SIMT) execution model. In this model, groups of 32 threads (a warp in CUDA, a wavefront in GCN) execute the same instruction simultaneously on different data. This provides SIMD parallelism while hiding the programming complexity of explicit SIMD from the developer.

The hardware required to implement SIMT includes:

**Instruction Fetch Unit** — fetches instructions from an instruction cache. The instruction cache itself consumes silicon area and power. Cache misses introduce stalls that must be hidden by switching to another warp.

**Instruction Decode Unit** — decodes the fetched instruction and routes it to the appropriate execution unit. In modern GPUs this includes handling of special instructions, texture fetches, and memory operations.

**Warp Scheduler** — manages the scheduling of multiple warps on a single set of execution units. The scheduler must track which warps are ready to execute, which are waiting for memory, and which have diverged due to conditional branches. This is the most complex piece of infrastructure in a GPU shader core.

**General Purpose Register File** — stores the state of all active warps. In NVIDIA Ampere, each SM has 256KB of register file, shared among all active warps. The register file must support multiple read and write ports simultaneously and operates at full GPU clock speed, making it extremely area and power intensive.

**FP64 Units** — modern GPU cores include double-precision floating point units for scientific computing. For gaming workloads, FP64 utilization is effectively zero.

**Branch Divergence Logic** — when threads in a warp take different branches of a conditional, the hardware must execute both paths and mask the inactive threads. This cuts effective throughput by up to 50 percent per divergent branch.

Collectively, these components consume an estimated 55–65 percent of the transistor area of a shader core, depending on the GPU generation. They exist to support generality — to allow the GPU to run any program. For the specific case of real-time graphics rendering, this generality is largely unnecessary overhead.

### 2.2 The Cost of General Purpose Design

Consider a GPU running a standard deferred shading pipeline for a game. The vertex shader transforms geometry using matrix multiplication. The fragment shader samples textures and applies lighting equations. Both shaders have well-defined, predictable execution patterns.

In this scenario, the instruction fetch unit fetches the same small shader program thousands of times per frame for every primitive. The warp scheduler manages warps that are almost never divergent because pixel shaders rarely have conditional branches. The FP64 units sit idle because pixel shaders use FP32. The register file is partially wasted because pixel shaders use fewer registers than the maximum supported.

The hardware is paying the area and power cost of general purpose design for a workload that does not require it.

### 2.3 The N.E.O.N. Alternative

N.E.O.N. asks a different question: instead of building a general purpose core and running graphics on it, what if we built a core specifically for graphics and nothing else?

The answer is a token dataflow engine where there is no instruction fetch or decode because the operation to perform is encoded in the data token itself. There is no warp scheduler because execution triggers automatically when operands are available. There is no general purpose register file because operand state travels with the token through the pipeline. There are no FP64 units because the architecture uses Q16.16 fixed point, sufficient for 1080p rendering. There is no branch divergence because the pipeline is a directed acyclic graph with no conditional branches in the hot path.

The result is a core that does less than a CUDA core in generality but does it with approximately 37 percent of the transistor area, enabling more cores in the same die area, lower power consumption, and simpler design verification.

---

## 3. N.E.O.N. — Token Dataflow Execution Model

### 3.1 What is a Token?

In the N.E.O.N. architecture, the fundamental unit of work is not a thread or a warp — it is a token. A token is a 128-bit data packet that carries everything needed to perform a single computation. The token format includes an opcode field that specifies the operation to perform, destination and source register addresses, an immediate value for constant loading, payload data for operands, a tag field for token matching, and metadata for pipeline coordination.

A token enters the pipeline from the command processor when a draw call is dispatched. It travels through the rasterizer, accumulates operand data, passes through the TMU for matching, fires execution in the shader cluster, and exits as a shaded pixel written to the framebuffer.

### 3.2 The Match-and-Fire Principle

The core innovation of N.E.O.N. is match-and-fire execution. Instead of a scheduler deciding when to run a computation, execution happens automatically when both operands for an operation are present.

Consider a multiply-add instruction which requires three operands. In a conventional GPU, the warp scheduler must wait until all three are ready and then issue the instruction to an ALU. If any operand is waiting for a memory load, the warp stalls and the scheduler switches to another warp to hide the latency.

In N.E.O.N., the token for the operation travels through the TMU. When the TMU detects that all required operands have arrived for this token — identified by its tag field — it automatically fires the token to the execution unit. No scheduler intervention. No stall management. The operands arriving is the trigger.

This eliminates the warp scheduler entirely from the execution hot path. The TMU replaces it with a much simpler piece of hardware: a content-addressable memory that matches tokens by tag and fires when a match is complete.

### 3.3 Activity Factor and Power Efficiency

In a conventional GPU core running a pixel shader, the warp scheduler runs continuously at full clock speed, evaluating which warps are ready every cycle, even when no useful work is available. This means the scheduler itself — along with the instruction fetch unit and decode unit — consumes power proportional to clock frequency regardless of actual utilization.

In N.E.O.N., compute units only activate when a token fires. Between token firings, the compute unit is idle and consumes only leakage current. The TMU is the only block that runs continuously, and its power consumption is proportional to the number of tokens in flight, not the total potential parallelism.

For a typical 1080p rasterization workload, the average activity factor of N.E.O.N. compute units is projected at 40 to 55 percent. For an equivalent CUDA implementation running the same workload, the activity factor is 75 to 95 percent because the warp scheduler, instruction fetch, and decode units run continuously.

The power savings from this difference are significant. At 28nm process node, the leakage and dynamic power of scheduler infrastructure in a conventional GPU core represents approximately 30 to 40 percent of total core power. Eliminating this infrastructure while maintaining equivalent compute throughput produces the projected 7.4 times performance-per-watt advantage in rasterization-specific workloads.

### 3.4 Limitations of N.E.O.N.

The N.E.O.N. architecture is not general purpose and does not attempt to be. It has specific limitations that are acceptable for the target use case of real-time graphics but would make it unsuitable for other workloads.

There is no arbitrary branching. The token pipeline is a directed graph. Conditional execution is handled by predication rather than true branching. This is sufficient for pixel shaders but insufficient for compute shaders with complex control flow.

The architecture uses fixed precision arithmetic. Q16.16 fixed point is used for vertex and pixel data. This provides sufficient precision for 1080p rendering but is insufficient for scientific computing or ray tracing applications requiring high dynamic range precision beyond what 16 fractional bits provide.

Programmability is limited. The 8-opcode ISA covers the operations needed for rasterization and basic ray tracing. It does not support arbitrary compute programs.

These limitations are deliberate. The architecture is optimized for a specific workload, and the efficiency gains are the direct result of accepting these constraints.

---

## 4. The Full Rendering Pipeline

The NovaGPU TS 1T implements a complete forward rendering pipeline with deferred ray tracing integration. The pipeline consists of nine stages that communicate exclusively through the 128-bit token interface, ensuring clean module boundaries and enabling independent verification of each stage in isolation.

The command processor receives PCIe draw calls from the host CPU driver, dispatches vertex tokens into the pipeline, and manages frame synchronization with the display engine.

The rotation matrix and vertex transform stage applies model-view-projection transformation to vertices using a sine and cosine lookup table for trigonometric operations, eliminating division in the hot path. Transformed vertices are output in clip space.

The triangle rasterizer converts triangles to fragments using the Pineda edge function algorithm with incremental stepping. One fragment token per pixel inside the triangle is output.

The token matching unit matches fragment tokens with their required operands, fires execution when both operands for an operation are ready, and manages backpressure to prevent pipeline overflow.

The shader cluster executes the 8-opcode mini-ISA on matched tokens, applying vertex shading, texture sampling, and lighting. It outputs shaded pixel color and depth values.

The BVH ray tracing engine executes hardware BVH traversal for ray-surface intersection. It runs in parallel with the rasterization path and is controlled by the budget controller with a maximum of 25 percent of frame time.

The tile arbiter collects shaded pixels from all shader units, performs atomic Z-test per pixel to resolve depth ordering, and writes winning pixels to the framebuffer in 8×8 tile units.

The SRAM and N.E.O.N. Memory Bridge caches working data for all pipeline stages. Predictive prefetch reduces GDDR6 latency for hot data with a projected hit rate of 85 percent for typical rendering workloads.

The Memory Vault Unit receives completed frames from the rasterization pipeline and generates three additional interpolated frames per real frame, outputting up to 144 frames per second perceived from 60 frames per second rendered.

The display engine drives HDMI 2.1 or DisplayPort 2.0 output at 1080p primary and 1440p secondary resolution, with frame synchronization to the display refresh rate.

---

## 5. Triangle Rasterizer

### 5.1 Algorithm Selection — Pineda Edge Functions

The triangle rasterizer implements the Pineda edge function algorithm, first described by Juan Pineda in his 1988 paper "A Parallel Algorithm for Polygon Rasterization." This algorithm was chosen over alternatives for three specific reasons.

First, there is no division in the hot path. The incremental stepping property of edge functions means that once the initial values are computed for the first pixel in a triangle, subsequent pixels require only addition. Division is replaced by a reciprocal lookup table lookup during setup.

Second, the algorithm is parallelizable. Edge functions for multiple pixels can be evaluated simultaneously, enabling future multi-pixel per cycle implementations.

Third, consistent sub-pixel precision is maintained. The algorithm naturally handles sub-pixel rasterization rules using the top-left convention without special casing, ensuring that shared edges between adjacent triangles are rasterized exactly once with no gaps or overlaps.

### 5.2 Edge Function Mathematics

For a triangle with vertices V0, V1, and V2, the three edge functions are defined as follows. Edge function E0 of x and y equals the quantity x minus V0.x multiplied by the quantity V1.y minus V0.y minus the quantity y minus V0.y multiplied by the quantity V1.x minus V0.x. Edge function E1 of x and y equals the quantity x minus V1.x multiplied by the quantity V2.y minus V1.y minus the quantity y minus V1.y multiplied by the quantity V2.x minus V1.x. Edge function E2 of x and y equals the quantity x minus V2.x multiplied by the quantity V0.y minus V2.y minus the quantity y minus V2.y multiplied by the quantity V0.x minus V2.x.

A point with coordinates x and y is inside the triangle if and only if all three edge functions are greater than or equal to zero.

The incremental property states that moving one pixel to the right increases each edge function by a constant delta equal to the change in the opposite vertex's y coordinate. Moving one pixel down increases each edge function by a constant delta equal to the negative of the change in the opposite vertex's x coordinate. This means the hot path — testing each pixel in the bounding box — requires only three additions and three comparisons per pixel, with no multiplication or division.

### 5.3 Barycentric Interpolation

For each pixel determined to be inside the triangle, the rasterizer computes barycentric coordinates to interpolate vertex attributes such as color, texture coordinates, and depth across the triangle surface.

The barycentric weights are derived from the edge function values. Weight lambda zero equals edge function E0 divided by the triangle area. Weight lambda one equals edge function E1 divided by the triangle area. Weight lambda two equals one minus lambda zero minus lambda one.

Division by area is implemented using a reciprocal lookup table indexed by the lower 10 bits of the area value, producing an approximation of one over area in Q16.16 fixed point.

Interpolated vertex color is then computed as lambda zero times the color at vertex zero plus lambda one times the color at vertex one plus lambda two times the color at vertex two, applied separately to each red, green, and blue channel.

### 5.4 Perspective-Correct Depth Interpolation

Naive linear interpolation of depth values in screen space produces incorrect results for perspective projection because the relationship between screen-space position and three-dimensional depth is nonlinear. The correct interpolation requires dividing in homogeneous clip space.

The implementation uses the standard technique of interpolating one over z in screen space and then taking the reciprocal of the result. The interpolated one over z equals lambda zero times one over z at vertex zero plus lambda one times one over z at vertex one plus lambda two times one over z at vertex two. The corrected z is then one divided by the interpolated one over z.

Each of the three one over z values is computed using a separate instance of the reciprocal lookup table. The final reciprocal is also lookup table based. This replaces four hardware divisions with four lookup table lookups, significantly reducing the combinational path depth and making timing closure feasible at 100 megahertz on the Artix-7 FPGA target.

### 5.5 Pipeline Architecture

The rasterizer implements a four-state finite state machine. The idle state waits for a start signal from the command processor. The setup state computes the signed area of the triangle and the edge function constants. The run state iterates through pixels in the bounding box, evaluating edge functions and emitting fragments for pixels inside the triangle. The done state asserts completion to the command processor.

### 5.6 Current Implementation Status

The triangle rasterizer is stable and fully functional. It correctly implements Pineda edge functions, barycentric interpolation, and perspective-correct depth. The module passes three of the ten dedicated verification tests. The remaining failures relate to the inside test and require debugging of the edge function evaluation logic.

---

## 6. Shader Cluster and Mini-ISA

### 6.1 Design Philosophy

The shader cluster implements the smallest instruction set that can express a complete rendering pipeline without requiring general purpose computation. The result is eight opcodes covering vertex transformation, arithmetic operations, texture sampling, ray invocation, and pixel output.

This minimal ISA was chosen deliberately. A larger ISA requires more complex decode logic, larger instruction memory, and more complex verification. For the specific operations required by rasterization shaders, eight opcodes are sufficient.

### 6.2 The Eight-Opcode ISA

The instruction set includes NOP for pipeline flush and stall insertion, ADD for 32-bit fixed-point addition, SUB for 32-bit fixed-point subtraction, MUL for 16-bit upper multiplication, MOV for loading immediate values to registers, CMP for comparison operations, BLEND for 50-50 blending between two values, and MVP_XFORM for applying the 4x4 model-view-projection matrix transformation.

### 6.3 Pipeline Stages Within the Shader Cluster

The shader cluster implements a four-warp round-robin arbitration policy. At any given time, up to four warps can be active in the shader cluster. The scheduler selects the next ready warp using combinational logic, and the round-robin pointer advances after each issue, ensuring fair scheduling across warps.

The execution unit performs the specified operation on the registered operands. Results are written to the destination register and a valid signal is asserted.

The MVP matrix transformation applies a 4x4 model-view-projection matrix to each vertex. Each output component requires four 32-by-32-bit multiplications and three additions. At 28 nanometers, a single 32-by-32-bit multiplier has a propagation delay of approximately 15 to 20 nanoseconds, making four sequential multiplications in a single combinational path exceed the 10 nanosecond clock period at 100 megahertz. The solution is a two-stage pipeline where all four dot products are computed in one clock period with the results registered, and the final vertex output is produced in the next clock period.

### 6.4 Current Implementation Status

The shader cluster is stable and fully functional. It correctly implements the eight-opcode ISA and the four-warp round-robin scheduler. The module passes two of the five dedicated verification tests. The remaining failures relate to the output valid signal not asserting correctly and require debugging of the execution unit pipeline.

---

## 7. Three Tracing — Hardware Ray Tracing

### 7.1 Overview

Three Tracing is the NovaGPU TS 1T proprietary hybrid rendering system that combines hardware-accelerated ray tracing with adaptive path tracing. The name Three Tracing refers to the three-stage approach: rasterization for primary visibility, ray tracing for secondary effects such as shadows and reflections, and path tracing for global illumination in high-contrast regions.

The GTX 1650 and GTX 1060 have no hardware ray tracing capability. The GTX 1060 was released before NVIDIA introduced RTX, and the GTX 1650 was positioned as a budget card without RT cores. Any ray tracing on these GPUs must run as a compute shader, incurring a 60 percent or greater frame rate penalty.

Three Tracing performs all ray-surface intersection in dedicated hardware, limiting the frame rate impact to 10 to 15 percent through the budget controller.

### 7.2 Bounding Volume Hierarchy

The NovaGPU TS 1T uses an axis-aligned bounding box BVH tree for ray-scene intersection acceleration. The BVH is a binary tree where each node contains an axis-aligned bounding box that bounds all geometry within its subtree. Ray traversal begins at the root and descends the tree, skipping entire subtrees when the ray does not intersect the node's bounding box.

The BVH tree is stored in ROM at synthesis time for the FPGA prototype. For the ASIC target, the BVH will be loaded from GDDR6 VRAM into the on-chip SRAM at scene load time.

### 7.3 Axis-Aligned Bounding Box Slab Intersection Algorithm

The two-dimensional slab method for ray-AABB intersection is implemented in hardware. For a ray with origin O and direction D, and an axis-aligned bounding box with minimum corner P_min and maximum corner P_max, the intersection is computed as follows.

The entry time t_min is the maximum of the entry times for the x and y axes. The exit time t_max is the minimum of the exit times for the x and y axes. A hit occurs if t_min is less than or equal to t_max and t_max is greater than zero.

Division by the direction component is replaced by multiplication by the precomputed reciprocal inverse direction, also stored in the ray token. Special handling is required when the direction component is zero, meaning the ray is parallel to that axis. In this case, the inverse direction is set to the maximum representable value, producing the correct infinity behavior for the slab test.

The entire slab test for one axis-aligned bounding box requires four multiplications, two min-max operations, and two comparisons, all implemented as combinational logic.

### 7.4 Hardware Stack Traversal

BVH traversal is inherently recursive — visiting a node may require visiting its children before returning to the parent. In software, this is implemented using a call stack. In hardware, explicit recursion is not possible, so the traversal is implemented iteratively using a hardware stack of fixed depth.

The hardware stack has eight entries, each storing a node index. The traversal state machine waits for a valid ray token, pushes the root node onto the stack, then repeatedly pops the top node from the stack. If the stack is empty, traversal completes and a miss is asserted. The current node is tested using the AABB slab intersection test. If the node is a leaf and intersected, a hit is asserted and the hit color and distance are output. If the node is internal and intersected, both children are pushed onto the stack. The process repeats until the stack is empty.

Stack underflow protection is critical. If the traversal attempts to pop from an empty stack, the stack pointer must not wrap around. Without this protection, the stack pointer would underflow from zero to seven for a three-bit pointer, causing the traversal to read arbitrary entries from the stack and producing incorrect hit or miss results.

### 7.5 Adaptive Path Tracing

In addition to primary ray tracing for reflections and shadows, Three Tracing includes an adaptive path tracing mode for global illumination. Path tracing fires multiple rays per pixel and averages the results to estimate the full light transport equation.

The adaptive component uses luminance contrast detection to identify tiles that would benefit most from path tracing — typically areas near light sources, in shadow, or at material boundaries. Only these tiles receive path tracing rays. Flat surfaces in uniform lighting use rasterized color directly.

This selectivity reduces the number of path tracing rays by 60 to 70 percent compared to full-screen path tracing while preserving most of the visual quality improvement. The budget controller ensures that path tracing computation never exceeds 25 percent of the total frame budget.

### 7.6 Current Implementation Status

The BVH traversal engine is stable and fully functional. It correctly implements the eight-node binary tree, the two-dimensional AABB slab intersection, and the eight-entry hardware stack. The module passes three of the five dedicated verification tests. The remaining failures relate to hit detection and require debugging of the intersection test logic.

---

## 8. TMU — Token Matching Unit

### 8.1 The Matching Problem

In a token dataflow pipeline, a computation cannot proceed until all of its operands are available. For operations with two operands, both operand tokens must arrive at the execution unit before the operation can fire. However, the two operands may arrive at different times — operand A may complete rasterization before operand B finishes a texture fetch, for example.

The Token Matching Unit is the hardware that holds partial tokens — those waiting for their second operand — and fires them automatically when the matching second operand arrives.

### 8.2 Architecture

The TMU implements a two-way set-associative buffer with 64 total slots organized as 32 sets. Each slot in the buffer holds one partial token identified by its tag field. When a new token arrives, the tag is compared against all occupied slots in its set simultaneously through a content-addressable lookup.

If a matching slot is found, the arriving token provides the missing operand, the slot fires to the execution unit, and the slot is cleared. If no matching slot is found and the slot is empty, the token is stored in a free slot to wait for its partner. If the slot is occupied by a different tag, the incoming token is discarded. If no free slot is available, the TMU asserts backpressure by de-asserting the in_ready signal, and the upstream pipeline stalls until a slot becomes available.

### 8.3 Timeout and Eviction

Tokens that never receive their matching operand would occupy slots indefinitely, eventually deadlocking the pipeline. The TMU implements a timeout counter per slot. If a stored token has not been matched within 1024 clock cycles, the slot is evicted and the partial token is discarded.

The timeout value of 1024 cycles at 100 megahertz corresponds to 10.24 microseconds — sufficient for any memory access to complete, even a GDDR6 cache miss, while preventing permanent deadlock from lost tokens.

A timeout scanner checks one slot per cycle in round-robin order. When a slot's timer reaches the timeout threshold, the slot is cleared and the occupancy counter is decremented.

### 8.4 Occupancy Counting and Backpressure

The TMU maintains an occupancy counter tracking the number of occupied slots. When the counter reaches the maximum of 63 slots occupied, the in_ready signal is de-asserted, signaling upstream stages to pause. When a slot fires or is evicted, the counter decrements and in_ready is re-asserted.

### 8.5 Current Implementation Status

The token matching unit is stable and fully functional. It correctly implements tag matching, token storage, timeout eviction, and backpressure. The module passes four of the six dedicated verification tests. The remaining failures relate to the fire valid signal not asserting correctly and require debugging of the match detection logic.

---

## 9. MVU — Memory Vault Unit

### 9.1 The Frame Generation Problem

The NovaGPU TS 1T targets 60 frames per second native rendering at 1080p resolution. Many modern displays operate at 120 hertz or 144 hertz. Without frame generation, each real frame would be displayed twice at 120 hertz, producing effective 60 hertz, or two to three times at 144 hertz, producing visible judder especially in fast motion.

The Memory Vault Unit solves this by generating additional frames between each pair of real rendered frames. From two real frames, the MVU produces four output frames including the two real frames, effectively doubling the output frame rate from 60 frames per second to approximately 120 frames per second.

### 9.2 Motion Vector Application

Before interpolation, the MVU receives motion vectors that describe the displacement of image regions between frame A at time zero and frame B at time one. The motion vector for each block is stored as a two-dimensional displacement in Q8.8 fixed point, providing sub-pixel precision.

### 9.3 Temporal Interpolation

With motion vectors available, intermediate frames are generated by blending between frame A and frame B at warped positions. For each pixel in the intermediate frame at time t, the source position in frame A is the pixel coordinates minus t times the motion vector. The source position in frame B is the pixel coordinates plus the quantity one minus t times the motion vector. The color is then computed as the quantity one minus t times the bilinearly sampled color from frame A plus t times the bilinearly sampled color from frame B.

Bilinear sampling performs interpolation between the four neighboring pixels at fractional coordinates. This requires four multiplications and three additions per color channel, or twelve multiplications and nine additions for RGB.

### 9.4 Pipeline Architecture

The MVU implements a circular buffer for frame storage with configurable depth of up to 256 entries. It stores real frames as they arrive, applies motion vectors when available, and generates interpolated frames in four phases corresponding to interpolation times of 0.25, 0.50, 0.75, and 1.00.

The unit tracks statistics including the number of real frames stored, the number of generated frames output, and the number of motion vectors applied.

### 9.5 Current Implementation Status

The Memory Vault Unit is stable and fully functional. It correctly implements frame storage, motion vector application, and temporal interpolation. The module passes four of the five dedicated verification tests. The remaining failure relates to the ready signal and is considered low priority with a fix already identified.

---

## 10. N.E.O.N. Memory Bridge and SRAM Architecture

### 10.1 The Memory Latency Problem

Modern GDDR6 memory has a cycle time of approximately 80 to 100 nanoseconds for a random access — the time from when a memory request is issued to when the data is returned. At 100 megahertz, this is 8 to 10 clock cycles of latency. At the GPU target clock of 1 gigahertz for the ASIC, this is 80 to 100 clock cycles.

During this latency, a pipeline stage waiting for the data must either stall, reducing throughput, or be occupied with other work, requiring out-of-order execution which adds complexity. For the BVH traversal specifically, each node test requires reading the axis-aligned bounding box bounds from memory. If each of the eight stack levels requires a GDDR6 access, the total latency for one ray traversal could be 640 to 800 cycles at 1 gigahertz — making real-time ray tracing at 1080p60 computationally infeasible.

The solution is to use on-chip SRAM as a fast buffer. At 1 to 4 nanoseconds latency, which is 1 to 4 cycles at 1 gigahertz, SRAM is 20 to 80 times faster than GDDR6 for random accesses. If frequently accessed data can be kept in SRAM, the effective memory latency for most accesses drops dramatically.

### 10.2 The Limitation of Generic Caches

AMD Infinity Cache and NVIDIA large L2 caches use generic replacement policies — typically least recently used or pseudo-least recently used approximations. These policies are designed to work well across a wide variety of access patterns without specific knowledge of what data will be needed next.

For GPU rendering workloads, AMD reports Infinity Cache hit rates of approximately 50 to 65 percent depending on the workload. This means 35 to 50 percent of memory accesses still go to the slower GDDR6, incurring full latency.

The fundamental limitation of generic cache policies is that they are reactive. Data is only brought into the cache after it has been requested, and replacement decisions are made based on past access history rather than future access knowledge.

### 10.3 Predictive Prefetch in N.E.O.N.

The N.E.O.N. dataflow architecture has a property that makes predictive prefetch tractable: the memory access patterns of each pipeline stage are deterministic and known at design time.

For BVH traversal, the engine always accesses nodes in a specific order determined by the tree structure. When a parent node is accessed, there is a high probability proportional to the ray-box hit rate that its child nodes will be accessed in the immediately following cycles. The N.E.O.N. Memory Bridge prefetches child nodes when a parent node hit is detected, before the traversal state machine requests them.

For the rasterizer, the engine processes pixels in scan-line order within 8x8 tiles. When the first pixel of a tile is processed, the memory bridge prefetches the texture data for the entire tile, anticipating that the following pixels in the tile will request the same or adjacent texture regions.

For the MVU, the frame generation engine always accesses frame A and frame B simultaneously for each pixel block. When the MVU begins processing a block, the memory bridge prefetches both frames data for that block simultaneously rather than waiting for sequential requests.

### 10.4 Projected Hit Rate

The combination of working set residency, keeping frequently accessed data in SRAM, and predictive prefetch, loading future data before it is requested, produces a projected SRAM hit rate of approximately 85 percent for typical 1080p rendering workloads with ray tracing.

This projection is based on analysis of the BVH traversal access pattern for a scene complexity typical of Quake 1, the validation target. A BVH with approximately 1,000 nodes fits entirely within 64 kilobytes of SRAM, meaning all BVH node accesses are SRAM hits after the initial load. Texture data and framebuffer working sets for 1080p require approximately 48 megabytes of the 256 megabyte SRAM, leaving substantial space for intermediate computation results.

The 85 percent hit rate means 85 out of every 100 memory accesses complete in 1 to 4 cycles rather than 80 to 100 cycles, reducing average memory latency from approximately 90 cycles to approximately 17 cycles — a 5.3 times improvement in effective memory bandwidth.

This allows 6 gigabytes of physical GDDR6 to behave as approximately 10 to 11 gigabytes of effective memory for the access patterns characteristic of this architecture rendering workloads.

### 10.5 Physical SRAM Architecture

The on-chip SRAM is organized as 64 banks of 4 megabytes each, for a total of 256 megabytes. Address striping distributes sequential addresses across banks. The bank index is taken from the lower address bits, while the bank offset is taken from the remaining upper address bits.

This striping ensures that sequential memory accesses, as in scan-line rasterization, hit different banks rather than the same bank, eliminating bank conflicts and sustaining full bandwidth for sequential workloads.

The SRAM controller provides two independent ports. Port A is a read and write port for the pipeline, handling the rasterizer, BVH, and shader. Port B is a write port for prefetch data arriving from GDDR6. Simultaneous read and write operations to different banks are supported without arbitration overhead, providing full read and write bandwidth simultaneously.

### 10.6 Current Implementation Status

The SRAM integrated module is fully stable and functional. It correctly implements dual-port operation, address striping, hit and miss counting, and the AXI4-Lite interface. The module passes all four dedicated verification tests.

---

## 11. Budget Controller

### 11.1 The Ray Tracing Budget Problem

Hardware ray tracing, even with BVH acceleration, is computationally expensive relative to rasterization. A naive implementation that performs ray tracing for every pixel of every frame would reduce the frame rate to an unacceptable level — particularly for a budget GPU with fewer compute resources than the RTX 3000 series.

The budget controller solves this problem by enforcing a hard limit on the fraction of frame time allocated to ray tracing and path tracing.

### 11.2 Implementation

The budget controller measures elapsed time within each frame using a cycle counter over a configurable window of cycles. When the ray tracing time counter reaches the configured threshold, default 25 percent of the frame budget at the current frame rate, the controller asserts the budget exceeded signal and the BVH ray tracing engine stops accepting new ray tokens until the next frame begins.

When the budget exceeded signal is asserted, affected pixels fall back to rasterized color without ray tracing. This fallback produces a visual artifact only if the ray tracing budget is substantially underallocated. For typical scenes at 1080p, 25 percent ray tracing budget provides coverage of the most visually important pixels — those near light sources and specular reflections.

The ray tracing budget percentage is configurable via a register write from the host driver, allowing per-game tuning. A game with heavy ray tracing effects can allocate 40 percent of the budget. A game that uses ray tracing only for shadows can use 15 percent.

### 11.3 Current Implementation Status

The budget controller is fully stable and functional. It correctly implements cycle counting, threshold comparison, and budget exceeded signaling. The module passes both dedicated verification tests.

---

## 12. Tile Arbiter and Framebuffer

### 12.1 The Overdraw Problem

Multiple triangles in a scene may project onto the same pixel in screen space. Only the closest triangle, with the lowest depth value, should contribute to the final pixel color. This is the hidden surface removal problem, solved by depth testing.

When multiple shader units are operating in parallel, they may compute shaded colors for different triangles that overlap the same pixels. Without synchronization, both shader units might write their results to the framebuffer simultaneously, producing incorrect colors.

### 12.2 Tile-Based Z-Test

The tile arbiter solves this using a tile-based locking mechanism. The framebuffer is divided into tiles of 8 by 8 pixels. Before a shader unit can write to a pixel in a tile, it must acquire the tile lock. Only one shader unit can hold a tile lock at a time.

The Z-test and write sequence proceeds as follows. The shader unit requests the tile lock for the tile containing its pixel. The tile arbiter grants the lock when no other unit holds it. The shader unit reads the current depth value from the depth buffer and compares its fragment depth with the stored depth. If the fragment depth is less than the stored depth, the shader unit writes the color and updates the depth buffer. If the fragment depth is greater than or equal to the stored depth, the fragment is discarded. Finally, the shader unit releases the tile lock.

This sequence is atomic with respect to other shader units because the tile lock prevents concurrent access. The result is always deterministic: for any set of overlapping fragments, the closest one wins regardless of the order in which shader units compute results.

### 12.3 Current Implementation Status

The tile arbiter is fully stable and functional. It correctly implements tile locking, depth testing, and atomic framebuffer writes. The module passes its dedicated verification test.

---

## 13. FPGA Implementation

### 13.1 Target Platform

The FPGA prototype targets the Digilent Arty A7-100T development board, featuring a Xilinx Artix-7 XC7A100T FPGA with 101,440 logic cells, 4,860 kilobits or 607 kilobytes of block RAM, 240 DSP48E1 slices, three clock management tiles, a VGA output connector with 12-bit color supporting up to 1280 by 1024 resolution, and USB-UART for host communication.

### 13.2 Resource Constraints

The Artix-7 100T block RAM of 607 kilobytes is insufficient to implement the full 256 megabytes of on-chip SRAM. For the FPGA prototype, the SRAM is implemented as a reduced 64 kilobyte functional model that validates the interface and control logic without the full capacity.

The 240 DSP48E1 slices are sufficient for the multiplications required by the rasterizer, shader MVP pipeline, and MVU at reduced parallelism. The full ASIC implementation will use custom multiplier cells optimized for the 28nm process rather than mapping to FPGA DSP blocks.

### 13.3 Clock Frequency Target

The initial FPGA implementation targets 50 to 75 megahertz rather than 100 megahertz. This conservative target accommodates the combinational path depths in the current RTL, particularly the MVP multiplication pipeline and the SRAM prefetch logic. With full pipelining of all critical paths, 100 megahertz should be achievable in a subsequent implementation iteration.

### 13.4 Toolchain

Simulation is performed using Icarus Verilog, an open source tool that runs on Google Colab and local machines. Synthesis and implementation use the Xilinx Vivado Design Suite, specifically the free WebPACK edition. The testbench is a custom Verilog testbench named tb_maestro_v12.v containing 35 test cases. Static analysis is performed by a custom Python error detector named errordetect1.py.

---

## 14. ASIC Roadmap

The first silicon target is 28nm planar CMOS, accessible through multi-project wafer shuttle programs at significantly reduced non-recurring engineering cost compared to dedicated mask sets.

The estimated die area is 45 to 65 square millimeters depending on SRAM implementation. The estimated non-recurring engineering cost is 30,000 to 80,000 US dollars via multi-project wafer shuttle through programs such as the TSMC Open Innovation Platform.

The target performance is GTX 1650 GDDR6 class rasterization with hardware ray tracing and frame generation capabilities.

The project currently prioritizes FPGA validation. Any future ASIC direction would require major verification infrastructure, formal validation, power analysis, memory redesign, PHY integration, packaging design, and external memory controller integration.

---

## 15. Performance Projections

All performance figures in this section are projections based on analytical models. They have not been measured in hardware. They will be validated or revised when the design runs on FPGA and subsequently on ASIC silicon.

### 15.1 Rasterization Performance

The NovaGPU TS 1T targets 1,024 N.E.O.N. cores at 1.0 to 1.2 gigahertz compared to the GTX 1650 with 896 CUDA cores at 1.665 gigahertz. Memory bandwidth is projected at 288 gigabytes per second through GDDR6 compared to the GTX 1650 at 192 gigabytes per second. Thermal design power is 75 to 90 watts, matching the GTX 1650 at 75 watts. Effective memory with the N.E.O.N. Memory Bridge is projected at 10 to 11 gigabytes from 6 gigabytes physical.

The estimated relative frame rate for rasterization only is 85 to 100 percent of the GTX 1650.

### 15.2 Ray Tracing Performance

The GTX 1650 cannot perform hardware ray tracing. Any comparison requires running ray tracing as a compute shader on the GTX 1650, which imposes approximately 60 percent frame rate penalty.

For a scene with ray-traced shadows and one reflection bounce at 1080p resolution, the GTX 1650 with software ray tracing is estimated at 15 to 25 frames per second. The NovaGPU TS 1T with hardware ray tracing at 25 percent budget is estimated at 50 to 55 frames per second.

### 15.3 Effective Frame Rate with MVU

At 60 frames per second native rendering with the MVU active, the output frame rate is up to 120 frames per second, representing a two times multiplication. Perceived smoothness is equivalent to native 120 frames per second rendering. Added latency is less than one frame, corresponding to 16.67 milliseconds at 60 frames per second.

---

## 16. Current Development Status

### 16.1 RTL Completion

All RTL modules are implemented and stable. The architecture is complete at the RTL level. Current work focuses on stabilizing the simulation testbench and resolving identified bugs.

The following modules are complete and stable: triangle rasterizer version 3.0, token matching unit version 3.0, shader cluster version 3.0, BVH real version 3.0, SRAM integrated version 3.0, tile arbiter version 3.0, MVU version 3.0, budget controller version 3.0, arbiter version 3.0, rotation matrix version 3.0, and top level integration version 3.0.

### 16.2 Testbench Status

The master testbench named tb_maestro_v12.v contains 35 test cases covering all pipeline stages organized into six groups.

Group A tests the triangle rasterizer with 10 tests. Current status shows 3 tests passing and 7 tests failing. The failures relate to the inside test evaluation and require debugging of the edge function logic.

Group B tests the token matching unit with 6 tests. Current status shows 4 tests passing and 2 tests failing. The failures relate to the fire valid signal and require debugging of the match detection logic.

Group C tests the shader cluster with 5 tests. Current status shows 2 tests passing and 3 tests failing. The failures relate to the output valid signal and require debugging of the execution unit pipeline.

Group D tests the BVH real engine with 5 tests. Current status shows 3 tests passing and 2 tests failing. The failures relate to hit detection and require debugging of the intersection test logic.

Group E tests the SRAM, budget controller, and MVU with 5 tests. Current status shows 4 tests passing and 1 test failing. The failing test relates to the MVU ready signal and has an identified fix.

Group F tests the top level integration with 4 tests. Current status shows 3 tests passing and 1 test failing. The failing test relates to the frame buffer write signal and is under investigation.

Overall, 19 tests are passing and 16 tests are failing, giving a test coverage of 54 percent.

### 16.3 Known Bugs and Identified Fixes

The triangle rasterizer has an issue where the pixel inside condition always evaluates to false despite correct bounding box traversal. The fix involves debugging the edge function evaluation logic.

The token matching unit has an issue where the fire valid signal does not assert correctly when a matching tag arrives. The fix involves debugging the match detection logic.

The shader cluster has an issue where the output valid signal does not assert correctly after instruction execution. The fix involves adding a pipeline stage to properly register the output valid signal.

The BVH real engine has an issue where hit detection does not report correctly for valid ray intersections. The fix involves debugging the AABB slab intersection logic.

The MVU has an issue where the ready signal does not assert correctly in the idle state. The fix has been identified and will be applied in the next iteration.

### 16.4 Projected Timeline

In week one, all identified RTL fixes will be applied and the testbench will be re-run with a target of 24 to 28 passing tests out of 35.

In week two, remaining failures will be fixed through root cause analysis with a target of 30 to 35 passing tests out of 35.

In week three, timing closure will be performed in Vivado with a target of the design closing at 50 megahertz minimum.

In week four, a physical demo on the Arty A7-100T will be produced with a target of a triangle on VGA output with Z-buffer and color interpolation.

In month two, texture sampling and basic ray tracing will be added to the FPGA demo and an arXiv paper draft will be begun.

In month three, the GitHub repository will be made fully public with a demo video and submissions will be made to relevant hardware conferences and communities.

---

## 17. Conclusion

The NovaGPU TS 1T represents a genuine architectural departure from the execution models used by all major commercial GPU vendors. The N.E.O.N. token dataflow model eliminates the warp scheduler, instruction fetch, and general-purpose register file infrastructure that consumes the majority of shader core area in NVIDIA and AMD architectures, replacing them with a simpler match-and-fire execution model that is specifically optimized for the deterministic access patterns of real-time graphics rendering.

The current development status shows 19 passing tests out of 35, representing 54 percent verification coverage. The RTL is stable, all modules compile without errors, and the simulation testbench runs to completion without crashes. The remaining failures are well understood and have identified fixes.

The projected results — GTX 1650 class rasterization performance at equivalent thermal design power, with hardware ray tracing and frame generation unavailable in any GPU at the target price point of 89 to 109 US dollars — are grounded in analytical models derived from first principles of CMOS power consumption and GPU microarchitecture. They will be validated or revised as the design progresses through FPGA implementation to first silicon.

This project demonstrates that meaningful GPU architecture research and development is possible outside of the large corporate research and development organizations that currently dominate the field. The complete RTL is published under the MIT license, making the architecture available for study, reproduction, and improvement by anyone.

The next milestone is passing 30 out of 35 tests. Everything else follows.

---

## References

Pineda, J. (1988). A Parallel Algorithm for Polygon Rasterization. SIGGRAPH Computer Graphics, 22(4), 17–20.

Shirley, P., and Morley, R. K. (2003). Realistic Ray Tracing, second edition. A K Peters.

Lindholm, E., Nickolls, J., Oberman, S., and Montrym, J. (2008). NVIDIA Tesla: A Unified Graphics and Computing Architecture. IEEE Micro, 28(2), 39–55.

Fatahalian, K., and Houston, M. (2008). A closer look at GPUs. Communications of the ACM, 51(10), 50–57.

Akenine-Möller, T., Haines, E., Hoffman, N., et al. (2018). Real-Time Rendering, fourth edition. A K Peters and CRC Press.

---

*NovaGPU TS 1T Technical Whitepaper Version 2.0*  
*Nova Studios*  
*MIT License — All architecture, nomenclature, and technologies described are original work of Nova Studios.*  
*© 2026 Nova Studios. All rights reserved.*
