`timescale 1ns/1ps
// ============================================================
// bvh_real.v — BVH Traversal Real v12.0 (Equipo Alpha)
// NovaGPU TS 1T — Nova Studios
//
// FIX v12 — Bug crítico de extracción de ray token:
//   PROBLEMA: v11 extraía ox/oy como {16'h0, token[127:112]} (16-bit
//   zero-extended). Resultado: ox=21 decimal cuando la AABB tiene
//   coordenadas en Q16.16 (mínimo 0x00050000=327680). NUNCA había hit.
//   SOLUCIÓN: Extraer componentes completos de 32 bits por campo.
//   Nuevo layout del token:
//     [127:96] = ray_ox  (Q16.16 completo)
//     [95:64]  = ray_oy  (Q16.16 completo)
//     [63:32]  = ray_dx  (Q16.16 completo)
//     [31:0]   = ray_dy  (Q16.16 completo)
//   ray_oz = 32'sh00000000 (constante, escena 2.5D)
//   ray_dz = 32'sh00010000 = 1.0 (constante)
// ============================================================

// ── AABB 3D INTERSECT ────────────────────────────────────────
module aabb_intersect_3d (
  input  wire signed [31:0] ray_ox, ray_oy, ray_oz,
  input  wire signed [31:0] inv_dx, inv_dy, inv_dz,
  input  wire signed [31:0] box_min_x, box_min_y, box_min_z,
  input  wire signed [31:0] box_max_x, box_max_y, box_max_z,
  output wire               hit,
  output wire signed [31:0] tmin_out,
  output wire signed [31:0] tmax_out
);
  wire dx_zero = (inv_dx == 32'h7FFFFFFF);
  wire dy_zero = (inv_dy == 32'h7FFFFFFF);
  wire dz_zero = (inv_dz == 32'h7FFFFFFF);

  wire signed [63:0] tx0_f = $signed(box_min_x - ray_ox) * $signed(inv_dx);
  wire signed [63:0] tx1_f = $signed(box_max_x - ray_ox) * $signed(inv_dx);
  wire signed [63:0] ty0_f = $signed(box_min_y - ray_oy) * $signed(inv_dy);
  wire signed [63:0] ty1_f = $signed(box_max_y - ray_oy) * $signed(inv_dy);
  wire signed [63:0] tz0_f = $signed(box_min_z - ray_oz) * $signed(inv_dz);
  wire signed [63:0] tz1_f = $signed(box_max_z - ray_oz) * $signed(inv_dz);

  wire signed [31:0] tx0 = tx0_f[47:16];
  wire signed [31:0] tx1 = tx1_f[47:16];
  wire signed [31:0] ty0 = ty0_f[47:16];
  wire signed [31:0] ty1 = ty1_f[47:16];
  wire signed [31:0] tz0 = tz0_f[47:16];
  wire signed [31:0] tz1 = tz1_f[47:16];

  wire signed [31:0] tmin_x = (tx0 < tx1) ? tx0 : tx1;
  wire signed [31:0] tmax_x = (tx0 > tx1) ? tx0 : tx1;
  wire signed [31:0] tmin_y = (ty0 < ty1) ? ty0 : ty1;
  wire signed [31:0] tmax_y = (ty0 > ty1) ? ty0 : ty1;
  wire signed [31:0] tmin_z = (tz0 < tz1) ? tz0 : tz1;
  wire signed [31:0] tmax_z = (tz0 > tz1) ? tz0 : tz1;

  wire signed [31:0] tmin_xy  = (tmin_x > tmin_y)  ? tmin_x  : tmin_y;
  wire signed [31:0] tmin_xyz = (tmin_xy > tmin_z)  ? tmin_xy : tmin_z;
  wire signed [31:0] tmax_xy  = (tmax_x  < tmax_y)  ? tmax_x  : tmax_y;
  wire signed [31:0] tmax_xyz = (tmax_xy < tmax_z)  ? tmax_xy : tmax_z;

  wire hit_x = dx_zero ? (ray_ox >= box_min_x && ray_ox <= box_max_x) : 1'b1;
  wire hit_y = dy_zero ? (ray_oy >= box_min_y && ray_oy <= box_max_y) : 1'b1;
  wire hit_z = dz_zero ? (ray_oz >= box_min_z && ray_oz <= box_max_z) : 1'b1;

  // tmin/tmax efectivos excluyendo ejes degenerados
  wire signed [31:0] tmin_eff_xy = dx_zero ? tmin_y : (dy_zero ? tmin_x : tmin_xy);
  wire signed [31:0] tmin_eff    = dz_zero ? tmin_eff_xy : ((dx_zero && dy_zero) ? tmin_z : tmin_xyz);
  wire signed [31:0] tmax_eff_xy = dx_zero ? tmax_y : (dy_zero ? tmax_x : tmax_xy);
  wire signed [31:0] tmax_eff    = dz_zero ? tmax_eff_xy : ((dx_zero && dy_zero) ? tmax_z : tmax_xyz);

  assign tmin_out = tmin_eff;
  assign tmax_out = tmax_eff;
  assign hit = hit_x && hit_y && hit_z &&
               (tmin_eff <= tmax_eff) && (tmax_eff >= 32'sd0);
endmodule


// ── BVH NODE ROM ─────────────────────────────────────────────
module bvh_node_rom (
  input  wire [2:0]          node_idx,
  output reg  signed [31:0]  min_x, min_y, min_z,
  output reg  signed [31:0]  max_x, max_y, max_z,
  output reg  [2:0]          child_left,
  output reg  [2:0]          child_right,
  output reg                 leaf,
  output reg  [3:0]          prim_id
);
  always @(*) begin
    case (node_idx)
      3'd0: begin // ROOT
        min_x=32'sh00000000; min_y=32'sh00000000; min_z=32'shFFFE0000;
        max_x=32'sh00300000; max_y=32'sh00200000; max_z=32'sh00020000;
        child_left=3'd1; child_right=3'd2; leaf=1'b0; prim_id=4'd15;
      end
      3'd1: begin // Interior izquierdo
        min_x=32'sh00000000; min_y=32'sh00000000; min_z=32'shFFFE0000;
        max_x=32'sh00180000; max_y=32'sh00200000; max_z=32'sh00020000;
        child_left=3'd3; child_right=3'd4; leaf=1'b0; prim_id=4'd15;
      end
      3'd2: begin // Interior derecho
        min_x=32'sh00180000; min_y=32'sh00000000; min_z=32'shFFFE0000;
        max_x=32'sh00300000; max_y=32'sh00200000; max_z=32'sh00020000;
        child_left=3'd5; child_right=3'd6; leaf=1'b0; prim_id=4'd15;
      end
      3'd3: begin // HOJA: Objeto 0 cubo central
        min_x=32'sh00050000; min_y=32'sh00050000; min_z=32'shFFFF0000;
        max_x=32'sh00250000; max_y=32'sh00250000; max_z=32'sh00010000;
        child_left=3'd0; child_right=3'd0; leaf=1'b1; prim_id=4'd0;
      end
      3'd4: begin // HOJA: Objeto 1 caja izquierda
        min_x=32'sh00020000; min_y=32'sh00100000; min_z=32'shFFFF8000;
        max_x=32'sh00080000; max_y=32'sh00180000; max_z=32'sh00008000;
        child_left=3'd0; child_right=3'd0; leaf=1'b1; prim_id=4'd1;
      end
      3'd5: begin // HOJA: Objeto 2 caja derecha
        min_x=32'sh00280000; min_y=32'sh00100000; min_z=32'shFFFF8000;
        max_x=32'sh002E0000; max_y=32'sh00180000; max_z=32'sh00008000;
        child_left=3'd0; child_right=3'd0; leaf=1'b1; prim_id=4'd2;
      end
      3'd6: begin // HOJA: Objeto 3 plataforma
        min_x=32'sh00000000; min_y=32'sh001E0000; min_z=32'shFFFE0000;
        max_x=32'sh00300000; max_y=32'sh00200000; max_z=32'sh00020000;
        child_left=3'd0; child_right=3'd0; leaf=1'b1; prim_id=4'd3;
      end
      default: begin
        min_x=32'sh7FFFFFFF; min_y=32'sh7FFFFFFF; min_z=32'sh7FFFFFFF;
        max_x=32'sh80000000; max_y=32'sh80000000; max_z=32'sh80000000;
        child_left=3'd0; child_right=3'd0; leaf=1'b1; prim_id=4'd15;
      end
    endcase
  end
endmodule


// ── BVH TRAVERSAL CON STACK HARDWARE ─────────────────────────
module bvh_traversal_real #(
  parameter BVH_DEPTH   = 8,
  parameter DATA_WIDTH  = 128,
  parameter STACK_DEPTH = 8
)(
  input  wire                   clk,
  input  wire                   rst_n,
  input  wire  [DATA_WIDTH-1:0] ray_token,
  input  wire                   ray_valid,
  output reg   [DATA_WIDTH-1:0] hit_color,
  output reg   [31:0]           hit_depth,
  output reg                    hit_valid,
  output reg                    hit_miss
);

  // ── FIX v12: Extraer componentes completos de 32 bits ───
  // Token layout: [127:96]=ox, [95:64]=oy, [63:32]=dx, [31:0]=dy (Q16.16)
  wire signed [31:0] ray_ox = $signed(ray_token[127:96]);
  wire signed [31:0] ray_oy = $signed(ray_token[95:64]);
  wire signed [31:0] ray_oz = 32'sh00000000;          // constante: z=0
  wire signed [31:0] ray_dx = $signed(ray_token[63:32]);
  wire signed [31:0] ray_dy = $signed(ray_token[31:0]);
  wire signed [31:0] ray_dz = 32'sh00010000;          // constante: dz=1.0

  wire [31:0] inv_dx, inv_dy, inv_dz;
  reciprocal_lut u_lut_dx (.index(ray_dx[9:0]), .reciprocal(inv_dx), .dividend(ray_dx));
  reciprocal_lut u_lut_dy (.index(ray_dy[9:0]), .reciprocal(inv_dy), .dividend(ray_dy));
  reciprocal_lut u_lut_dz (.index(ray_dz[9:0]), .reciprocal(inv_dz), .dividend(ray_dz));

  // ROM interface
  reg [2:0] rom_idx;
  wire signed [31:0] n_min_x, n_min_y, n_min_z;
  wire signed [31:0] n_max_x, n_max_y, n_max_z;
  wire [2:0]  n_child_l, n_child_r;
  wire        n_leaf;
  wire [3:0]  n_prim_id;

  bvh_node_rom u_rom (
    .node_idx(rom_idx),
    .min_x(n_min_x), .min_y(n_min_y), .min_z(n_min_z),
    .max_x(n_max_x), .max_y(n_max_y), .max_z(n_max_z),
    .child_left(n_child_l), .child_right(n_child_r),
    .leaf(n_leaf), .prim_id(n_prim_id)
  );

  // AABB 3D intersector
  wire        node_hit;
  wire signed [31:0] node_tmin, node_tmax;

  aabb_intersect_3d u_isect (
    .ray_ox(ray_ox), .ray_oy(ray_oy), .ray_oz(ray_oz),
    .inv_dx(inv_dx), .inv_dy(inv_dy), .inv_dz(inv_dz),
    .box_min_x(n_min_x), .box_min_y(n_min_y), .box_min_z(n_min_z),
    .box_max_x(n_max_x), .box_max_y(n_max_y), .box_max_z(n_max_z),
    .hit(node_hit), .tmin_out(node_tmin), .tmax_out(node_tmax)
  );

  // Hardware stack
  reg [2:0]  stack    [0:STACK_DEPTH-1];
  reg [2:0]  stack_sp;
  reg signed [31:0] closest_t;
  reg [3:0]  closest_prim;
  reg        any_hit_r;

  function [31:0] prim_color;
    input [3:0] pid;
    begin
      case (pid)
        4'd0:    prim_color = 32'hFF4400FF;
        4'd1:    prim_color = 32'h00FF44FF;
        4'd2:    prim_color = 32'h4400FFFF;
        4'd3:    prim_color = 32'h888888FF;
        default: prim_color = 32'h000000FF;
      endcase
    end
  endfunction

  localparam ST_IDLE     = 3'd0;
  localparam ST_PUSH     = 3'd1;
  localparam ST_POP      = 3'd2;
  localparam ST_TEST     = 3'd3;
  localparam ST_LEAF     = 3'd4;
  localparam ST_CHILDREN = 3'd5;
  localparam ST_DONE     = 3'd6;

  reg [2:0]  state;
  reg [DATA_WIDTH-1:0] ray_token_r;

  reg [DATA_WIDTH-1:0] pipe_color [0:BVH_DEPTH-1];
  reg                  pipe_valid [0:BVH_DEPTH-1];
  reg                  pipe_miss  [0:BVH_DEPTH-1];
  reg [31:0]           pipe_depth [0:BVH_DEPTH-1];

  integer pi;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state        <= ST_IDLE;
      stack_sp     <= 3'd0;
      closest_t    <= 32'h7FFFFFFF;
      closest_prim <= 4'd15;
      any_hit_r    <= 1'b0;
      rom_idx      <= 3'd0;
      ray_token_r  <= {DATA_WIDTH{1'b0}};
      hit_valid    <= 1'b0;
      hit_miss     <= 1'b1;
      hit_color    <= {DATA_WIDTH{1'b0}};
      hit_depth    <= 32'hFFFFFFFF;
      for (pi = 0; pi < BVH_DEPTH; pi = pi + 1) begin
        pipe_color[pi] <= {DATA_WIDTH{1'b0}};
        pipe_valid[pi] <= 1'b0;
        pipe_miss[pi]  <= 1'b1;
        pipe_depth[pi] <= 32'hFFFFFFFF;
      end
    end else begin
      // Fixed-latency output pipeline shift
      for (pi = 1; pi < BVH_DEPTH; pi = pi + 1) begin
        pipe_color[pi] <= pipe_color[pi-1];
        pipe_valid[pi] <= pipe_valid[pi-1];
        pipe_miss[pi]  <= pipe_miss[pi-1];
        pipe_depth[pi] <= pipe_depth[pi-1];
      end
      hit_color <= pipe_color[BVH_DEPTH-1];
      hit_valid <= pipe_valid[BVH_DEPTH-1];
      hit_miss  <= pipe_miss[BVH_DEPTH-1];
      hit_depth <= pipe_depth[BVH_DEPTH-1];

      pipe_valid[0] <= 1'b0;
      pipe_miss[0]  <= 1'b1;

      case (state)
        ST_IDLE: begin
          if (ray_valid) begin
            ray_token_r  <= ray_token;
            stack_sp     <= 3'd0;
            closest_t    <= 32'h7FFFFFFF;
            closest_prim <= 4'd15;
            any_hit_r    <= 1'b0;
            state        <= ST_PUSH;
          end
        end
        ST_PUSH: begin
          stack[0] <= 3'd0;
          stack_sp <= 3'd1;
          state    <= ST_POP;
        end
        ST_POP: begin
          if (stack_sp == 3'd0) begin
            state <= ST_DONE;
          end else begin
            stack_sp <= stack_sp - 3'd1;
            rom_idx  <= stack[stack_sp - 3'd1];
            state    <= ST_TEST;
          end
        end
        ST_TEST: begin
          if (!node_hit || (node_tmin >= closest_t)) begin
            state <= ST_POP;
          end else if (n_leaf) begin
            state <= ST_LEAF;
          end else begin
            state <= ST_CHILDREN;
          end
        end
        ST_LEAF: begin
          if (node_tmin < closest_t) begin
            closest_t    <= node_tmin;
            closest_prim <= n_prim_id;
            any_hit_r    <= 1'b1;
          end
          state <= ST_POP;
        end
        ST_CHILDREN: begin
          if (stack_sp < 3'd6) begin
            stack[stack_sp]        <= n_child_r;
            stack[stack_sp + 3'd1] <= n_child_l;
            stack_sp               <= stack_sp + 3'd2;
          end
          state <= ST_POP;
        end
        ST_DONE: begin
          pipe_color[0] <= any_hit_r ?
            {prim_color(closest_prim), ray_token_r[95:0]} :
            {32'h000000FF, ray_token_r[95:0]};
          pipe_valid[0] <= 1'b1;
          pipe_miss[0]  <= ~any_hit_r;
          pipe_depth[0] <= any_hit_r ? closest_t : 32'hFFFFFFFF;
          state         <= ST_IDLE;
        end
        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule

// Copyright (c) 2025 Nova Studios / Maximal Technology
// SPDX-License-Identifier: MIT