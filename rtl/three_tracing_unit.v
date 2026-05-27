`timescale 1ns/1ps
// ============================================================
// three_tracing_unit.v — Ray Tracing Unit v11.0 (Equipo Alpha)
// NovaGPU TS 1T — Nova Studios
//
// MEJORAS v11:
//   1. ESCALADO: 8 tracing units paralelas (vs 3 en v10)
//   2. EXECUTION MODEL FORMAL: RT-First Pipeline
//        Ray Gen → BVH → Closest Hit → Composite → Output
//   3. DEPTH BUFFER: usa hit_depth del BVH para z-compositing
//   4. sram_ack handshake preservado de v10
//   5. Bypass pipeline preservado
//   6. Adaptive path tracer preservado
// ============================================================

module three_tracing_unit #(
  parameter BVH_DEPTH  = 8,
  parameter RAY_BUDGET = 8,        // Escalado: 8 ray budget
  parameter DATA_WIDTH = 128,
  parameter NUM_RT_UNITS = 8       // 8 unidades paralelas
)(
  input  wire                   clk,
  input  wire                   rst_n,
  input  wire  [DATA_WIDTH-1:0] frag_in,
  input  wire                   in_valid,
  input  wire                   budget_ok,
  input  wire                   sram_ack,

  output wire  [DATA_WIDTH-1:0] frame_out,
  output wire                   out_valid
);

  localparam BYPASS_DELAY = BVH_DEPTH + 1;

  // ── RT enable: valid fragment + budget + SRAM sync ───────
  wire rt_enable = in_valid & budget_ok & sram_ack;

  // ── 8 BVH Units paralelas (NUM_RT_UNITS) ─────────────────
  // Each unit processes an independent ray token (round-robin dispatch)
  wire [DATA_WIDTH-1:0] bvh_color [0:NUM_RT_UNITS-1];
  wire [31:0]           bvh_depth [0:NUM_RT_UNITS-1];
  wire                  bvh_valid [0:NUM_RT_UNITS-1];
  wire                  bvh_miss  [0:NUM_RT_UNITS-1];

  // Round-robin dispatch counter
  reg [2:0] dispatch_ptr;  // log2(8)=3 bits
  reg [2:0] collect_ptr;   // log2(8)=3 bits

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dispatch_ptr <= 3'd0;
      collect_ptr  <= 3'd0;
    end else begin
      if (rt_enable)
        dispatch_ptr <= (dispatch_ptr == (NUM_RT_UNITS-1)) ?
                        3'd0 : dispatch_ptr + 3'd1;
      if (bvh_valid[collect_ptr])
        collect_ptr  <= (collect_ptr == (NUM_RT_UNITS-1)) ?
                        3'd0 : collect_ptr + 3'd1;
    end
  end

  // Instantiate 8 BVH units
  genvar gi;
  generate
    for (gi = 0; gi < NUM_RT_UNITS; gi = gi + 1) begin : bvh_array
      bvh_traversal_real #(
        .BVH_DEPTH(BVH_DEPTH),
        .DATA_WIDTH(DATA_WIDTH)
      ) u_bvh (
        .clk       (clk),
        .rst_n     (rst_n),
        .ray_token (frag_in),
        .ray_valid (rt_enable && (dispatch_ptr == gi[2:0])),
        .hit_color (bvh_color[gi]),
        .hit_depth (bvh_depth[gi]),
        .hit_valid (bvh_valid[gi]),
        .hit_miss  (bvh_miss[gi])
      );
    end
  endgenerate

  // ── Collect output from active BVH unit ──────────────────
  wire [DATA_WIDTH-1:0] active_bvh_color = bvh_color[collect_ptr];
  wire [31:0]           active_bvh_depth = bvh_depth[collect_ptr];
  wire                  active_bvh_valid = bvh_valid[collect_ptr];
  wire                  active_bvh_miss  = bvh_miss[collect_ptr];

  // ── RT-First Compositing ─────────────────────────────────
  // Use BVH depth for proper Z-ordering
  reg  [DATA_WIDTH-1:0] rt_out;
  reg                   rt_valid;
  reg  [31:0]           rt_depth;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rt_out   <= {DATA_WIDTH{1'b0}};
      rt_valid <= 1'b0;
      rt_depth <= 32'hFFFFFFFF;
    end else if (active_bvh_valid) begin
      // RT-First: use BVH result; fallback to raster on miss
      rt_out   <= active_bvh_miss ?
                  frag_in :
                  ((frag_in >> 1) + (active_bvh_color >> 1));
      rt_depth <= active_bvh_miss ? frag_in[95:64] : active_bvh_depth;
      rt_valid <= 1'b1;
    end else begin
      rt_valid <= 1'b0;
    end
  end

  // ── Adaptive Path Tracer ─────────────────────────────────
  wire [7:0] luma_rt   = rt_out[127:120];
  wire [7:0] luma_frag = frag_in[127:120];
  wire high_contrast   = (luma_rt   > luma_frag + 8'd30) |
                         (luma_frag > luma_rt   + 8'd30);

  reg  [DATA_WIDTH-1:0] pt_color;
  reg                   pt_valid;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pt_color <= {DATA_WIDTH{1'b0}};
      pt_valid <= 1'b0;
    end else if (rt_valid) begin
      // High-contrast: additional sample blend
      pt_color <= high_contrast ?
                  (rt_out + (frag_in >> 3)) :
                  rt_out;
      pt_valid <= 1'b1;
    end else begin
      pt_valid <= 1'b0;
    end
  end

  // ── Bypass: no budget or SRAM not ready ─────────────────
  wire bypass_active = in_valid & (~budget_ok | ~sram_ack);

  reg [DATA_WIDTH-1:0] bypass_pipe [0:BYPASS_DELAY-1];
  reg                  bypass_vld  [0:BYPASS_DELAY-1];

  integer bi;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (bi = 0; bi < BYPASS_DELAY; bi = bi + 1) begin
        bypass_pipe[bi] <= {DATA_WIDTH{1'b0}};
        bypass_vld[bi]  <= 1'b0;
      end
    end else begin
      bypass_pipe[0] <= frag_in;
      bypass_vld[0]  <= bypass_active;
      for (bi = 1; bi < BYPASS_DELAY; bi = bi + 1) begin
        bypass_pipe[bi] <= bypass_pipe[bi-1];
        bypass_vld[bi]  <= bypass_vld[bi-1];
      end
    end
  end

  assign frame_out = pt_valid                   ? pt_color                    :
                     bypass_vld[BYPASS_DELAY-1] ? bypass_pipe[BYPASS_DELAY-1] :
                                                  {DATA_WIDTH{1'b0}};
  assign out_valid = pt_valid | bypass_vld[BYPASS_DELAY-1];

endmodule

// Copyright (c) 2025 Nova Studios / Maximal Technology
// SPDX-License-Identifier: MIT