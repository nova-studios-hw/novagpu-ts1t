`timescale 1ns/1ps
// ============================================================
// top.v — Integrador Principal NovaGPU TS 1T v11.0 (Equipo Alpha)
// Nova Studios
//
// MEJORAS v11 (Auditoría Profunda):
//   1. EXECUTION MODEL FORMAL declarado: Ray Tracing First
//        Ray Gen → BVH Traverse → Closest Hit → Shade → Output
//   2. MVP matrix load interface expuesto desde top
//   3. AXI4-Lite outputs del SRAM expuestos
//   4. Bandwidth counters por segmento de memoria
//   5. NUM_RT_UNITS parametrizado (8 por defecto)
//   6. Todos los fixes v10.x preservados
// ============================================================

module novagpu_ts1t_top #(
  parameter NUM_CORES           = 1024,
  parameter NUM_CU              = 16,
  parameter TOKEN_WIDTH         = 128,
  parameter TAG_WIDTH           = 16,
  parameter TMU_SLOTS           = 1024,
  parameter MVU_REAL_FRAMES     = 2,
  parameter MVU_GEN_FRAMES      = 4,
  parameter TARGET_FREQ_SILICON = 400,   // Realista: 400 MHz ASIC / 250 MHz FPGA
  parameter BYPASS_DEPTH        = 64,
  parameter NUM_ARB_PORTS       = 16,
  parameter TT_BVH_DEPTH        = 8,
  parameter TT_RAY_BUDGET       = 8,     // Escalado
  parameter TT_NUM_RT_UNITS     = 8,     // 8 tracing units paralelas
  parameter RT_PERCENT          = 25,
  parameter SCREEN_W            = 640,
  parameter SCREEN_H            = 480
)(
  input  wire         clk,
  input  wire         rst_n,

  // ── PCIe / Data Interface ────────────────────────────────
  input  wire  [255:0] pcie_data_in,
  output wire  [255:0] pcie_data_out,
  input  wire          pcie_valid,
  output wire          pcie_ready,

  // ── Motion Vectors ───────────────────────────────────────
  input  wire  [15:0]  mv_x, mv_y,
  input  wire          mv_valid,
  input  wire          frame_start,

  // ── Rasterizer input ─────────────────────────────────────
  input  wire  [10:0]  v0_x, v0_y, v1_x, v1_y, v2_x, v2_y,
  input  wire  [31:0]  c0, c1, c2, z0, z1, z2,
  input  wire          rast_start,

  // ── MVP Matrix load (optional) ───────────────────────────
  input  wire  [31:0]  mvp_m00, mvp_m01, mvp_m02, mvp_m03,
  input  wire  [31:0]  mvp_m10, mvp_m11, mvp_m12, mvp_m13,
  input  wire  [31:0]  mvp_m20, mvp_m21, mvp_m22, mvp_m23,
  input  wire  [31:0]  mvp_m30, mvp_m31, mvp_m32, mvp_m33,
  input  wire          mvp_load,

  // ── Frame output ─────────────────────────────────────────
  output wire  [TOKEN_WIDTH-1:0] frame_out,
  output wire                    frame_valid,
  output wire  [2:0]             frame_count,
  output wire                    mvu_ready_out,

  // ── Framebuffer write ────────────────────────────────────
  output wire  [31:0]  fb_color,
  output wire  [18:0]  fb_addr,
  output wire          fb_write,

  // ── Budget / Status ───────────────────────────────────────
  output wire  [7:0]   rt_load,
  output wire          budget_ok_out,
  output wire  [15:0]  sram_hits,
  output wire  [15:0]  sram_misses,

  // ── AXI4-Lite outputs ────────────────────────────────────
  output wire          axi_awready,
  output wire          axi_wready,
  output wire          axi_arready,
  output wire          axi_rvalid,
  output wire  [TOKEN_WIDTH-1:0] axi_rdata,

  // ── Bandwidth counters ────────────────────────────────────
  output wire  [15:0]  bw_instrmem,
  output wire  [15:0]  bw_bvhmem,
  output wire  [15:0]  bw_texmem,
  output wire  [15:0]  bw_framebuf
);

  // ── TMU ───────────────────────────────────────────────────
  wire [TAG_WIDTH-1:0]    tmu_in_tag;
  wire [TOKEN_WIDTH-1:0]  tmu_in_data;
  wire                    tmu_in_valid;
  wire                    tmu_in_ready;
  wire [TAG_WIDTH-1:0]    tmu_fire_tag;
  wire [TOKEN_WIDTH-1:0]  tmu_fire_data_a;
  wire [TOKEN_WIDTH-1:0]  tmu_fire_data_b;
  wire                    tmu_fire_valid;

  token_matching_unit #(
    .NUM_SLOTS(TMU_SLOTS), .TAG_WIDTH(TAG_WIDTH), .DATA_WIDTH(TOKEN_WIDTH)
  ) u_tmu (
    .clk(clk), .rst_n(rst_n),
    .in_tag(tmu_in_tag), .in_data(tmu_in_data),
    .in_valid(tmu_in_valid), .in_ready(tmu_in_ready),
    .fire_tag(tmu_fire_tag),
    .fire_data_a(tmu_fire_data_a), .fire_data_b(tmu_fire_data_b),
    .fire_valid(tmu_fire_valid), .occupancy()
  );

  // ── SHADER (con MVP) ─────────────────────────────────────
  wire [TOKEN_WIDTH-1:0]  shader_out;
  wire                    shader_valid;

  shader_cluster #(
    .NUM_CU(NUM_CU), .DATA_WIDTH(TOKEN_WIDTH), .NUM_WARPS(4)
  ) u_shaders (
    .clk(clk), .rst_n(rst_n),
    .data_in(tmu_fire_data_a), .data_in_b(tmu_fire_data_b),
    .in_valid(tmu_fire_valid),
    .mvp_m00(mvp_m00), .mvp_m01(mvp_m01), .mvp_m02(mvp_m02), .mvp_m03(mvp_m03),
    .mvp_m10(mvp_m10), .mvp_m11(mvp_m11), .mvp_m12(mvp_m12), .mvp_m13(mvp_m13),
    .mvp_m20(mvp_m20), .mvp_m21(mvp_m21), .mvp_m22(mvp_m22), .mvp_m23(mvp_m23),
    .mvp_m30(mvp_m30), .mvp_m31(mvp_m31), .mvp_m32(mvp_m32), .mvp_m33(mvp_m33),
    .mvp_load(mvp_load),
    .data_out(shader_out), .out_valid(shader_valid)
  );

  // ── RASTERIZADOR ─────────────────────────────────────────
  wire [TOKEN_WIDTH-1:0]  rast_token;
  wire                    rast_token_valid;
  wire                    rast_busy;

  triangle_rasterizer #(
    .DATA_WIDTH(TOKEN_WIDTH), .SCREEN_W(SCREEN_W), .SCREEN_H(SCREEN_H)
  ) u_rast (
    .clk(clk), .rst_n(rst_n),
    .v0_x(v0_x), .v0_y(v0_y),
    .v1_x(v1_x), .v1_y(v1_y),
    .v2_x(v2_x), .v2_y(v2_y),
    .c0(c0), .c1(c1), .c2(c2),
    .z0(z0), .z1(z1), .z2(z2),
    .start(rast_start), .busy(rast_busy),
    .token_out(rast_token), .token_valid(rast_token_valid),
    .token_ready(1'b1)
  );

  // ── TILE ARBITER ─────────────────────────────────────────
  wire [TOKEN_WIDTH-1:0]  tile_in    = rast_token_valid ? rast_token : shader_out;
  wire                    tile_valid = rast_token_valid | shader_valid;

  wire [31:0]  tile_color;
  wire [18:0]  tile_addr;
  wire         tile_write;
  wire         tile_ready;
  wire [15:0]  tile_written, tile_discarded;

  tile_arbiter #(
    .DATA_WIDTH(TOKEN_WIDTH), .SCREEN_W(SCREEN_W), .SCREEN_H(SCREEN_H)
  ) u_tile (
    .clk(clk), .rst_n(rst_n),
    .frag_in(tile_in), .frag_valid(tile_valid),
    .frag_ready(tile_ready),
    .pixel_color(tile_color), .pixel_addr(tile_addr),
    .pixel_write(tile_write),
    .fragments_written(tile_written),
    .fragments_discarded(tile_discarded)
  );

  // ── SRAM INTEGRADA (jerarquía completa) ──────────────────
  wire [TOKEN_WIDTH-1:0]  sram_a_rdata_w;
  wire [TOKEN_WIDTH-1:0]  sram_b_rdata_w;
  wire                    sram_a_ack_w;
  wire                    sram_b_ack_w;

  sram_integrated #(.DATA_WIDTH(TOKEN_WIDTH)) u_sram (
    .clk(clk), .rst_n(rst_n),
    .a_addr({13'b0, tile_addr}),
    .a_wdata(rast_token),
    .a_req(rast_token_valid),
    .a_wen(rast_token_valid),
    .a_rdata(sram_a_rdata_w),
    .a_ack(sram_a_ack_w),
    .b_addr({13'b0, tile_addr}),
    .b_wdata({{(TOKEN_WIDTH-32){1'b0}}, tile_color}),
    .b_req(tile_write),
    .b_wen(tile_write),
    .b_rdata(sram_b_rdata_w),
    .b_ack(sram_b_ack_w),
    .axi_awready(axi_awready),
    .axi_wready(axi_wready),
    .axi_arready(axi_arready),
    .axi_rvalid(axi_rvalid),
    .axi_rdata(axi_rdata),
    .hit_count(sram_hits),
    .miss_count(sram_misses),
    .conflict_o(),
    .bw_instrmem(bw_instrmem),
    .bw_bvhmem(bw_bvhmem),
    .bw_texmem(bw_texmem),
    .bw_framebuf(bw_framebuf)
  );

  // ── BUDGET CONTROLLER ─────────────────────────────────────
  wire budget_ok;
  wire rt_active = shader_valid & budget_ok;

  budget_controller #(
    .CLK_MHZ(TARGET_FREQ_SILICON), .RT_PERCENT(RT_PERCENT)
  ) u_budget (
    .clk(clk), .rst_n(rst_n),
    .frame_start(frame_start), .rt_active(rt_active),
    .budget_ok(budget_ok), .rt_load(rt_load)
  );

  // ── THREE TRACING (8 RT units) ────────────────────────────
  wire [TOKEN_WIDTH-1:0]  tt_out;
  wire                    tt_valid;

  three_tracing_unit #(
    .BVH_DEPTH(TT_BVH_DEPTH),
    .RAY_BUDGET(TT_RAY_BUDGET),
    .DATA_WIDTH(TOKEN_WIDTH),
    .NUM_RT_UNITS(TT_NUM_RT_UNITS)
  ) u_tt (
    .clk(clk), .rst_n(rst_n),
    .frag_in(shader_out), .in_valid(shader_valid),
    .budget_ok(budget_ok),
    .sram_ack(sram_b_ack_w),
    .frame_out(tt_out), .out_valid(tt_valid)
  );

  // ── MVU ───────────────────────────────────────────────────
  wire mvu_ready;

  mvu #(
    .REAL_FRAMES(MVU_REAL_FRAMES), .GEN_FRAMES(MVU_GEN_FRAMES),
    .DATA_WIDTH(TOKEN_WIDTH)
  ) u_mvu (
    .clk(clk), .rst_n(rst_n),
    .frame_in(tt_out), .in_valid(tt_valid),
    .mv_x(mv_x), .mv_y(mv_y), .mv_valid(mv_valid),
    .frame_out(frame_out), .frame_valid(frame_valid),
    .frame_count(frame_count), .mvu_ready(mvu_ready)
  );

  // ── ÁRBITRO ──────────────────────────────────────────────
  wire [NUM_ARB_PORTS-1:0] arb_req_w;
  wire [2*NUM_ARB_PORTS-1:0] arb_prio_flat;  // FIX: bus plano en lugar de array SV
  wire [NUM_ARB_PORTS-1:0] arb_grant_w;
  wire [TOKEN_WIDTH-1:0]   arb_out_w;
  wire                     arb_valid_w, arb_full_w;

  // FIX v2: concat único — Icarus rechaza índices literales sobre wire parametrizado
  // {zeros[15:4], slot3=0, tt, rast, tmu}
  assign arb_req_w = {{(NUM_ARB_PORTS-4){1'b0}}, 1'b0, tt_valid, rast_token_valid, tmu_fire_valid};

  genvar gi;
  generate
    for (gi = 0; gi < NUM_ARB_PORTS; gi = gi + 1) begin : arb_prio_gen
      // FIX: asignar en bus plano prio_flat[2*gi+1:2*gi]
      assign arb_prio_flat[2*gi+1:2*gi] = (gi == 2) ? 2'b11 :
                                           (gi == 1) ? 2'b10 :
                                           (gi == 0) ? 2'b01 : 2'b00;
    end
  endgenerate

  arbiter #(
    .NUM_PORTS(NUM_ARB_PORTS), .BUF_DEPTH(BYPASS_DEPTH),
    .DATA_WIDTH(TOKEN_WIDTH)
  ) u_arb (
    .clk(clk), .rst_n(rst_n),
    .req(arb_req_w),
    .data_in_0(tmu_fire_data_a),
    .data_in_1(rast_token),
    .data_in_2(tt_out),
    .data_in_3({TOKEN_WIDTH{1'b0}}),
    .data_in_4({TOKEN_WIDTH{1'b0}}),  .data_in_5({TOKEN_WIDTH{1'b0}}),
    .data_in_6({TOKEN_WIDTH{1'b0}}),  .data_in_7({TOKEN_WIDTH{1'b0}}),
    .data_in_8({TOKEN_WIDTH{1'b0}}),  .data_in_9({TOKEN_WIDTH{1'b0}}),
    .data_in_10({TOKEN_WIDTH{1'b0}}), .data_in_11({TOKEN_WIDTH{1'b0}}),
    .data_in_12({TOKEN_WIDTH{1'b0}}), .data_in_13({TOKEN_WIDTH{1'b0}}),
    .data_in_14({TOKEN_WIDTH{1'b0}}), .data_in_15({TOKEN_WIDTH{1'b0}}),
    .prio_in_flat(arb_prio_flat),  // FIX: conectar bus plano
    .grant(arb_grant_w), .data_out(arb_out_w),
    .data_valid(arb_valid_w), .buf_full(arb_full_w)
  );

  // ── Conexiones finales ────────────────────────────────────
  assign tmu_in_tag    = pcie_data_in[TAG_WIDTH-1:0];
  assign tmu_in_data   = pcie_data_in[TOKEN_WIDTH-1:0];
  assign tmu_in_valid  = pcie_valid;
  assign pcie_ready    = tmu_in_ready & mvu_ready;
  assign pcie_data_out = {{(256-TOKEN_WIDTH){1'b0}}, frame_out};

  assign fb_color      = tile_color;
  assign fb_addr       = tile_addr;
  assign fb_write      = tile_write;

  assign mvu_ready_out = mvu_ready;
  assign budget_ok_out = budget_ok;

endmodule

// Copyright (c) 2025 Nova Studios / Maximal Technology
// SPDX-License-Identifier: MIT