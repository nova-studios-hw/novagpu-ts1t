`timescale 1ns/1ps






















module fpga_top (
    input  wire        clk,       
    input  wire        rst_n,     

    
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,
    output wire        vga_hsync,
    output wire        vga_vsync,

    
    output wire [3:0]  led
);






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
wire pll_locked = rst_n;          

wire sys_rst = ~rst_n;            






localparam [10:0] V0X = 11'd320, V0Y = 11'd60;
localparam [10:0] V1X = 11'd120, V1Y = 11'd420;
localparam [10:0] V2X = 11'd520, V2Y = 11'd420;


localparam [31:0] C0 = 32'hFF0000FF;
localparam [31:0] C1 = 32'h00FF00FF;
localparam [31:0] C2 = 32'h0000FFFF;
localparam [31:0] Z_ZERO = 32'h0;


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


localparam [31:0] FP_ONE  = 32'h3F800000;
localparam [31:0] FP_ZERO = 32'h00000000;




wire [127:0] fb_color_wide;
wire [255:0] pcie_data_zero = 256'h0;  
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

    
    .pcie_data_in    (pcie_data_zero),
    .pcie_data_out   (),
    .pcie_valid      (1'b0),
    .pcie_ready      (),

    
    .mv_x            (16'h0),
    .mv_y            (16'h0),
    .mv_valid        (1'b0),
    .frame_start     (1'b0),

    
    .v0_x (V0X), .v0_y (V0Y),
    .v1_x (V1X), .v1_y (V1Y),
    .v2_x (V2X), .v2_y (V2Y),
    .c0   (C0),  .c1   (C1),  .c2 (C2),
    .z0   (Z_ZERO), .z1 (Z_ZERO), .z2 (Z_ZERO),
    .rast_start (rast_start_r),

    
    .mvp_m00(FP_ONE),  .mvp_m01(FP_ZERO), .mvp_m02(FP_ZERO), .mvp_m03(FP_ZERO),
    .mvp_m10(FP_ZERO), .mvp_m11(FP_ONE),  .mvp_m12(FP_ZERO), .mvp_m13(FP_ZERO),
    .mvp_m20(FP_ZERO), .mvp_m21(FP_ZERO), .mvp_m22(FP_ONE),  .mvp_m23(FP_ZERO),
    .mvp_m30(FP_ZERO), .mvp_m31(FP_ZERO), .mvp_m32(FP_ZERO), .mvp_m33(FP_ONE),
    .mvp_load (1'b1),

    
    .fb_color        (fb_color_w),
    .fb_addr         (fb_addr_w),
    .fb_write        (fb_write_w),

    
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
always @(posedge clk_pixel)
begin
    if (rast_done_w)
        $display("TOP VE rast_done_w @ %0t", $time);
end





localparam FB_SIZE = 640 * 480;   

(* ram_style = "block" *)
reg [11:0] framebuf [0:FB_SIZE-1];


always @(posedge clk_pixel) begin
    if (fb_write_w && (fb_addr_w < 19'd307200))
        framebuf[fb_addr_w] <= fb_color_w[11:0];
end






localparam HA = 640, HFP = 16,  HS = 96,  HBP = 48;   
localparam VA = 480, VFP = 10,  VS = 2,   VBP = 33;   
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


assign vga_hsync = ~((hcnt >= HA + HFP) && (hcnt < HA + HFP + HS));
assign vga_vsync = ~((vcnt >= VA + VFP) && (vcnt < VA + VFP + VS));



wire [18:0] rd_addr = vis ? ($unsigned(vcnt) * 19'd640 + $unsigned(hcnt)) : 19'd0;
reg  [11:0] px;

always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) px <= 12'd0;
    else        px <= framebuf[rd_addr];
end

assign vga_r = vis ? px[11:8] : 4'b0;
assign vga_g = vis ? px[7:4]  : 4'b0;
assign vga_b = vis ? px[3:0]  : 4'b0;




assign led[0] = pll_locked;
assign led[1] = frame_valid_w;
assign led[2] = rast_done_w;
assign led[3] = mvu_rdy_w;

endmodule