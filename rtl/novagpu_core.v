`timescale 1ns/1ps
// =============================================================================
// novagpu_core.v  —  NovaGPU TS 1T  Núcleo interno (SIN puertos externos)
// Nova Studios / Maximal Technology
//
// Este módulo es el top.v original RENOMBRADO a novagpu_core.
// NUNCA debe ser el top-level de Vivado.
// El top-level real es fpga_top.v
// =============================================================================

module novagpu_core #(
    parameter DATA_WIDTH      = 128,
    parameter TAG_WIDTH       = 16,
    parameter TMU_SLOTS       = 64,
    parameter MVU_REAL_FRAMES = 2,
    parameter MVU_GEN_FRAMES  = 4,
    parameter TARGET_FREQ_MHZ = 100,
    parameter NUM_ARB_PORTS   = 4,
    parameter TT_BVH_DEPTH    = 8,
    parameter TT_RAY_BUDGET   = 8,
    parameter TT_NUM_RT_UNITS = 4,
    parameter RT_PERCENT      = 25,
    parameter SCREEN_W        = 640,
    parameter SCREEN_H        = 480
)(
    input  wire        clk,
    input  wire        rst_n,

    // PCIe / Data Interface
    input  wire [255:0] pcie_data_in,
    output wire [255:0] pcie_data_out,
    input  wire         pcie_valid,
    output wire         pcie_ready,

    // Motion Vectors
    input  wire [15:0]  mv_x, mv_y,
    input  wire         mv_valid,
    input  wire         frame_start,

    // Rasterizer input
    input  wire [10:0]  v0_x, v0_y, v1_x, v1_y, v2_x, v2_y,
    input  wire [31:0]  c0, c1, c2, z0, z1, z2,
    input  wire         rast_start,

    // MVP Matrix
    input  wire [31:0]  mvp_m00, mvp_m01, mvp_m02, mvp_m03,
    input  wire [31:0]  mvp_m10, mvp_m11, mvp_m12, mvp_m13,
    input  wire [31:0]  mvp_m20, mvp_m21, mvp_m22, mvp_m23,
    input  wire [31:0]  mvp_m30, mvp_m31, mvp_m32, mvp_m33,
    input  wire         mvp_load,

    // Frame output
    output wire [DATA_WIDTH-1:0] frame_out,
    output wire                   frame_valid,
    output wire [2:0]             frame_count,
    output wire                   mvu_ready_out,

    // Framebuffer write
    output wire [31:0]  fb_color,
    output wire [18:0]  fb_addr,
    output wire         fb_write,

    // Status
    output wire [7:0]   rt_load,
    output wire         budget_ok_out,
    output wire [15:0]  sram_hits,
    output wire [15:0]  sram_misses,

    // AXI4-Lite
    output wire         axi_awready,
    output wire         axi_wready,
    output wire         axi_arready,
    output wire         axi_rvalid,
    output wire [DATA_WIDTH-1:0] axi_rdata,

    // Bandwidth
    output wire [15:0]  bw_instrmem,
    output wire [15:0]  bw_bvhmem,
    output wire [15:0]  bw_texmem,
    output wire [15:0]  bw_framebuf,

    // Rast stats
    output wire [19:0]  rast_pixels_emitted,
    output wire [19:0]  rast_pixels_skipped,
    output wire         rast_frame_done
);

    // ── TMU ───────────────────────────────────────────────────
    wire [TAG_WIDTH-1:0]   tmu_in_tag   = pcie_data_in[TAG_WIDTH-1:0];
    wire [DATA_WIDTH-1:0]  tmu_in_data  = pcie_data_in[TAG_WIDTH+DATA_WIDTH-1:TAG_WIDTH];
    wire                   tmu_in_valid = pcie_valid;
    wire                   tmu_in_ready;
    wire [TAG_WIDTH-1:0]   tmu_fire_tag;
    wire [DATA_WIDTH-1:0]  tmu_fire_data_a, tmu_fire_data_b;
    wire                   tmu_fire_valid;

    token_matching_unit #(
        .NUM_SLOTS(TMU_SLOTS), .TAG_WIDTH(TAG_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) u_tmu (
        .clk(clk), .rst_n(rst_n),
        .in_tag(tmu_in_tag), .in_data(tmu_in_data),
        .in_valid(tmu_in_valid), .in_ready(tmu_in_ready),
        .fire_tag(tmu_fire_tag),
        .fire_data_a(tmu_fire_data_a), .fire_data_b(tmu_fire_data_b),
        .fire_valid(tmu_fire_valid), .occupancy()
    );

    // ── Shader Cluster ────────────────────────────────────────
    wire [DATA_WIDTH-1:0] shader_out;
    wire                  shader_valid;
    wire [15:0]           shader_exec_count;

    shader_cluster #(
        .NUM_CU(4), .DATA_WIDTH(DATA_WIDTH), .NUM_WARPS(4)
    ) u_shader (
        .clk(clk), .rst_n(rst_n),
        .data_in(tmu_fire_data_a), .data_in_b(tmu_fire_data_b),
        .in_valid(tmu_fire_valid),
        .mvp_m00(mvp_m00), .mvp_m01(mvp_m01),
        .mvp_m02(mvp_m02), .mvp_m03(mvp_m03),
        .mvp_m10(mvp_m10), .mvp_m11(mvp_m11),
        .mvp_m12(mvp_m12), .mvp_m13(mvp_m13),
        .mvp_m20(mvp_m20), .mvp_m21(mvp_m21),
        .mvp_m22(mvp_m22), .mvp_m23(mvp_m23),
        .mvp_m30(mvp_m30), .mvp_m31(mvp_m31),
        .mvp_m32(mvp_m32), .mvp_m33(mvp_m33),
        .mvp_load(mvp_load),
        .data_out(shader_out), .out_valid(shader_valid),
        .exec_count_out(shader_exec_count)
    );

    // ── Budget Controller ─────────────────────────────────────
    wire budget_ok;
    wire rt_active = shader_valid & budget_ok;

    budget_controller #(
        .CLK_MHZ(TARGET_FREQ_MHZ), .RT_PERCENT(RT_PERCENT)
    ) u_budget (
        .clk(clk), .rst_n(rst_n),
        .frame_start(frame_start), .rt_active(rt_active),
        .budget_ok(budget_ok), .rt_load(rt_load)
    );

    // ── Three Tracing Unit ────────────────────────────────────
    wire [DATA_WIDTH-1:0] tt_out;
    wire                  tt_valid;

    three_tracing_unit #(
        .BVH_DEPTH(TT_BVH_DEPTH), .RAY_BUDGET(TT_RAY_BUDGET),
        .DATA_WIDTH(DATA_WIDTH), .NUM_RT_UNITS(TT_NUM_RT_UNITS)
    ) u_tt (
        .clk(clk), .rst_n(rst_n),
        .frag_in(shader_out), .in_valid(shader_valid),
        .budget_ok(budget_ok), .sram_ack(1'b1),
        .frame_out(tt_out), .out_valid(tt_valid)
    );

    // ── Triangle Rasterizer ───────────────────────────────────
    wire [DATA_WIDTH-1:0] rast_token;
    wire                  rast_token_valid, rast_busy;

    triangle_rasterizer #(
        .DATA_WIDTH(DATA_WIDTH), .SCREEN_W(SCREEN_W), .SCREEN_H(SCREEN_H)
    ) u_rast (
        .clk(clk), .rst_n(rst_n),
        .v0_x(v0_x), .v0_y(v0_y),
        .v1_x(v1_x), .v1_y(v1_y),
        .v2_x(v2_x), .v2_y(v2_y),
        .c0(c0), .c1(c1), .c2(c2),
        .z0(z0), .z1(z1), .z2(z2),
        .start(rast_start), .busy(rast_busy),
        .token_out(rast_token), .token_valid(rast_token_valid),
        .token_ready(1'b1),
        .pixels_emitted(rast_pixels_emitted),
        .pixels_skipped(rast_pixels_skipped),
        .frame_done(rast_frame_done)
    );

    // ── Tile Arbiter ──────────────────────────────────────────
    wire [DATA_WIDTH-1:0] tile_in    = rast_token_valid ? rast_token : tt_out;
    wire                  tile_valid = rast_token_valid | tt_valid;
    wire [31:0]  tile_color;
    wire [18:0]  tile_addr;
    wire         tile_write;
    wire         tile_ready;
    wire [15:0]  tile_written, tile_discarded;

    tile_arbiter #(
        .DATA_WIDTH(DATA_WIDTH), .SCREEN_W(SCREEN_W), .SCREEN_H(SCREEN_H)
    ) u_tile (
        .clk(clk), .rst_n(rst_n),
        .frag_in(tile_in), .frag_valid(tile_valid),
        .frag_ready(tile_ready),
        .pixel_color(tile_color), .pixel_addr(tile_addr),
        .pixel_write(tile_write),
        .fragments_written(tile_written),
        .fragments_discarded(tile_discarded)
    );

    // ── SRAM Integrada ────────────────────────────────────────
    wire [DATA_WIDTH-1:0] sram_a_rdata, sram_b_rdata;
    wire                  sram_a_ack, sram_b_ack;

sram_integrated #(.DATA_WIDTH(DATA_WIDTH)) u_sram (
    .clk(clk),
    .rst_n(rst_n),

    .a_addr({13'b0, tile_addr}),
    .a_wdata({{(DATA_WIDTH-32){1'b0}}, tile_color}),
    .a_req(tile_write),
    .a_wen(tile_write),
    .a_rdata(sram_a_rdata),
    .a_ack(sram_a_ack),

    .b_addr({13'b0, tile_addr}),
    .b_req(tile_write),
    .b_rdata(sram_b_rdata),
    .b_ack(sram_b_ack),

    .axi_awready(axi_awready),
    .axi_wready(axi_wready),
    .axi_arready(axi_arready),
    .axi_rvalid(axi_rvalid),
    .axi_rdata(axi_rdata),

    .hit_count(sram_hits),
    .miss_count(sram_misses),
    .conflict_o(),

    .bw_bvhmem(bw_bvhmem),
    .bw_framebuf(bw_framebuf)
);

    // ── MVU ───────────────────────────────────────────────────
    wire mvu_ready;

    mvu #(
        .REAL_FRAMES(MVU_REAL_FRAMES), .GEN_FRAMES(MVU_GEN_FRAMES),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_mvu (
        .clk(clk), .rst_n(rst_n),
        .frame_in(tt_out), .in_valid(tt_valid),
        .mv_x(mv_x), .mv_y(mv_y), .mv_valid(mv_valid),
        .frame_out(frame_out), .frame_valid(frame_valid),
        .frame_count(frame_count), .mvu_ready(mvu_ready)
    );

    // ── Salidas ───────────────────────────────────────────────
    assign pcie_ready    = tmu_in_ready & mvu_ready;
    assign pcie_data_out = {{(256-DATA_WIDTH){1'b0}}, frame_out};
    assign fb_color      = tile_color;
    assign fb_addr       = tile_addr;
    assign fb_write      = tile_write;
    assign mvu_ready_out = mvu_ready;
    assign budget_ok_out = budget_ok;
    assign bw_instrmem   = 16'h0;  // no submodule drives this — tied to 0
    assign bw_texmem     = 16'h0;  // no submodule drives this — tied to 0

endmodule