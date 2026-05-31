
`timescale 1ns/1ps
// =============================================================================
// triangle_rasterizer.v  —  NovaGPU TS1T  v2.4-FIX
//
// FIX v2.4: frame_done cleared only on start, not on every ST_IDLE entry.
//   Previously: frame_done <= 0 every cycle in ST_IDLE → only 1-cycle pulse.
//   Now: frame_done <= 0 when a new start is issued. Stays high until then.
//
// FIX v2.3 (maintained): CW winding correction, degenerate skip, BB clipping.
//
// Token layout [127:0]:
//   [127:96] color  [95:64] z  [63:48] px  [47:32] py
//   [31:16]  tri_id [15:3] rsvd  [2] is_last  [1] edge  [0] valid
// =============================================================================

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

    // ── Bounding box raw (combinacional) ─────────────────────
    wire [10:0] xmin_raw = (v0_x < v1_x) ?
                               ((v0_x < v2_x) ? v0_x : v2_x) :
                               ((v1_x < v2_x) ? v1_x : v2_x);
    wire [10:0] xmax_raw = (v0_x > v1_x) ?
                               ((v0_x > v2_x) ? v0_x : v2_x) :
                               ((v1_x > v2_x) ? v1_x : v2_x);
    wire [10:0] ymin_raw = (v0_y < v1_y) ?
                               ((v0_y < v2_y) ? v0_y : v2_y) :
                               ((v1_y < v2_y) ? v1_y : v2_y);
    wire [10:0] ymax_raw = (v0_y > v1_y) ?
                               ((v0_y > v2_y) ? v0_y : v2_y) :
                               ((v1_y > v2_y) ? v1_y : v2_y);

    // FIX A6: tri_offscreen — triángulo completamente fuera
    wire tri_offscreen = (xmin_raw >= SCREEN_W[10:0]) ||
                         (ymin_raw >= SCREEN_H[10:0]);

    wire [10:0] xmin_c = tri_offscreen ? 11'd1 :
                          (xmin_raw >= SCREEN_W[10:0]) ? 11'd0 : xmin_raw;
    wire [10:0] xmax_c = (xmax_raw >= SCREEN_W[10:0]) ? SCREEN_W[10:0]-11'd1 : xmax_raw;
    wire [10:0] ymin_c = tri_offscreen ? 11'd1 :
                          (ymin_raw >= SCREEN_H[10:0]) ? 11'd0 : ymin_raw;
    wire [10:0] ymax_c = (ymax_raw >= SCREEN_H[10:0]) ? SCREEN_H[10:0]-11'd1 : ymax_raw;

    // ── Edge functions COMBINACIONALES ────────────────────────
    wire signed [23:0] w0_comb = (px - rv1_x) * A12 + (py - rv1_y) * B12;
    wire signed [23:0] w1_comb = (px - rv2_x) * A20 + (py - rv2_y) * B20;
    wire signed [23:0] w2_comb = (px - rv0_x) * A01 + (py - rv0_y) * B01;

    wire pixel_inside = (w0_comb >= 24'sd0) &&
                        (w1_comb >= 24'sd0) &&
                        (w2_comb >= 24'sd0) &&
                        (area2 != 24'sd0);

    wire is_last = (px >= bb_xmax) && (py >= bb_ymax);

    // ── Color/z combinacional ─────────────────────────────────
    wire [7:0] c0_r = c0[23:16], c0_g = c0[15:8], c0_b = c0[7:0];
    wire [7:0] c1_r = c1[23:16], c1_g = c1[15:8], c1_b = c1[7:0];
    wire [7:0] c2_r = c2[23:16], c2_g = c2[15:8], c2_b = c2[7:0];

    wire signed [47:0] ci_r_raw = $signed({16'd0, c0_r}) * $signed(w0_comb) +
                                   $signed({16'd0, c1_r}) * $signed(w1_comb) +
                                   $signed({16'd0, c2_r}) * $signed(w2_comb);
    wire signed [47:0] ci_g_raw = $signed({16'd0, c0_g}) * $signed(w0_comb) +
                                   $signed({16'd0, c1_g}) * $signed(w1_comb) +
                                   $signed({16'd0, c2_g}) * $signed(w2_comb);
    wire signed [47:0] ci_b_raw = $signed({16'd0, c0_b}) * $signed(w0_comb) +
                                   $signed({16'd0, c1_b}) * $signed(w1_comb) +
                                   $signed({16'd0, c2_b}) * $signed(w2_comb);

    wire [7:0] ci_r = (area2 != 24'sd0) ?
                      (ci_r_raw / $signed({8'd0, area2})) : {8'd0};
    wire [7:0] ci_g = (area2 != 24'sd0) ?
                      (ci_g_raw / $signed({8'd0, area2})) : {8'd0};
    wire [7:0] ci_b = (area2 != 24'sd0) ?
                      (ci_b_raw / $signed({8'd0, area2})) : {8'd0};

    wire [31:0] color_comb = {8'hFF, ci_r, ci_g, ci_b};

    wire signed [63:0] zi_raw = $signed({32'd0, z0}) * $signed(w0_comb) +
                                 $signed({32'd0, z1}) * $signed(w1_comb) +
                                 $signed({32'd0, z2}) * $signed(w2_comb);
    wire [31:0] z_comb = (area2 != 24'sd0) ?
                          (zi_raw / $signed({8'd0, area2})) : 32'd0;

    // ── Área signed (combinacional) ────────────────────────────
    wire signed [23:0] area2_comb =
        ($signed({1'b0, v1_x}) - $signed({1'b0, v0_x})) *
        ($signed({1'b0, v2_y}) - $signed({1'b0, v0_y})) -
        ($signed({1'b0, v1_y}) - $signed({1'b0, v0_y})) *
        ($signed({1'b0, v2_x}) - $signed({1'b0, v0_x}));

    wire tri_is_cw = (area2_comb > 24'sd0);

    wire bb_empty = ($signed({1'b0, xmin_c}) > $signed({1'b0, xmax_c})) ||
                    ($signed({1'b0, ymin_c}) > $signed({1'b0, ymax_c})) ||
                    tri_offscreen;

    wire skip_run = (area2_comb == 24'sd0) || bb_empty;

    // ── Deltas para CCW (sin negación) ────────────────────────
    wire signed [11:0] A01_ccw = $signed({1'b0, v1_y}) - $signed({1'b0, v0_y});
    wire signed [11:0] B01_ccw = $signed({1'b0, v0_x}) - $signed({1'b0, v1_x});
    wire signed [11:0] A12_ccw = $signed({1'b0, v2_y}) - $signed({1'b0, v1_y});
    wire signed [11:0] B12_ccw = $signed({1'b0, v1_x}) - $signed({1'b0, v2_x});
    wire signed [11:0] A20_ccw = $signed({1'b0, v0_y}) - $signed({1'b0, v2_y});
    wire signed [11:0] B20_ccw = $signed({1'b0, v2_x}) - $signed({1'b0, v0_x});

    wire signed [11:0] A01_sel = tri_is_cw ? -A01_ccw : A01_ccw;
    wire signed [11:0] B01_sel = tri_is_cw ? -B01_ccw : B01_ccw;
    wire signed [11:0] A12_sel = tri_is_cw ? -A12_ccw : A12_ccw;
    wire signed [11:0] B12_sel = tri_is_cw ? -B12_ccw : B12_ccw;
    wire signed [11:0] A20_sel = tri_is_cw ? -A20_ccw : A20_ccw;
    wire signed [11:0] B20_sel = tri_is_cw ? -B20_ccw : B20_ccw;

    // ── FSM Principal ─────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            busy           <= 1'b0;
            token_valid    <= 1'b0;
            token_pending  <= 1'b0;
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
            area2 <= 24'sd0;
            bb_xmin <= 12'sd0; bb_xmax <= 12'sd0;
            bb_ymin <= 12'sd0; bb_ymax <= 12'sd0;
            px <= 12'sd0; py <= 12'sd0;
        end else begin

            // Handshake downstream
            if (token_valid && token_ready) begin
                token_valid   <= 1'b0;
                token_pending <= 1'b0;
            end

            case (state)
                ST_IDLE: begin
                    // FIX v2.4: frame_done cleared only when new start issued
                    if (start && !busy) begin
                        frame_done     <= 1'b0;   // Bajar al iniciar nuevo triángulo
                        busy           <= 1'b1;
                        pixels_emitted <= 20'd0;
                        pixels_skipped <= 20'd0;
                        state          <= ST_SETUP;
                    end
                end

                ST_SETUP: begin
                    bb_xmin <= $signed({1'b0, xmin_c});
                    bb_xmax <= $signed({1'b0, xmax_c});
                    bb_ymin <= $signed({1'b0, ymin_c});
                    bb_ymax <= $signed({1'b0, ymax_c});
                    px      <= $signed({1'b0, xmin_c});
                    py      <= $signed({1'b0, ymin_c});

                    rv0_x <= $signed({1'b0, v0_x});
                    rv0_y <= $signed({1'b0, v0_y});
                    rv1_x <= $signed({1'b0, v1_x});
                    rv1_y <= $signed({1'b0, v1_y});
                    rv2_x <= $signed({1'b0, v2_x});
                    rv2_y <= $signed({1'b0, v2_y});

                    A01 <= A01_sel;
                    B01 <= B01_sel;
                    A12 <= A12_sel;
                    B12 <= B12_sel;
                    A20 <= A20_sel;
                    B20 <= B20_sel;

                    area2 <= (area2_comb < 24'sd0) ? -area2_comb : area2_comb;

                    if (skip_run) begin
                        state <= ST_DONE;
                    end else begin
                        state <= ST_RUN;
                    end
                end

                ST_RUN: begin
                    if (!token_pending || (token_valid && token_ready)) begin
                        if (pixel_inside) begin
                            token_out    <= {color_comb, z_comb,
                                             {5'd0, px[10:0]}, {5'd0, py[10:0]},
                                             tri_id,
                                             13'd0, is_last, 1'b1, 1'b1};
                            token_valid   <= 1'b1;
                            token_pending <= 1'b1;
                            pixels_emitted <= pixels_emitted + 20'd1;
                        end else begin
                            pixels_skipped <= pixels_skipped + 20'd1;
                        end

                        // Advance scan
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
                    // FIX v2.4: frame_done en NIVEL — se activa en ST_DONE
                    // y permanece alto hasta que se inicie un nuevo triángulo (en ST_IDLE).
                    frame_done <= 1'b1;

                    // Salir sólo cuando no hay token pendiente
                    if (!token_pending || (token_valid && token_ready)) begin
                        token_valid <= 1'b0;
                        busy        <= 1'b0;
                        state       <= ST_IDLE;
                        // frame_done NO se baja aquí — se baja en ST_IDLE cuando llega start
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
