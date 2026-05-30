`timescale 1ns/1ps
// =============================================================================
// bvh_real.v  —  BVH Traversal  v3.0
// NovaGPU TS 2T  —  Nova Studios / Maximal Technology
//
// BVH de 8 nodos (árbol binario 3 niveles) con AABB slab intersection.
// Recíproco por LUT de 256 entradas.
// Stack hardware de 8 niveles para DFS.
//
// Ray token [127:0]:
//   [127:96] = ray_ox  (Q16.16)
//   [95:64]  = ray_oy  (Q16.16)
//   [63:32]  = ray_dx  (Q16.16)
//   [31:0]   = ray_dy  (Q16.16)
//
// Correcciones v3.0:
//   - Stack gestionado como reg array (sin unpacked ports)
//   - FSM bien separada del comb
//   - miss_valid pulsado correctamente al final del traversal
// =============================================================================

// ── Reciprocal LUT (256 entradas, Q16.16) ─────────────────────
module reciprocal_lut (
    input  wire [7:0]  index,
    output reg  [31:0] recip_q1616
);
    always @(*) begin
        case (index)
            8'd0:   recip_q1616 = 32'h7FFFFFFF;
            8'd1:   recip_q1616 = 32'h00010000;
            8'd2:   recip_q1616 = 32'h00008000;
            8'd3:   recip_q1616 = 32'h00005555;
            8'd4:   recip_q1616 = 32'h00004000;
            8'd5:   recip_q1616 = 32'h00003333;
            8'd6:   recip_q1616 = 32'h00002AAA;
            8'd7:   recip_q1616 = 32'h00002492;
            8'd8:   recip_q1616 = 32'h00002000;
            8'd9:   recip_q1616 = 32'h00001C71;
            8'd10:  recip_q1616 = 32'h00001999;
            8'd11:  recip_q1616 = 32'h00001745;
            8'd12:  recip_q1616 = 32'h00001555;
            8'd13:  recip_q1616 = 32'h000013B1;
            8'd14:  recip_q1616 = 32'h00001249;
            8'd15:  recip_q1616 = 32'h00001111;
            8'd16:  recip_q1616 = 32'h00001000;
            8'd20:  recip_q1616 = 32'h00000CCC;
            8'd24:  recip_q1616 = 32'h00000AAA;
            8'd32:  recip_q1616 = 32'h00000800;
            8'd48:  recip_q1616 = 32'h00000555;
            8'd64:  recip_q1616 = 32'h00000400;
            8'd96:  recip_q1616 = 32'h000002AA;
            8'd128: recip_q1616 = 32'h00000200;
            8'd192: recip_q1616 = 32'h00000155;
            8'd255: recip_q1616 = 32'h00000101;
            default: recip_q1616 = (index > 8'd0) ?
                                   (32'h00010000 / {24'd0, index}) :
                                   32'h7FFFFFFF;
        endcase
    end
endmodule

// ── AABB 2D Slab Intersection (versión simplificada 2D para simulación) ───
module aabb_intersect_2d (
    input  wire signed [31:0] ray_ox, ray_oy,
    input  wire signed [31:0] inv_dx, inv_dy,
    input  wire signed [31:0] box_xmin, box_ymin,
    input  wire signed [31:0] box_xmax, box_ymax,
    output wire               hit,
    output wire signed [31:0] tmin_out,
    output wire signed [31:0] tmax_out
);
    wire dx_zero = (inv_dx == 32'h7FFFFFFF);
    wire dy_zero = (inv_dy == 32'h7FFFFFFF);

    wire signed [63:0] tx0_f = $signed(box_xmin - ray_ox) * $signed(inv_dx);
    wire signed [63:0] tx1_f = $signed(box_xmax - ray_ox) * $signed(inv_dx);
    wire signed [63:0] ty0_f = $signed(box_ymin - ray_oy) * $signed(inv_dy);
    wire signed [63:0] ty1_f = $signed(box_ymax - ray_oy) * $signed(inv_dy);

    wire signed [31:0] tx0 = tx0_f[47:16];
    wire signed [31:0] tx1 = tx1_f[47:16];
    wire signed [31:0] ty0 = ty0_f[47:16];
    wire signed [31:0] ty1 = ty1_f[47:16];

    wire signed [31:0] tmin_x = ($signed(tx0) < $signed(tx1)) ? tx0 : tx1;
    wire signed [31:0] tmax_x = ($signed(tx0) > $signed(tx1)) ? tx0 : tx1;
    wire signed [31:0] tmin_y = ($signed(ty0) < $signed(ty1)) ? ty0 : ty1;
    wire signed [31:0] tmax_y = ($signed(ty0) > $signed(ty1)) ? ty0 : ty1;

    wire signed [31:0] tmin_eff = dx_zero ? tmin_y :
                                  dy_zero ? tmin_x :
                                  (tmin_x > tmin_y) ? tmin_x : tmin_y;
    wire signed [31:0] tmax_eff = dx_zero ? tmax_y :
                                  dy_zero ? tmax_x :
                                  (tmax_x < tmax_y) ? tmax_x : tmax_y;

    wire in_x = dx_zero ? ($signed(ray_ox) >= $signed(box_xmin) &&
                            $signed(ray_ox) <= $signed(box_xmax)) : 1'b1;
    wire in_y = dy_zero ? ($signed(ray_oy) >= $signed(box_ymin) &&
                            $signed(ray_oy) <= $signed(box_ymax)) : 1'b1;

    assign tmin_out = tmin_eff;
    assign tmax_out = tmax_eff;
    assign hit = in_x && in_y &&
                 ($signed(tmin_eff) <= $signed(tmax_eff)) &&
                 ($signed(tmax_eff) >= 32'sd0);
endmodule

// ── BVH Traversal Top ──────────────────────────────────────────
module bvh_real #(
    parameter BVH_DEPTH  = 8,
    parameter DATA_WIDTH = 128
)(
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire [DATA_WIDTH-1:0]  ray_token,
    input  wire                   ray_valid,
    output reg                    ray_ready,

    output reg                    hit_valid,
    output reg  [7:0]             hit_prim_id,
    output reg  [31:0]            hit_t,
    output reg  [DATA_WIDTH-1:0]  hit_token,

    output reg                    miss_valid,
    output reg  [15:0]            nodes_tested,

    output reg  [15:0]            hits_total,
    output reg  [15:0]            misses_total
);

    // ── BVH Node ROM (8 nodos, árbol 3 niveles) ───────────────
    localparam N = 8;
    reg signed [31:0] node_xmin  [0:N-1];
    reg signed [31:0] node_ymin  [0:N-1];
    reg signed [31:0] node_xmax  [0:N-1];
    reg signed [31:0] node_ymax  [0:N-1];
    reg [2:0]         node_left  [0:N-1];
    reg [2:0]         node_right [0:N-1];
    reg               node_leaf  [0:N-1];
    reg [7:0]         node_prim  [0:N-1];

    initial begin
        node_xmin[0] = 32'h00000000; node_ymin[0] = 32'h00000000;
        node_xmax[0] = 32'h02800000; node_ymax[0] = 32'h01E00000;
        node_left[0] = 3'd1; node_right[0] = 3'd2;
        node_leaf[0] = 1'b0; node_prim[0]  = 8'd0;

        node_xmin[1] = 32'h00000000; node_ymin[1] = 32'h00000000;
        node_xmax[1] = 32'h01400000; node_ymax[1] = 32'h01E00000;
        node_left[1] = 3'd3; node_right[1] = 3'd4;
        node_leaf[1] = 1'b0; node_prim[1]  = 8'd0;

        node_xmin[2] = 32'h01400000; node_ymin[2] = 32'h00000000;
        node_xmax[2] = 32'h02800000; node_ymax[2] = 32'h01E00000;
        node_left[2] = 3'd5; node_right[2] = 3'd6;
        node_leaf[2] = 1'b0; node_prim[2]  = 8'd0;

        node_xmin[3] = 32'h00000000; node_ymin[3] = 32'h00000000;
        node_xmax[3] = 32'h01400000; node_ymax[3] = 32'h00F00000;
        node_left[3] = 3'd0; node_right[3] = 3'd0;
        node_leaf[3] = 1'b1; node_prim[3]  = 8'd0;

        node_xmin[4] = 32'h00000000; node_ymin[4] = 32'h00F00000;
        node_xmax[4] = 32'h01400000; node_ymax[4] = 32'h01E00000;
        node_left[4] = 3'd0; node_right[4] = 3'd0;
        node_leaf[4] = 1'b1; node_prim[4]  = 8'd1;

        node_xmin[5] = 32'h01400000; node_ymin[5] = 32'h00000000;
        node_xmax[5] = 32'h02800000; node_ymax[5] = 32'h00F00000;
        node_left[5] = 3'd0; node_right[5] = 3'd0;
        node_leaf[5] = 1'b1; node_prim[5]  = 8'd2;

        node_xmin[6] = 32'h01400000; node_ymin[6] = 32'h00F00000;
        node_xmax[6] = 32'h02800000; node_ymax[6] = 32'h01E00000;
        node_left[6] = 3'd0; node_right[6] = 3'd0;
        node_leaf[6] = 1'b1; node_prim[6]  = 8'd3;

        node_xmin[7] = 32'h0; node_ymin[7] = 32'h0;
        node_xmax[7] = 32'h0; node_ymax[7] = 32'h0;
        node_left[7] = 3'd0; node_right[7] = 3'd0;
        node_leaf[7] = 1'b0; node_prim[7]  = 8'd0;
    end

    // ── Extraer ray components ─────────────────────────────────
    wire signed [31:0] ray_ox = ray_token[127:96];
    wire signed [31:0] ray_oy = ray_token[95:64];
    wire signed [31:0] ray_dx = ray_token[63:32];
    wire signed [31:0] ray_dy = ray_token[31:0];

    // ── Reciprocal LUT ─────────────────────────────────────────
    wire [7:0]  rdx_idx = ray_dx[23:16];
    wire [7:0]  rdy_idx = ray_dy[23:16];
    wire [31:0] inv_dx, inv_dy;

    reciprocal_lut u_recip_x (.index(rdx_idx), .recip_q1616(inv_dx));
    reciprocal_lut u_recip_y (.index(rdy_idx), .recip_q1616(inv_dy));

    // ── AABB intersector instancia ────────────────────────────
    reg  signed [31:0] test_xmin, test_ymin, test_xmax, test_ymax;
    wire               aabb_hit;
    wire signed [31:0] aabb_tmin, aabb_tmax;

    aabb_intersect_2d u_aabb (
        .ray_ox(ray_ox), .ray_oy(ray_oy),
        .inv_dx(inv_dx), .inv_dy(inv_dy),
        .box_xmin(test_xmin), .box_ymin(test_ymin),
        .box_xmax(test_xmax), .box_ymax(test_ymax),
        .hit(aabb_hit), .tmin_out(aabb_tmin), .tmax_out(aabb_tmax)
    );

    // ── DFS Stack ─────────────────────────────────────────────
    localparam [2:0] STACK_MAX = BVH_DEPTH - 1; // FIX: 3-bit bound para comparación segura
    reg [2:0]  stack     [0:BVH_DEPTH-1];
    reg [2:0]  stack_ptr;
    reg [2:0]  cur_node;

    // ── FSM ───────────────────────────────────────────────────
    localparam ST_IDLE   = 3'd0;
    localparam ST_PUSH   = 3'd1;
    localparam ST_TEST   = 3'd2;
    localparam ST_WAIT   = 3'd3;
    localparam ST_LEAF   = 3'd4;
    localparam ST_POP    = 3'd5;
    localparam ST_MISS   = 3'd6;

    reg [2:0] state;
    reg [DATA_WIDTH-1:0] saved_ray;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            ray_ready     <= 1'b1;
            hit_valid     <= 1'b0;
            miss_valid    <= 1'b0;
            nodes_tested  <= 16'd0;
            hits_total    <= 16'd0;
            misses_total  <= 16'd0;
            stack_ptr     <= 3'd0;
            cur_node      <= 3'd0;
            test_xmin     <= 32'sd0;
            test_ymin     <= 32'sd0;
            test_xmax     <= 32'sd0;
            test_ymax     <= 32'sd0;
            // FIX: unrolled loop — avoids integer loop variable in sequential always
            stack[0] <= 3'd0; stack[1] <= 3'd0; stack[2] <= 3'd0; stack[3] <= 3'd0;
            stack[4] <= 3'd0; stack[5] <= 3'd0; stack[6] <= 3'd0; stack[7] <= 3'd0;
        end else begin
            hit_valid  <= 1'b0;
            miss_valid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    ray_ready <= 1'b1;
                    if (ray_valid) begin
                        saved_ray    <= ray_token;
                        ray_ready    <= 1'b0;
                        cur_node     <= 3'd0;
                        stack_ptr    <= 3'd0;
                        nodes_tested <= 16'd0; // FIX: reset por ray, no acumulado global
                        state        <= ST_PUSH;
                    end
                end

                ST_PUSH: begin
                    test_xmin <= node_xmin[cur_node];
                    test_ymin <= node_ymin[cur_node];
                    test_xmax <= node_xmax[cur_node];
                    test_ymax <= node_ymax[cur_node];
                    state     <= ST_WAIT;
                end

                ST_WAIT: begin
                    state <= ST_TEST;
                end

                ST_TEST: begin
                    nodes_tested <= nodes_tested + 16'd1;
                    if (aabb_hit) begin
                        if (node_leaf[cur_node]) begin
                            state <= ST_LEAF;
                        end else begin
                            if (stack_ptr < STACK_MAX) begin  // FIX: comparación 3-bit vs 3-bit
                                stack[stack_ptr] <= node_right[cur_node];
                                stack_ptr        <= stack_ptr + 3'd1;
                            end
                            cur_node <= node_left[cur_node];
                            state    <= ST_PUSH;
                        end
                    end else begin
                        state <= ST_POP;
                    end
                end

                ST_LEAF: begin
                    hit_valid   <= 1'b1;
                    hit_prim_id <= node_prim[cur_node];
                    hit_t       <= aabb_tmin;
                    hit_token   <= saved_ray;
                    hits_total  <= hits_total + 16'd1;
                    state       <= ST_POP;
                end

                ST_POP: begin
                    if (stack_ptr > 3'd0) begin
                        stack_ptr <= stack_ptr - 3'd1;
                        cur_node  <= stack[stack_ptr - 3'd1];
                        state     <= ST_PUSH;
                    end else begin
                        state <= ST_MISS;
                    end
                end

                ST_MISS: begin
                    miss_valid   <= 1'b1;
                    misses_total <= misses_total + 16'd1;
                    ray_ready    <= 1'b1;
                    state        <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule