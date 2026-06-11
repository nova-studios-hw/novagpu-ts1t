`timescale 1ns/1ps










































module triangle_rasterizer #(
    parameter DATA_WIDTH = 128,
    parameter SCREEN_W   = 640,
    parameter SCREEN_H   = 480
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire [10:0] v0_x, v0_y,
    input  wire [10:0] v1_x, v1_y,
    input  wire [10:0] v2_x, v2_y,

    input  wire [31:0] c0, c1, c2,
    input  wire [31:0] z0, z1, z2,

    input  wire        start,
    output reg         busy,

    output reg  [DATA_WIDTH-1:0] token_out,
    output reg                   token_valid,
    input  wire                  token_ready,

    output reg  [19:0] pixels_emitted,
    output reg  [19:0] pixels_skipped,
    output reg         frame_done
);

    localparam ST_IDLE  = 2'd0;
    localparam ST_SETUP = 2'd1;
    localparam ST_RUN   = 2'd2;
    localparam ST_DONE  = 2'd3;

    reg [1:0] state;

    reg signed [11:0] bb_xmin, bb_xmax, bb_ymin, bb_ymax;
    reg signed [11:0] px, py;

    reg signed [11:0] A01, A12, A20;
    reg signed [11:0] B01, B12, B20;
    reg signed [23:0] area2;

    reg signed [11:0] rv0_x, rv0_y;
    reg signed [11:0] rv1_x, rv1_y;
    reg signed [11:0] rv2_x, rv2_y;

    reg [15:0] tri_id;
    reg        token_pending;

    
    reg emit_staged;

    
    wire signed [11:0] v0_x_s = {v0_x[10], v0_x};
    wire signed [11:0] v0_y_s = {v0_y[10], v0_y};
    wire signed [11:0] v1_x_s = {v1_x[10], v1_x};
    wire signed [11:0] v1_y_s = {v1_y[10], v1_y};
    wire signed [11:0] v2_x_s = {v2_x[10], v2_x};
    wire signed [11:0] v2_y_s = {v2_y[10], v2_y};

    
    wire signed [11:0] xmin_raw_s =
        (v0_x_s < v1_x_s) ? ((v0_x_s < v2_x_s) ? v0_x_s : v2_x_s)
                           : ((v1_x_s < v2_x_s) ? v1_x_s : v2_x_s);

    wire signed [11:0] xmax_raw_s =
        (v0_x_s > v1_x_s) ? ((v0_x_s > v2_x_s) ? v0_x_s : v2_x_s)
                           : ((v1_x_s > v2_x_s) ? v1_x_s : v2_x_s);

    wire signed [11:0] ymin_raw_s =
        (v0_y_s < v1_y_s) ? ((v0_y_s < v2_y_s) ? v0_y_s : v2_y_s)
                           : ((v1_y_s < v2_y_s) ? v1_y_s : v2_y_s);

    wire signed [11:0] ymax_raw_s =
        (v0_y_s > v1_y_s) ? ((v0_y_s > v2_y_s) ? v0_y_s : v2_y_s)
                           : ((v1_y_s > v2_y_s) ? v1_y_s : v2_y_s);

    
    wire signed [11:0] screen_wm1_s = $signed(SCREEN_W - 1);
    wire signed [11:0] screen_hm1_s = $signed(SCREEN_H - 1);

    
    wire signed [11:0] xmin_c_s =
        (xmin_raw_s < 12'sd0)       ? 12'sd0        :
        (xmin_raw_s > screen_wm1_s) ? screen_wm1_s  : xmin_raw_s;

    wire signed [11:0] xmax_c_s =
        (xmax_raw_s < 12'sd0)       ? 12'sd0        :
        (xmax_raw_s > screen_wm1_s) ? screen_wm1_s  : xmax_raw_s;

    wire signed [11:0] ymin_c_s =
        (ymin_raw_s < 12'sd0)       ? 12'sd0        :
        (ymin_raw_s > screen_hm1_s) ? screen_hm1_s  : ymin_raw_s;

    wire signed [11:0] ymax_c_s =
        (ymax_raw_s < 12'sd0)       ? 12'sd0        :
        (ymax_raw_s > screen_hm1_s) ? screen_hm1_s  : ymax_raw_s;

    
    wire tri_offscreen =
        (xmax_raw_s < 12'sd0)       ||
        (ymax_raw_s < 12'sd0)       ||
        (xmin_raw_s > screen_wm1_s) ||
        (ymin_raw_s > screen_hm1_s);

    
    wire signed [23:0] w0_comb = (px - rv1_x) * A12 + (py - rv1_y) * B12;
    wire signed [23:0] w1_comb = (px - rv2_x) * A20 + (py - rv2_y) * B20;
    wire signed [23:0] w2_comb = (px - rv0_x) * A01 + (py - rv0_y) * B01;

    wire pixel_inside = (w0_comb >= 24'sd0) &&
                        (w1_comb >= 24'sd0) &&
                        (w2_comb >= 24'sd0) &&
                        (area2   != 24'sd0);

    wire is_last = (px >= bb_xmax) && (py >= bb_ymax);

    
    wire [7:0] c0_r = c0[23:16], c0_g = c0[15:8], c0_b = c0[7:0];
    wire [7:0] c1_r = c1[23:16], c1_g = c1[15:8], c1_b = c1[7:0];
    wire [7:0] c2_r = c2[23:16], c2_g = c2[15:8], c2_b = c2[7:0];

    wire signed [47:0] ci_r_raw =
        $signed({16'd0, c0_r}) * $signed(w0_comb) +
        $signed({16'd0, c1_r}) * $signed(w1_comb) +
        $signed({16'd0, c2_r}) * $signed(w2_comb);

    wire signed [47:0] ci_g_raw =
        $signed({16'd0, c0_g}) * $signed(w0_comb) +
        $signed({16'd0, c1_g}) * $signed(w1_comb) +
        $signed({16'd0, c2_g}) * $signed(w2_comb);

    wire signed [47:0] ci_b_raw =
        $signed({16'd0, c0_b}) * $signed(w0_comb) +
        $signed({16'd0, c1_b}) * $signed(w1_comb) +
        $signed({16'd0, c2_b}) * $signed(w2_comb);

    wire [7:0] ci_r = (area2 != 24'sd0) ?
                      ci_r_raw / $signed({8'd0, area2}) : 8'd0;
    wire [7:0] ci_g = (area2 != 24'sd0) ?
                      ci_g_raw / $signed({8'd0, area2}) : 8'd0;
    wire [7:0] ci_b = (area2 != 24'sd0) ?
                      ci_b_raw / $signed({8'd0, area2}) : 8'd0;

    wire [31:0] color_comb = {8'hFF, ci_r, ci_g, ci_b};

    wire signed [63:0] zi_raw =
        $signed({32'd0, z0}) * $signed(w0_comb) +
        $signed({32'd0, z1}) * $signed(w1_comb) +
        $signed({32'd0, z2}) * $signed(w2_comb);

    wire [31:0] z_comb = (area2 != 24'sd0) ?
                         zi_raw / $signed({8'd0, area2}) : 32'd0;

    
    wire signed [23:0] area2_comb =
        (v1_x_s - v0_x_s) * (v2_y_s - v0_y_s) -
        (v1_y_s - v0_y_s) * (v2_x_s - v0_x_s);

    wire tri_is_cw = (area2_comb > 24'sd0);

    wire bb_empty =
        (xmin_c_s > xmax_c_s) ||
        (ymin_c_s > ymax_c_s) ||
        tri_offscreen;

    wire skip_run = (area2_comb == 24'sd0) || bb_empty;

    
    wire signed [11:0] A01_ccw = v1_y_s - v0_y_s;
    wire signed [11:0] B01_ccw = v0_x_s - v1_x_s;
    wire signed [11:0] A12_ccw = v2_y_s - v1_y_s;
    wire signed [11:0] B12_ccw = v1_x_s - v2_x_s;
    wire signed [11:0] A20_ccw = v0_y_s - v2_y_s;
    wire signed [11:0] B20_ccw = v2_x_s - v0_x_s;

    wire signed [11:0] A01_sel = tri_is_cw ? -A01_ccw : A01_ccw;
    wire signed [11:0] B01_sel = tri_is_cw ? -B01_ccw : B01_ccw;
    wire signed [11:0] A12_sel = tri_is_cw ? -A12_ccw : A12_ccw;
    wire signed [11:0] B12_sel = tri_is_cw ? -B12_ccw : B12_ccw;
    wire signed [11:0] A20_sel = tri_is_cw ? -A20_ccw : A20_ccw;
    wire signed [11:0] B20_sel = tri_is_cw ? -B20_ccw : B20_ccw;

    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            busy           <= 1'b0;
            token_valid    <= 1'b0;
            token_pending  <= 1'b0;
            emit_staged    <= 1'b0;
            pixels_emitted <= 20'd0;
            pixels_skipped <= 20'd0;
            frame_done     <= 1'b0;
            tri_id         <= 16'd0;

            rv0_x <= 12'sd0; rv0_y <= 12'sd0;
            rv1_x <= 12'sd0; rv1_y <= 12'sd0;
            rv2_x <= 12'sd0; rv2_y <= 12'sd0;

            A01 <= 12'sd0; B01 <= 12'sd0;
            A12 <= 12'sd0; B12 <= 12'sd0;
            A20 <= 12'sd0; B20 <= 12'sd0;

            area2   <= 24'sd0;
            bb_xmin <= 12'sd0; bb_xmax <= 12'sd0;
            bb_ymin <= 12'sd0; bb_ymax <= 12'sd0;
            px      <= 12'sd0; py      <= 12'sd0;
        end else begin

            
            
            
            if (start) begin
                frame_done    <= 1'b0;
                busy          <= 1'b1;
                token_valid   <= 1'b0;
                token_pending <= 1'b0;
                emit_staged   <= 1'b0;  
                
                state         <= ST_SETUP;

            end else begin

                
                
                
                if (emit_staged) begin
                    pixels_emitted <= pixels_emitted + 20'd1;
                    emit_staged    <= 1'b0;
                end

                
                
                
                
                if (token_valid && token_ready) begin
                    token_valid   <= 1'b0;
                    token_pending <= 1'b0;
                    emit_staged   <= 1'b1;
                end

                
                case (state)
                    ST_IDLE: begin
                        
                    end

                    ST_SETUP: begin
                        bb_xmin <= xmin_c_s;
                        bb_xmax <= xmax_c_s;
                        bb_ymin <= ymin_c_s;
                        bb_ymax <= ymax_c_s;
                        px      <= xmin_c_s;
                        py      <= ymin_c_s;

                        rv0_x <= v0_x_s; rv0_y <= v0_y_s;
                        rv1_x <= v1_x_s; rv1_y <= v1_y_s;
                        rv2_x <= v2_x_s; rv2_y <= v2_y_s;

                        A01 <= A01_sel; B01 <= B01_sel;
                        A12 <= A12_sel; B12 <= B12_sel;
                        A20 <= A20_sel; B20 <= B20_sel;

                        area2 <= (area2_comb < 24'sd0) ?
                                 -area2_comb : area2_comb;

                        if (skip_run) begin
                            token_valid   <= 1'b0;
                            token_pending <= 1'b0;
                            emit_staged   <= 1'b0;
                            state         <= ST_DONE;
                        end else begin
                            state <= ST_RUN;
                        end
                    end

                    ST_RUN: begin
                        if (!token_pending || (token_valid && token_ready)) begin
                            if (pixel_inside) begin
                                token_out <= {color_comb, z_comb,
                                              {5'd0, px[10:0]}, {5'd0, py[10:0]},
                                              tri_id,
                                              13'd0, is_last, 1'b1, 1'b1};
                                token_valid   <= 1'b1;
                                token_pending <= 1'b1;
                                
                            end else begin
                                pixels_skipped <= pixels_skipped + 20'd1;
                            end

                            
                            if (px >= bb_xmax) begin
                                px <= bb_xmin;
                                if (py >= bb_ymax) begin
                                    state  <= ST_DONE;
                                    tri_id <= tri_id + 16'd1;
                                end else begin
                                    py <= py + 12'sd1;
                                end
                            end else begin
                                px <= px + 12'sd1;
                            end
                        end
                    end

                    ST_DONE: begin
                        frame_done <= 1'b1;
                        if (!token_pending || (token_valid && token_ready)) begin
                            token_valid <= 1'b0;
                            busy        <= 1'b0;
                            state       <= ST_IDLE;
                        end
                    end

                    default: state <= ST_IDLE;
                endcase

            end 
        end
    end

endmodule
