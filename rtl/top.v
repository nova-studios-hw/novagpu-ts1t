`timescale 1ns/1ps
// =============================================================================
// fpga_top.v  —  NovaGPU TS 1T  FPGA Top-Level REAL
// Nova Studios / Maximal Technology
//
// Target : Digilent Arty A7-100T  (xc7a100tcsg324-1)
// I/O    : 20 pines físicos  (< 210 disponibles)
//
// Jerarquía:
//   fpga_top          ← TOP-LEVEL (este archivo, único con pines externos)
//   └── novagpu_core  ← núcleo GPU (top.v renombrado)
//       ├── token_matching_unit
//       ├── shader_cluster
//       ├── budget_controller
//       ├── three_tracing_unit
//       ├── triangle_rasterizer
//       ├── tile_arbiter
//       ├── sram_integrated
//       └── mvu
//
// INSTRUCCIÓN A VIVADO: Set As Top → fpga_top
// =============================================================================

module fpga_top (
    input  wire        clk,       // E3 — 100 MHz onboard oscillator
    input  wire        rst_n,     // C2 — BTN0, activo bajo

    // VGA 12-bit  (Pmod JB = R/G, Pmod JC = B/sync)
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,
    output wire        vga_hsync,
    output wire        vga_vsync,

    // LEDs de estado  LD0-LD3
    output wire [3:0]  led
);

// ===========================================================================
// 1.  Divisor de clock RTL puro  100 MHz → 25 MHz  (÷4)
//     Sin IP externa — funciona directo en síntesis sin Clocking Wizard
//     25 MHz no es exactamente 25.175 MHz pero el timing VGA es tolerable
// ===========================================================================
reg [1:0] clk_div;
reg       clk_pixel_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        clk_div     <= 2'd0;
        clk_pixel_r <= 1'b0;
    end else begin
        if (clk_div == 2'd1) begin
            clk_div     <= 2'd0;
            clk_pixel_r <= ~clk_pixel_r;
        end else begin
            clk_div <= clk_div + 2'd1;
        end
    end
end

wire clk_pixel = clk_pixel_r;
wire pll_locked = rst_n;          // sin PLL real — locked = ~reset

wire sys_rst = ~rst_n;            // reset activo alto

// ===========================================================================
// 2.  Estímulos internos  —  sin pines externos
// ===========================================================================

// ── Triángulo fijo (no requiere host) ──────────────────────────────────────
localparam [10:0] V0X = 11'd320, V0Y = 11'd60;
localparam [10:0] V1X = 11'd120, V1Y = 11'd420;
localparam [10:0] V2X = 11'd520, V2Y = 11'd420;

// Colores R8G8B8A8: rojo, verde, azul
localparam [31:0] C0 = 32'hFF0000FF;
localparam [31:0] C1 = 32'h00FF00FF;
localparam [31:0] C2 = 32'h0000FFFF;
localparam [31:0] Z_ZERO = 32'h0;

// ── Pulso rast_start: dispara una vez al arrancar ──────────────────────────
reg [1:0] start_state;
reg       rast_start_r;

always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        start_state  <= 2'd0;
        rast_start_r <= 1'b0;
    end else begin
        case (start_state)
            2'd0: begin rast_start_r <= 1'b1; start_state <= 2'd1; end
            2'd1: begin rast_start_r <= 1'b0; start_state <= 2'd2; end
            default: rast_start_r <= 1'b0;
        endcase
    end
end

// ── MVP Identidad  (IEEE 754: 1.0 = 32'h3F800000) ─────────────────────────
localparam [31:0] FP_ONE  = 32'h3F800000;
localparam [31:0] FP_ZERO = 32'h00000000;

// ===========================================================================
// 3.  Instancia del núcleo GPU
// ===========================================================================
wire [127:0] fb_color_wide;
wire [255:0] pcie_data_zero = 256'h0;  // FIX: Vivado rejects >32-bit literals in port connections
wire [31:0]  fb_color_w;
wire [18:0]  fb_addr_w;
wire         fb_write_w;
wire         frame_valid_w;
wire         rast_done_w;
wire         mvu_rdy_w;

novagpu_core #(
    .DATA_WIDTH      (128),
    .TAG_WIDTH       (16),
    .TMU_SLOTS       (64),
    .MVU_REAL_FRAMES (2),
    .MVU_GEN_FRAMES  (4),
    .TARGET_FREQ_MHZ (100),
    .NUM_ARB_PORTS   (4),
    .TT_BVH_DEPTH    (8),
    .TT_RAY_BUDGET   (8),
    .TT_NUM_RT_UNITS (4),
    .RT_PERCENT      (25),
    .SCREEN_W        (640),
    .SCREEN_H        (480)
) u_gpu (
    .clk             (clk_pixel),
    .rst_n           (~sys_rst),

    // PCIe stub — idle
    .pcie_data_in    (pcie_data_zero),
    .pcie_data_out   (),
    .pcie_valid      (1'b0),
    .pcie_ready      (),

    // Motion vectors — nulos
    .mv_x            (16'h0),
    .mv_y            (16'h0),
    .mv_valid        (1'b0),
    .frame_start     (1'b0),

    // Triángulo fijo
    .v0_x (V0X), .v0_y (V0Y),
    .v1_x (V1X), .v1_y (V1Y),
    .v2_x (V2X), .v2_y (V2Y),
    .c0   (C0),  .c1   (C1),  .c2 (C2),
    .z0   (Z_ZERO), .z1 (Z_ZERO), .z2 (Z_ZERO),
    .rast_start (rast_start_r),

    // MVP identidad
    .mvp_m00(FP_ONE),  .mvp_m01(FP_ZERO), .mvp_m02(FP_ZERO), .mvp_m03(FP_ZERO),
    .mvp_m10(FP_ZERO), .mvp_m11(FP_ONE),  .mvp_m12(FP_ZERO), .mvp_m13(FP_ZERO),
    .mvp_m20(FP_ZERO), .mvp_m21(FP_ZERO), .mvp_m22(FP_ONE),  .mvp_m23(FP_ZERO),
    .mvp_m30(FP_ZERO), .mvp_m31(FP_ZERO), .mvp_m32(FP_ZERO), .mvp_m33(FP_ONE),
    .mvp_load (1'b1),

    // Framebuffer write
    .fb_color        (fb_color_w),
    .fb_addr         (fb_addr_w),
    .fb_write        (fb_write_w),

    // Outputs no usados en demo (tied off)
    .frame_out       (),
    .frame_valid     (frame_valid_w),
    .frame_count     (),
    .mvu_ready_out   (mvu_rdy_w),
    .rt_load         (),
    .budget_ok_out   (),
    .sram_hits       (),
    .sram_misses     (),
    .axi_awready     (),
    .axi_wready      (),
    .axi_arready     (),
    .axi_rvalid      (),
    .axi_rdata       (),
    .bw_instrmem     (),
    .bw_bvhmem       (),
    .bw_texmem       (),
    .bw_framebuf     (),
    .rast_pixels_emitted (),
    .rast_pixels_skipped (),
    .rast_frame_done     (rast_done_w)
);

// ===========================================================================
// 4.  Framebuffer en BRAM  (640×480 × 12-bit)
//     Puerto A: escritura GPU
//     Puerto B: lectura VGA
// ===========================================================================
localparam FB_SIZE = 640 * 480;   // 307200

(* ram_style = "block" *)
reg [11:0] framebuf [0:FB_SIZE-1];

// Escritura desde GPU — toma bits [11:0] del fb_color
always @(posedge clk_pixel) begin
    if (fb_write_w && (fb_addr_w < 19'd307200))
        framebuf[fb_addr_w] <= fb_color_w[11:0];
end

// ===========================================================================
// 5.  VGA Controller  640×480 @ 60 Hz
//     Pixel clock nominal: 25.175 MHz
// ===========================================================================
// Timing VESA
localparam HA = 640, HFP = 16,  HS = 96,  HBP = 48;   // H total = 800
localparam VA = 480, VFP = 10,  VS = 2,   VBP = 33;   // V total = 525
localparam HT = HA + HFP + HS + HBP;
localparam VT = VA + VFP + VS + VBP;

reg [9:0] hcnt, vcnt;

always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        hcnt <= 10'd0; vcnt <= 10'd0;
    end else begin
        if (hcnt == HT - 1) begin
            hcnt <= 10'd0;
            vcnt <= (vcnt == VT - 1) ? 10'd0 : vcnt + 10'd1;
        end else
            hcnt <= hcnt + 10'd1;
    end
end

wire h_vis = (hcnt < HA);
wire v_vis = (vcnt < VA);
wire vis   = h_vis & v_vis;

// Sync pulsos (negativos)
assign vga_hsync = ~((hcnt >= HA + HFP) && (hcnt < HA + HFP + HS));
assign vga_vsync = ~((vcnt >= VA + VFP) && (vcnt < VA + VFP + VS));

// Lectura framebuffer — pipeline de 1 ciclo
// FIX: explicit $unsigned cast avoids Vivado inferring signed 19x19 multiplier
wire [18:0] rd_addr = vis ? ($unsigned(vcnt) * 19'd640 + $unsigned(hcnt)) : 19'd0;
reg  [11:0] px;

always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) px <= 12'd0;
    else        px <= framebuf[rd_addr];
end

assign vga_r = vis ? px[11:8] : 4'b0;
assign vga_g = vis ? px[7:4]  : 4'b0;
assign vga_b = vis ? px[3:0]  : 4'b0;

// ===========================================================================
// 6.  LEDs
// ===========================================================================
assign led[0] = pll_locked;
assign led[1] = frame_valid_w;
assign led[2] = rast_done_w;
assign led[3] = mvu_rdy_w;

endmodule