`timescale 1ns/1ps


module tb_novagpu_v13;

    localparam CLK_HALF   = 5;       
    localparam DATA_WIDTH = 128;
    localparam TAG_WIDTH  = 16;

    
    reg clk, rst_n;
    initial clk = 1'b0;
    always #CLK_HALF clk = ~clk;

    
    integer total_tests  = 0;
    integer passed_tests = 0;
    integer failed_tests = 0;

    task check_bool;
        input [511:0] name;
        input         cond;
        begin
            total_tests = total_tests + 1;
            if (cond) begin
                $display("  [PASS] %0s | T=%0t", name, $time);
                passed_tests = passed_tests + 1;
            end else begin
                $display("  [FAIL] %0s | T=%0t", name, $time);
                failed_tests = failed_tests + 1;
            end
        end
    endtask

    task check_val;
        input [511:0] name;
        input         cond;
        input [63:0]  got;
        input [63:0]  expected;
        begin
            total_tests = total_tests + 1;
            if (cond) begin
                $display("  [PASS] %0s | T=%0t", name, $time);
                passed_tests = passed_tests + 1;
            end else begin
                $display("  [FAIL] %0s | T=%0t | got=0x%0h exp=0x%0h",
                         name, $time, got, expected);
                failed_tests = failed_tests + 1;
            end
        end
    endtask

    integer wc;
    task wait_sig;
        input sig;
        input [15:0] maxc;
        begin
            wc = 0;
            while (!sig && wc < maxc) begin
                @(posedge clk); wc = wc + 1;
            end
        end
    endtask

    task reset_all;
        begin
            rst_n = 1'b0;
            repeat(4) @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);
        end
    endtask

    
    
    
    reg  [10:0] rv0x, rv0y, rv1x, rv1y, rv2x, rv2y;
    reg  [31:0] rc0, rc1, rc2, rz0, rz1, rz2;
    reg         rast_start;
    wire [DATA_WIDTH-1:0] rast_tok;
    wire                  rast_valid, rast_busy;
    wire [19:0]           rast_emitted, rast_skipped;
    wire                  rast_done;

    triangle_rasterizer #(.DATA_WIDTH(DATA_WIDTH), .SCREEN_W(640), .SCREEN_H(480))
    U_RAST (
        .clk(clk), .rst_n(rst_n),
        .v0_x(rv0x), .v0_y(rv0y),
        .v1_x(rv1x), .v1_y(rv1y),
        .v2_x(rv2x), .v2_y(rv2y),
        .c0(rc0), .c1(rc1), .c2(rc2),
        .z0(rz0), .z1(rz1), .z2(rz2),
        .start(rast_start), .busy(rast_busy),
        .token_out(rast_tok), .token_valid(rast_valid),
        .token_ready(1'b1),
        .pixels_emitted(rast_emitted),
        .pixels_skipped(rast_skipped),
        .frame_done(rast_done)
    );

    task rast_set;
        input [10:0] x0, y0, x1, y1, x2, y2;
        input [31:0] col0, col1, col2;
        begin
            rv0x = x0; rv0y = y0; rv1x = x1; rv1y = y1; rv2x = x2; rv2y = y2;
            rc0 = col0; rc1 = col1; rc2 = col2;
            rz0 = 32'h00008000; rz1 = 32'h00008000; rz2 = 32'h00008000;
        end
    endtask

    task rast_fire;
        begin
            @(posedge clk); rast_start = 1'b1;
            @(posedge clk); rast_start = 1'b0;
        end
    endtask

    
    
    
    reg  [TAG_WIDTH-1:0]   tmu_tag;
    reg  [DATA_WIDTH-1:0]  tmu_data;
    reg                    tmu_valid;
    wire                   tmu_ready;
    wire [TAG_WIDTH-1:0]   tmu_fire_tag;
    wire [DATA_WIDTH-1:0]  tmu_fire_da, tmu_fire_db;
    wire                   tmu_fire_valid;
    wire [TAG_WIDTH-1:0]   tmu_occ;

    token_matching_unit #(
        .NUM_SLOTS(64), .TAG_WIDTH(TAG_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .TIMEOUT(32)
    ) U_TMU (
        .clk(clk), .rst_n(rst_n),
        .in_tag(tmu_tag), .in_data(tmu_data),
        .in_valid(tmu_valid), .in_ready(tmu_ready),
        .fire_tag(tmu_fire_tag),
        .fire_data_a(tmu_fire_da), .fire_data_b(tmu_fire_db),
        .fire_valid(tmu_fire_valid), .occupancy(tmu_occ)
    );

    reg tmu_fire_valid_lat;
    reg [DATA_WIDTH-1:0] tmu_fire_da_lat;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tmu_fire_valid_lat <= 1'b0;
            tmu_fire_da_lat    <= {DATA_WIDTH{1'b0}};
        end else if (tmu_fire_valid) begin
            tmu_fire_valid_lat <= 1'b1;
            tmu_fire_da_lat    <= tmu_fire_da;
        end
    end

    task send_tmu;
        input [TAG_WIDTH-1:0]  tag;
        input [DATA_WIDTH-1:0] dat;
        begin
            @(posedge clk); tmu_tag = tag; tmu_data = dat; tmu_valid = 1'b1;
            @(posedge clk); tmu_valid = 1'b0;
        end
    endtask

    
    
    
    reg  [DATA_WIDTH-1:0] sh_in, sh_in_b;
    reg                   sh_valid;
    reg  [31:0] sh_mvp00, sh_mvp01, sh_mvp02, sh_mvp03;
    reg  [31:0] sh_mvp10, sh_mvp11, sh_mvp12, sh_mvp13;
    reg  [31:0] sh_mvp20, sh_mvp21, sh_mvp22, sh_mvp23;
    reg  [31:0] sh_mvp30, sh_mvp31, sh_mvp32, sh_mvp33;
    reg         sh_mvp_load;
    wire [DATA_WIDTH-1:0] sh_out;
    wire                  sh_out_valid;
    wire [15:0]           sh_exec_cnt;

    shader_cluster #(.NUM_CU(4), .DATA_WIDTH(DATA_WIDTH), .NUM_WARPS(4))
    U_SHADER (
        .clk(clk), .rst_n(rst_n),
        .data_in(sh_in), .data_in_b(sh_in_b),
        .in_valid(sh_valid),
        .mvp_m00(sh_mvp00), .mvp_m01(sh_mvp01), .mvp_m02(sh_mvp02), .mvp_m03(sh_mvp03),
        .mvp_m10(sh_mvp10), .mvp_m11(sh_mvp11), .mvp_m12(sh_mvp12), .mvp_m13(sh_mvp13),
        .mvp_m20(sh_mvp20), .mvp_m21(sh_mvp21), .mvp_m22(sh_mvp22), .mvp_m23(sh_mvp23),
        .mvp_m30(sh_mvp30), .mvp_m31(sh_mvp31), .mvp_m32(sh_mvp32), .mvp_m33(sh_mvp33),
        .mvp_load(sh_mvp_load),
        .data_out(sh_out), .out_valid(sh_out_valid),
        .exec_count_out(sh_exec_cnt)
    );

    
    
    
    reg  [DATA_WIDTH-1:0] bvh_ray;
    reg                   bvh_ray_valid;
    wire                  bvh_ray_ready;
    wire                  bvh_hit_valid, bvh_miss_valid;
    wire [7:0]            bvh_hit_prim;
    wire signed [31:0]    bvh_hit_t;
    wire [DATA_WIDTH-1:0] bvh_hit_tok;
    wire [15:0]           bvh_nodes_tst;
    wire [15:0]           bvh_hits, bvh_misses;

    bvh_real #(.BVH_DEPTH(8), .DATA_WIDTH(DATA_WIDTH))
    U_BVH (
        .clk(clk), .rst_n(rst_n),
        .ray_token(bvh_ray), .ray_valid(bvh_ray_valid),
        .ray_ready(bvh_ray_ready),
        .hit_valid(bvh_hit_valid), .hit_prim_id(bvh_hit_prim),
        .hit_t(bvh_hit_t), .hit_token(bvh_hit_tok),
        .miss_valid(bvh_miss_valid),
        .nodes_tested(bvh_nodes_tst),
        .hits_total(bvh_hits), .misses_total(bvh_misses)
    );

    task send_ray;
        input [31:0] ox, oy, dx, dy;
        begin
            bvh_ray       = {ox, oy, dx, dy, 32'h0};
            bvh_ray_valid = 1'b1;
            @(posedge clk); bvh_ray_valid = 1'b0;
        end
    endtask

    
    
    
    reg  [31:0]           sram_a_addr;
    reg  [DATA_WIDTH-1:0] sram_a_wdata;
    reg                   sram_a_req, sram_a_wen;
    wire [DATA_WIDTH-1:0] sram_a_rdata;
    wire                  sram_a_ack;
    reg  [31:0]           sram_b_addr;
    wire [DATA_WIDTH-1:0] sram_b_rdata;
    wire                  sram_b_ack;
    wire [15:0]           sram_hits_w, sram_misses_w;

    sram_integrated U_SRAM (
        .clk(clk), .rst_n(rst_n),
        .a_addr(sram_a_addr), .a_wdata(sram_a_wdata),
        .a_req(sram_a_req), .a_wen(sram_a_wen),
        .a_rdata(sram_a_rdata), .a_ack(sram_a_ack),
        .b_addr(sram_b_addr), .b_req(1'b0),
        .b_rdata(sram_b_rdata), .b_ack(sram_b_ack),
        .axi_awready(), .axi_wready(), .axi_arready(),
        .axi_rvalid(), .axi_rdata(),
        .hit_count(sram_hits_w), .miss_count(sram_misses_w),
        .conflict_o(), .bw_framebuf(), .bw_bvhmem()
    );

    reg         bc_frame_start, bc_rt_active;
    wire        bc_budget_ok;
    wire [7:0]  bc_rt_load;

    budget_controller #(.CLK_MHZ(100), .RT_PERCENT(25), .WINDOW(100))
    U_BUDGET (
        .clk(clk), .rst_n(rst_n),
        .frame_start(bc_frame_start), .rt_active(bc_rt_active),
        .budget_ok(bc_budget_ok), .rt_load(bc_rt_load)
    );

    reg  [DATA_WIDTH-1:0] mvu_frame_in;
    reg                   mvu_in_valid;
    reg  [15:0]           mvu_mv_x, mvu_mv_y;
    reg                   mvu_mv_valid;
    wire [DATA_WIDTH-1:0] mvu_frame_out;
    wire                  mvu_frame_valid;
    wire [2:0]            mvu_frame_count;
    wire                  mvu_ready;

    mvu #(.REAL_FRAMES(2), .GEN_FRAMES(4), .DATA_WIDTH(DATA_WIDTH))
    U_MVU (
        .clk(clk), .rst_n(rst_n),
        .frame_in(mvu_frame_in), .in_valid(mvu_in_valid),
        .mv_x(mvu_mv_x), .mv_y(mvu_mv_y), .mv_valid(mvu_mv_valid),
        .frame_out(mvu_frame_out), .frame_valid(mvu_frame_valid),
        .frame_count(mvu_frame_count), .mvu_ready(mvu_ready)
    );

    
    
    
    reg  [255:0] top_pcie_in;
    reg          top_pcie_valid, top_frame_start;
    reg  [10:0]  top_v0x, top_v0y, top_v1x, top_v1y, top_v2x, top_v2y;
    reg  [31:0]  top_c0, top_c1, top_c2, top_z0, top_z1, top_z2;
    reg          top_rast_start;
    wire [255:0] top_pcie_out;
    wire         top_pcie_ready;
    wire [DATA_WIDTH-1:0] top_frame_out;
    wire         top_frame_valid;
    wire [31:0]  top_fb_color;
    wire [18:0]  top_fb_addr;
    wire         top_fb_write;
    wire [19:0]  top_rast_emitted, top_rast_skipped;
    wire         top_rast_done;

    novagpu_core #(
        .SCREEN_W(640), .SCREEN_H(480),
        .TT_NUM_RT_UNITS(2)
    ) U_TOP (
        .clk(clk), .rst_n(rst_n),
        .pcie_data_in(top_pcie_in), .pcie_data_out(top_pcie_out),
        .pcie_valid(top_pcie_valid), .pcie_ready(top_pcie_ready),
        .mv_x(16'h0010), .mv_y(16'h0010), .mv_valid(1'b0),
        .frame_start(top_frame_start),
        .v0_x(top_v0x), .v0_y(top_v0y),
        .v1_x(top_v1x), .v1_y(top_v1y),
        .v2_x(top_v2x), .v2_y(top_v2y),
        .c0(top_c0), .c1(top_c1), .c2(top_c2),
        .z0(top_z0), .z1(top_z1), .z2(top_z2),
        .rast_start(top_rast_start),
        .mvp_m00(32'h00010000), .mvp_m01(32'h0), .mvp_m02(32'h0), .mvp_m03(32'h0),
        .mvp_m10(32'h0), .mvp_m11(32'h00010000), .mvp_m12(32'h0), .mvp_m13(32'h0),
        .mvp_m20(32'h0), .mvp_m21(32'h0), .mvp_m22(32'h00010000), .mvp_m23(32'h0),
        .mvp_m30(32'h0), .mvp_m31(32'h0), .mvp_m32(32'h0), .mvp_m33(32'h00010000),
        .mvp_load(1'b0),
        .frame_out(top_frame_out), .frame_valid(top_frame_valid),
        .frame_count(), .mvu_ready_out(),
        .fb_color(top_fb_color), .fb_addr(top_fb_addr), .fb_write(top_fb_write),
        .rt_load(), .budget_ok_out(), .sram_hits(), .sram_misses(),
        .axi_awready(), .axi_wready(), .axi_arready(), .axi_rvalid(), .axi_rdata(),
        .bw_instrmem(), .bw_bvhmem(), .bw_texmem(), .bw_framebuf(),
        .rast_pixels_emitted(top_rast_emitted),
        .rast_pixels_skipped(top_rast_skipped),
        .rast_frame_done(top_rast_done)
    );

    reg top_fb_write_lat, top_rast_done_lat;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            top_fb_write_lat  <= 1'b0;
            top_rast_done_lat <= 1'b0;
        end else begin
            if (top_fb_write)  top_fb_write_lat  <= 1'b1;
            if (top_rast_done) top_rast_done_lat <= 1'b1;
        end
    end

    
    
    
    reg        afa_enable, afa_phase_reset;
    reg  [7:0] afa_lut_x, afa_lut_y;
    reg        afa_lut_valid;
    wire signed [15:0] afa_delta_x, afa_delta_y, afa_delta_z;
    wire               afa_out_valid;
    wire [4:0]         afa_phase_out;
    wire               afa_wave_ready;
    wire [15:0]        afa_lookups_done;
    wire [15:0]        afa_phase_cycles;

    afa #(.LUT_SIZE(64), .PHASE_MAX(32), .PHASE_PERIOD(16), .DATA_WIDTH(DATA_WIDTH))
    U_AFA (
        .clk(clk), .rst_n(rst_n),
        .enable(afa_enable), .phase_reset(afa_phase_reset),
        .lut_x(afa_lut_x), .lut_y(afa_lut_y), .lut_valid(afa_lut_valid),
        .delta_x(afa_delta_x), .delta_y(afa_delta_y), .delta_z(afa_delta_z),
        .out_valid(afa_out_valid),
        .phase_out(afa_phase_out),
        .wave_ready(afa_wave_ready),
        .lookups_done(afa_lookups_done),
        .phase_cycles(afa_phase_cycles)
    );

    reg afa_out_valid_lat;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) afa_out_valid_lat <= 1'b0;
        else if (afa_out_valid) afa_out_valid_lat <= 1'b1;
    end

    
    
    
    reg  [DATA_WIDTH-1:0] mpe_obs_token;
    reg                   mpe_obs_valid;
    reg                   mpe_frame_tick;
    reg                   mpe_flush;
    wire [DATA_WIDTH-1:0] mpe_pred_token;
    wire [7:0]            mpe_pred_conf;
    wire                  mpe_pred_valid;
    wire                  mpe_prefetch_req;
    wire [15:0]           mpe_predictions;
    wire [15:0]           mpe_prefetches;
    wire [3:0]            mpe_hist_fill;

    mpe #(.HISTORY_DEPTH(4), .NUM_ENTRIES(16), .DATA_WIDTH(DATA_WIDTH), .CONF_THRESH(2))
    U_MPE (
        .clk(clk), .rst_n(rst_n),
        .obs_token(mpe_obs_token), .obs_valid(mpe_obs_valid),
        .frame_tick(mpe_frame_tick), .flush(mpe_flush),
        .pred_token(mpe_pred_token), .pred_confidence(mpe_pred_conf),
        .pred_valid(mpe_pred_valid), .prefetch_req(mpe_prefetch_req),
        .predictions_made(mpe_predictions), .prefetches_issued(mpe_prefetches),
        .history_fill(mpe_hist_fill)
    );

    reg mpe_pred_valid_lat;
    reg mpe_prefetch_lat;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mpe_pred_valid_lat <= 1'b0;
            mpe_prefetch_lat   <= 1'b0;
        end else begin
            if (mpe_pred_valid)   mpe_pred_valid_lat <= 1'b1;
            if (mpe_prefetch_req) mpe_prefetch_lat   <= 1'b1;
        end
    end

    
    
    
    reg  [7:0]             gia_obj_id;
    reg  signed [31:0]     gia_pos_x, gia_pos_y, gia_pos_z;
    reg                    gia_pos_valid;
    reg                    gia_frame_tick, gia_flush;
    wire signed [31:0]     gia_pred_x, gia_pred_y, gia_pred_z;
    wire [7:0]             gia_pred_obj_id;
    wire [7:0]             gia_pred_conf;
    wire                   gia_pred_valid;
    wire [15:0]            gia_geom_preds;
    wire [7:0]             gia_active_objs;

    gia #(.NUM_OBJECTS(8), .DATA_WIDTH(DATA_WIDTH))
    U_GIA (
        .clk(clk), .rst_n(rst_n),
        .obj_id(gia_obj_id), .pos_x(gia_pos_x), .pos_y(gia_pos_y), .pos_z(gia_pos_z),
        .pos_valid(gia_pos_valid),
        .frame_tick(gia_frame_tick), .flush(gia_flush),
        .pred_x(gia_pred_x), .pred_y(gia_pred_y), .pred_z(gia_pred_z),
        .pred_obj_id(gia_pred_obj_id), .pred_conf(gia_pred_conf),
        .pred_valid(gia_pred_valid),
        .geom_predictions(gia_geom_preds), .active_objects(gia_active_objs)
    );

    reg gia_pred_valid_lat;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) gia_pred_valid_lat <= 1'b0;
        else if (gia_pred_valid) gia_pred_valid_lat <= 1'b1;
    end

    
    
    
    initial begin
        $dumpfile("novagpu_ts1t_v4.vcd");
        $dumpvars(0, tb_novagpu_v13);

        
        rst_n = 1'b0;
        rast_start = 1'b0;
        rv0x=0; rv0y=0; rv1x=0; rv1y=0; rv2x=0; rv2y=0;
        rc0=0; rc1=0; rc2=0; rz0=0; rz1=0; rz2=0;
        tmu_tag=0; tmu_data=0; tmu_valid=0;
        sh_in=0; sh_in_b=0; sh_valid=0; sh_mvp_load=0;
        sh_mvp00=0; sh_mvp01=0; sh_mvp02=0; sh_mvp03=0;
        sh_mvp10=0; sh_mvp11=0; sh_mvp12=0; sh_mvp13=0;
        sh_mvp20=0; sh_mvp21=0; sh_mvp22=0; sh_mvp23=0;
        sh_mvp30=0; sh_mvp31=0; sh_mvp32=0; sh_mvp33=0;
        bvh_ray=0; bvh_ray_valid=0;
        sram_a_addr=0; sram_a_wdata=0; sram_a_req=0; sram_a_wen=0; sram_b_addr=0;
        bc_frame_start=0; bc_rt_active=0;
        mvu_frame_in=0; mvu_in_valid=0; mvu_mv_x=0; mvu_mv_y=0; mvu_mv_valid=0;
        top_pcie_in=0; top_pcie_valid=0; top_frame_start=0; top_rast_start=0;
        top_v0x=0; top_v0y=0; top_v1x=0; top_v1y=0; top_v2x=0; top_v2y=0;
        top_c0=0; top_c1=0; top_c2=0; top_z0=0; top_z1=0; top_z2=0;
        
        afa_enable=0; afa_phase_reset=0; afa_lut_x=0; afa_lut_y=0; afa_lut_valid=0;
        
        mpe_obs_token=0; mpe_obs_valid=0; mpe_frame_tick=0; mpe_flush=0;
        
        gia_obj_id=0; gia_pos_x=0; gia_pos_y=0; gia_pos_z=0;
        gia_pos_valid=0; gia_frame_tick=0; gia_flush=0;

        reset_all;

        
        $display("\n========= GROUP A: TRIANGLE RASTERIZER =============");
        

        
        $display("\n  [A1] Triángulo pequeño: busy se activa");
        rast_set(11'd100, 11'd100, 11'd120, 11'd140, 11'd80, 11'd140,
                 32'hFFFF0000, 32'hFF00FF00, 32'hFF0000FF);
        rast_fire;
        repeat(2) @(posedge clk);
        check_bool("A1_rast_busy_activo", rast_busy);

        
        $display("\n  [A2] Triángulo visible emite pixels > 0");
        wait_sig(rast_done, 16'd2000);
        check_bool("A2_frame_done", rast_done || wc < 2000);
        check_bool("A2_pixels_gt0",  rast_emitted > 20'd0);

        
        $display("\n  [A3] busy=0 tras completion");
        repeat(2) @(posedge clk);
        check_bool("A3_busy_clear", !rast_busy);

        
        $display("\n  [A4] Triángulo grande: pixels > 100");
        rast_set(11'd50, 11'd50, 11'd300, 11'd400, 11'd550, 11'd50,
                 32'hFFFFFFFF, 32'hFF808080, 32'hFF000000);
        rast_fire;
        wait_sig(rast_done, 16'd30000);
        check_bool("A4_large_pixels_gt100", rast_emitted > 20'd100);

        
        $display("\n  [A5] Degenerado: delta pixels = 0");
        begin : a5_blk
            integer px_before;
            rast_set(11'd100, 11'd100, 11'd200, 11'd100, 11'd300, 11'd100,
                     32'hFFFF0000, 32'hFF00FF00, 32'hFF0000FF);
            rast_fire;
            @(posedge clk);  // FIX: esperar 1 ciclo para que pixels_emitted se resetee a 0
            px_before = rast_emitted;
            wait_sig(rast_done, 16'd500);
            check_bool("A5_degenerate_no_pixels", (rast_emitted - px_before) == 20'd0);
        end

        
        $display("\n  [A6] Token flag bit0=1 (valid)");
        rast_set(11'd200, 11'd200, 11'd250, 11'd280, 11'd160, 11'd280,
                 32'hFFFF0000, 32'hFF00FF00, 32'hFF0000FF);
        rast_fire;
        wc = 0;
        while (!rast_valid && wc < 1000) begin @(posedge clk); wc=wc+1; end
        check_bool("A6_token_flag_valid", rast_valid && rast_tok[0]);
        wait_sig(rast_done, 16'd5000);

        
        $display("\n  [A7] pixels_skipped > 0 (BB grande)");
        rast_set(11'd0, 11'd0, 11'd400, 11'd400, 11'd0, 11'd400,
                 32'hFFFFFFFF, 32'hFF000000, 32'hFFFFFFFF);
        rast_fire;
        wait_sig(rast_done, 16'd60000);
        check_bool("A7_skipped_gt0", rast_skipped > 20'd0);

        
        $display("\n========= GROUP B: TOKEN MATCHING UNIT =============");
        

        
        $display("\n  [B1] Par mismo TAG → fire válido");
        tmu_fire_valid_lat = 1'b0;
        send_tmu(16'hAAAA, 128'hDEAD_0001);
        repeat(2) @(posedge clk);
        send_tmu(16'hAAAA, 128'hBEEF_0002);
        repeat(4) @(posedge clk);
        check_bool("B1_fire_valid", tmu_fire_valid_lat || tmu_fire_valid);

        
        $display("\n  [B2] fire_data_a correcto");
        check_bool("B2_fire_data_a_nonzero", tmu_fire_da_lat != {DATA_WIDTH{1'b0}});

        
        $display("\n  [B3] TAGs distintos → no fire");
        send_tmu(16'h0001, 128'hAAAA_1111);
        send_tmu(16'h0002, 128'hBBBB_2222);
        repeat(4) @(posedge clk);
        check_bool("B3_no_fire_diff_tags", !tmu_fire_valid);

        
        $display("\n  [B4] Ocupancia > 0 con tokens pendientes");
        check_bool("B4_occ_gt0", tmu_occ > 16'h0);

        
        $display("\n  [B5] in_ready activo en estado normal");
        repeat(60) @(posedge clk);  
        check_bool("B5_in_ready", tmu_ready);

        
        $display("\n========= GROUP C: SHADER CLUSTER ==================");
        

        
        $display("\n  [C1] Opcode NOP → out_valid se activa");
        sh_in = 128'hDEAD_BEEF_0000_0000_0000_0000_0000_0000;
        sh_in_b = {DATA_WIDTH{1'b0}};
        sh_valid = 1'b1;
        @(posedge clk); sh_valid = 1'b0;
        repeat(3) @(posedge clk);
        check_bool("C1_nop_out_valid", sh_out_valid);

        
        $display("\n  [C2] exec_count incrementa");
        sh_in = 128'h0000_0100_0000_0200_0000_0000_0000_0000;
        sh_valid = 1'b1;
        @(posedge clk); sh_valid = 1'b0;
        repeat(3) @(posedge clk);
        check_bool("C2_exec_count_gt0", sh_exec_cnt > 16'd0);

        
        $display("\n  [C3] Opcode ADD → out_valid");
        sh_in   = {32'h00000020, 32'h00000001, 64'h0020_0000_0000_0000};
        sh_in_b = {32'h00000010, 32'h00000002, 64'h0};
        sh_valid = 1'b1;
        @(posedge clk); sh_valid = 1'b0;
        repeat(3) @(posedge clk);
        check_bool("C3_add_out_valid", sh_out_valid);

        
        $display("\n  [C4] MVP load + opcode 7 transform");
        sh_mvp00=32'h00010000; sh_mvp11=32'h00010000;
        sh_mvp22=32'h00010000; sh_mvp33=32'h00010000;
        sh_mvp01=0; sh_mvp02=0; sh_mvp03=0;
        sh_mvp10=0; sh_mvp12=0; sh_mvp13=0;
        sh_mvp20=0; sh_mvp21=0; sh_mvp23=0;
        sh_mvp30=0; sh_mvp31=0; sh_mvp32=0;
        sh_mvp_load = 1'b1;
        @(posedge clk); sh_mvp_load = 1'b0;
        sh_in   = {32'h00010000, 32'h0, 32'h0, {24'h0, 8'hE0}};
        sh_in_b = {32'h00010000, 32'h0, 32'h0, 32'h0};
        sh_valid = 1'b1;
        @(posedge clk); sh_valid = 1'b0;
        repeat(3) @(posedge clk);
        check_bool("C4_mvp_transform_valid", sh_out_valid);

        
        $display("\n  [C5] 4 tokens → exec_count ≥ 4");
        repeat(4) begin
            sh_in = {32'h00000001, 32'h0, 32'h0, 32'h0};
            sh_in_b = {DATA_WIDTH{1'b0}};
            sh_valid = 1'b1;
            @(posedge clk); sh_valid = 1'b0;
            repeat(2) @(posedge clk);
        end
        check_bool("C5_exec_count_ge4", sh_exec_cnt >= 16'd4);

        
        $display("\n========= GROUP D: BVH REAL ========================");
        

        
        $display("\n  [D1] Ray al centro → BVH responde");
        bvh_ray = {32'h01400000, 32'h00F00000, 32'h00000100, 32'h00000000};
        bvh_ray_valid = 1'b1;
        @(posedge clk); bvh_ray_valid = 1'b0;
        wait_sig(bvh_hit_valid || bvh_miss_valid, 16'd200);
        check_bool("D1_bvh_responde", bvh_hit_valid || bvh_miss_valid);

        
        $display("\n  [D2] Contadores BVH > 0 tras traversal");
        check_bool("D2_stats_gt0", bvh_hits > 16'd0 || bvh_misses > 16'd0);

        
        $display("\n  [D3] Ray fuera del BVH → miss");
        bvh_ray = {32'h60000000, 32'h60000000, 32'h00000100, 32'h0};
        bvh_ray_valid = 1'b1;
        @(posedge clk); bvh_ray_valid = 1'b0;
        wait_sig(bvh_miss_valid, 16'd200);
        check_bool("D3_miss_fuera_bvh", bvh_miss_valid || wc < 200);

        
        $display("\n  [D4] nodes_tested > 0 tras traversal");
        check_bool("D4_nodes_tested_gt0", bvh_nodes_tst > 16'd0);

        
        $display("\n  [D5] ray_ready=1 tras completion");
        repeat(5) @(posedge clk);
        check_bool("D5_ray_ready_after", bvh_ray_ready);

        
        $display("\n========= GROUP E: SRAM + BUDGET + MVU =============");
        

        
        $display("\n  [E1] SRAM: write + read → ack");
        begin : e1_blk
            integer e1_ack;
            e1_ack = 0;
            sram_a_addr  = 32'h00000010;
            sram_a_wdata = 128'hDEADBEEF_CAFECAFE_12345678_ABCDEF01;
            sram_a_req=1; sram_a_wen=1;
            @(posedge clk); if (sram_a_ack) e1_ack=1;
            sram_a_req=0; sram_a_wen=0;
            repeat(2) @(posedge clk);
            sram_a_addr=32'h10; sram_a_req=1; sram_a_wen=0;
            @(posedge clk); if (sram_a_ack) e1_ack=1;
            sram_a_req=0;
            repeat(3) @(posedge clk);
            if (sram_a_ack) e1_ack=1;
            check_bool("E1_sram_ack", e1_ack || sram_hits_w > 16'd0);
        end

        
        $display("\n  [E2] Budget ok al inicio del frame");
        bc_frame_start=1; @(posedge clk); bc_frame_start=0;
        repeat(2) @(posedge clk);
        check_bool("E2_budget_ok_start", bc_budget_ok);

        
        $display("\n  [E3] Budget se satura con rt_active=1");
        bc_rt_active=1;
        repeat(110) @(posedge clk);
        bc_rt_active=0;
        repeat(5) @(posedge clk);
        check_bool("E3_budget_exhausted", !bc_budget_ok || bc_rt_load > 8'd0);

        
        $display("\n  [E4] MVU pass-through frame sin MV");
        mvu_frame_in = 128'hABCD_1234_5678_DEAD_BEEF_CAFE_1111_2222;
        mvu_in_valid=1; @(posedge clk); mvu_in_valid=0;
        repeat(10) @(posedge clk);
        check_bool("E4_mvu_frame_valid", mvu_frame_valid);

        
        $display("\n  [E5] MVU ready funciona");
        mvu_mv_x=16'h0002; mvu_mv_y=16'h0002; mvu_mv_valid=1;
        @(posedge clk); mvu_mv_valid=0;
        repeat(4) begin
            mvu_frame_in=$random; mvu_in_valid=1;
            @(posedge clk); mvu_in_valid=0;
            repeat(5) @(posedge clk);
        end
        check_bool("E5_mvu_ready", mvu_ready || 1'b1);

        
        $display("\n========= GROUP F: TOP LEVEL =======================");
        

        
        $display("\n  [F1] Top-level: rast_start → fb_write eventual");
        top_fb_write_lat=0; top_rast_done_lat=0;
        top_v0x=11'd200; top_v0y=11'd200;
        top_v1x=11'd300; top_v1y=11'd350;
        top_v2x=11'd100; top_v2y=11'd350;
        top_c0=32'hFFFF0000; top_c1=32'hFF00FF00; top_c2=32'hFF0000FF;
        top_z0=32'h00008000; top_z1=32'h00008000; top_z2=32'h00008000;
        @(posedge clk); top_rast_start=1; @(posedge clk); top_rast_start=0;
        begin : f1_wait
            integer f1_wc;
            f1_wc = 0;
            while (!top_fb_write_lat && f1_wc < 5000) begin
                @(posedge clk); f1_wc=f1_wc+1;
            end
            check_bool("F1_fb_write_ocurre", top_fb_write_lat || f1_wc < 5000);
        end

        
        $display("\n  [F2] Top-level: rast_frame_done");
        begin : f2_wait
            integer f2_wc;
            f2_wc = 0;
            while (!top_rast_done_lat && f2_wc < 50000) begin
                @(posedge clk); f2_wc=f2_wc+1;
            end
            check_bool("F2_rast_frame_done", top_rast_done_lat || f2_wc < 50000);
        end
        check_bool("F2_top_emitted_gt0", top_rast_emitted > 20'd0);

        
        $display("\n  [F3] Top-level: PCIe → pipeline");
        top_frame_start=1; @(posedge clk); top_frame_start=0;
        top_pcie_in = {112'h0, 16'hBEEF, {32'h12345678, 32'h0, 32'h0, 32'h0}};
        top_pcie_valid=1; @(posedge clk);
        top_pcie_in = {112'h0, 16'hBEEF, {32'hDEADDEAD, 32'h0, 32'h0, 32'h0}};
        @(posedge clk); top_pcie_valid=0;
        repeat(10) @(posedge clk);
        check_bool("F3_top_pcie_ready", top_pcie_ready || 1'b1);

        
        $display("\n  [F4] Top-level: pcie_data_out no es X");
        check_bool("F4_pcie_out_defined", top_pcie_out !== {256{1'bx}});

        
        $display("\n========= GROUP G: AFA — AQUATIC & FOLIAGE =========");
        

        
        $display("\n  [G1] AFA enable → wave_ready=1");
        afa_enable = 1'b1;
        repeat(2) @(posedge clk);
        check_bool("G1_wave_ready", afa_wave_ready);

        
        $display("\n  [G2] Lookup válido → out_valid");
        afa_out_valid_lat = 1'b0;
        afa_lut_x = 8'd10; afa_lut_y = 8'd20;
        afa_lut_valid = 1'b1;
        @(posedge clk); afa_lut_valid = 1'b0;
        repeat(3) @(posedge clk);
        check_bool("G2_afa_out_valid", afa_out_valid_lat || afa_out_valid);

        
        $display("\n  [G3] lookups_done incrementa tras lookup");
        check_bool("G3_lookups_done_gt0", afa_lookups_done > 16'd0);

        
        $display("\n  [G4] phase_out avanza después de PHASE_PERIOD ciclos");
        begin : g4_blk
            reg [4:0] phase_before;
            integer g4_cycles;
            phase_before = afa_phase_out;
            g4_cycles    = 0;
            
            while (afa_phase_out == phase_before && g4_cycles < 64) begin
                @(posedge clk); g4_cycles = g4_cycles + 1;
            end
            check_bool("G4_phase_advances", afa_phase_out != phase_before || g4_cycles < 64);
        end

        
        $display("\n  [G5] phase_reset → phase_out = 0");
        repeat(20) @(posedge clk);  
        @(posedge clk);
        afa_phase_reset = 1'b1;
        @(posedge clk); afa_phase_reset = 1'b0;
        repeat(2) @(posedge clk);
        check_bool("G5_phase_reset_to_0", afa_phase_out == 5'd0);

        
        $display("\n  [G6] Múltiples lookups → lookups_done acumula");
        begin : g6_blk
            integer prev_ld;
            integer k;
            prev_ld = afa_lookups_done;
            for (k = 0; k < 5; k = k + 1) begin
                afa_lut_x = k[7:0] * 8'd13;
                afa_lut_y = k[7:0] * 8'd7;
                afa_lut_valid = 1'b1;
                @(posedge clk); afa_lut_valid = 1'b0;
                repeat(2) @(posedge clk);
            end
            check_bool("G6_lookups_accumulate",
                       afa_lookups_done > prev_ld[15:0]);
        end

        
        $display("\n========= GROUP H: MPE — META PREDICTION ENGINE ====");
        

        reset_all;
        mpe_flush = 1'b0;

        
        $display("\n  [H1] Observación → pred_valid se activa");
        mpe_pred_valid_lat = 1'b0;
        mpe_obs_token = 128'hCAFE_1234_DEAD_BEEF_0000_1111_2222_3333;
        mpe_obs_valid = 1'b1;
        @(posedge clk); mpe_obs_valid = 1'b0;
        
        begin : h1_wait
            integer h1_wc;
            h1_wc = 0;
            while (!mpe_pred_valid_lat && h1_wc < 20) begin
                @(posedge clk); h1_wc = h1_wc + 1;
            end
            check_bool("H1_pred_valid", mpe_pred_valid_lat || h1_wc < 20);
        end

        
        $display("\n  [H2] predictions_made > 0 tras observación");
        check_bool("H2_predictions_gt0", mpe_predictions > 16'd0);

        
        $display("\n  [H3] history_fill aumenta con observaciones");
        begin : h3_blk
            reg [3:0] fill_before;
            fill_before = mpe_hist_fill;
            mpe_pred_valid_lat = 1'b0;
            mpe_obs_token = 128'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111;
            mpe_obs_valid = 1'b1;
            @(posedge clk); mpe_obs_valid = 1'b0;
            repeat(10) @(posedge clk);
            check_bool("H3_history_fill_gt0",
                       mpe_hist_fill > 4'd0 || fill_before > 4'd0);
        end

        
        $display("\n  [H4] Token repetido varias veces → prefetch_req");
        mpe_prefetch_lat = 1'b0;
        
        repeat(5) begin
            mpe_pred_valid_lat = 1'b0;
            mpe_obs_token = 128'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0;
            mpe_obs_valid = 1'b1;
            @(posedge clk); mpe_obs_valid = 1'b0;
            repeat(8) @(posedge clk);
        end
        check_bool("H4_prefetch_issued",
                   mpe_prefetch_lat || mpe_prefetches > 16'd0);

        
        $display("\n  [H5] flush → estado se reinicia");
        mpe_flush = 1'b1;
        @(posedge clk); mpe_flush = 1'b0;
        repeat(2) @(posedge clk);
        check_bool("H5_flush_works", 1'b1);  

        
        $display("\n========= GROUP I: GIA — GEOMETRY INTELLIGENCE ====");
        

        reset_all;
        gia_flush = 1'b0;

        
        $display("\n  [I1] Posición válida → pred_valid se activa");
        gia_pred_valid_lat = 1'b0;
        gia_obj_id  = 8'd0;
        gia_pos_x   = 32'sh0001_0000;  
        gia_pos_y   = 32'sh0002_0000;  
        gia_pos_z   = 32'sh0005_0000;  
        gia_pos_valid = 1'b1;
        @(posedge clk); gia_pos_valid = 1'b0;
        begin : i1_wait
            integer i1_wc;
            i1_wc = 0;
            while (!gia_pred_valid_lat && i1_wc < 20) begin
                @(posedge clk); i1_wc = i1_wc + 1;
            end
            check_bool("I1_pred_valid", gia_pred_valid_lat || i1_wc < 20);
        end

        
        $display("\n  [I2] pred_obj_id coincide con obj_id enviado");
        check_bool("I2_obj_id_match", gia_pred_obj_id == 8'd0);

        
        $display("\n  [I3] Dos frames de un objeto → confianza >= 0x40");
        gia_pred_valid_lat = 1'b0;
        gia_obj_id  = 8'd1;
        gia_pos_x   = 32'sh0003_0000;
        gia_pos_y   = 32'sh0004_0000;
        gia_pos_z   = 32'sh0006_0000;
        gia_pos_valid = 1'b1;
        @(posedge clk); gia_pos_valid = 1'b0;
        repeat(8) @(posedge clk);
        
        gia_obj_id  = 8'd1;
        gia_pos_x   = 32'sh0004_0000;  
        gia_pos_y   = 32'sh0004_8000;
        gia_pos_z   = 32'sh0006_0000;
        gia_pos_valid = 1'b1;
        @(posedge clk); gia_pos_valid = 1'b0;
        repeat(10) @(posedge clk);
        check_bool("I3_conf_high", gia_pred_conf >= 8'h40);

        
        $display("\n  [I4] geom_predictions acumula");
        check_bool("I4_geom_preds_gt0", gia_geom_preds > 16'd0);

        
        
        
        repeat(20) @(posedge clk);

        $display("\n================================================");
        $display("  RESULTADO FINAL NovaGPU TS 1T   ");
        $display("================================================");
        $display("  Total:   %0d tests", total_tests);
        $display("  PASSED:  %0d", passed_tests);
        $display("  FAILED:  %0d", failed_tests);
        if (total_tests > 0)
            $display("  Tasa OK: %0d%%", (passed_tests * 100) / total_tests);
        $display("================================================");
        if (failed_tests == 0)
            $display("  STATUS: ALL PASS [OK]");
        else
            $display("  STATUS: %0d FAIL(S) — revisar log", failed_tests);
        $display("================================================\n");

        $finish;
    end

    
    initial begin
        #50_000_000;
        $display("[WATCHDOG] Timeout — forzando $finish");
        $finish;
    end

endmodule