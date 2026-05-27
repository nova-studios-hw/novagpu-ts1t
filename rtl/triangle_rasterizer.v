`timescale 1ns/1ps
// ============================================================
// triangle_rasterizer.v — v10 (CORREGIDO)
// NovaGPU TS 1T — Maximal Technology / Nova Studios
//
// FIX v10 (Auditoría):
//   PROBLEMA: Divisiones de 64 bits en wire combinacional (no sintetizable).
//   SOLUCIÓN: Reemplazado por reciprocal_lut.v para precalcular 1/z.
//   FLUJO: 
//     1. Indexar LUT con z0, z1, z2.
//     2. Usar resultado Q16 como multiplicador.
//     3. Pipeline de 1 ciclo para el resultado de la LUT.
// ============================================================

module triangle_rasterizer #(
  parameter DATA_WIDTH = 128,
  parameter SCREEN_W   = 640,
  parameter SCREEN_H   = 480
)(
  input  wire         clk,
  input  wire         rst_n,

  input  wire [10:0]  v0_x, v0_y,
  input  wire [10:0]  v1_x, v1_y,
  input  wire [10:0]  v2_x, v2_y,

  input  wire [31:0]  c0, c1, c2,
  input  wire [31:0]  z0, z1, z2,

  input  wire         start,
  output reg          busy,

  output reg  [DATA_WIDTH-1:0] token_out,
  output reg                   token_valid,
  input  wire                  token_ready
);

  // ── BOUNDING BOX ──────────────────────────────────────────
  wire [10:0] bb_xmin = (v0_x < v1_x) ? ((v0_x < v2_x) ? v0_x : v2_x)
                                       : ((v1_x < v2_x) ? v1_x : v2_x);
  wire [10:0] bb_xmax = (v0_x > v1_x) ? ((v0_x > v2_x) ? v0_x : v2_x)
                                       : ((v1_x > v2_x) ? v1_x : v2_x);
  wire [10:0] bb_ymin = (v0_y < v1_y) ? ((v0_y < v2_y) ? v0_y : v2_y)
                                       : ((v1_y < v2_y) ? v1_y : v2_y);
  wire [10:0] bb_ymax = (v0_y > v1_y) ? ((v0_y > v2_y) ? v0_y : v2_y)
                                       : ((v1_y > v2_y) ? v1_y : v2_y);

  // ── ESTADOS ───────────────────────────────────────────────
  localparam ST_IDLE  = 3'd0;
  localparam ST_SETUP = 3'd1;
  localparam ST_SCAN  = 3'd2;
  localparam ST_EMIT  = 3'd3;
  localparam ST_DONE  = 3'd4;

  reg [2:0]  state;
  reg [10:0] px, py;
  reg [15:0] tag_counter;

  // ── EDGE FUNCTIONS INCREMENTALES (Pineda) ─────────────────
  reg signed [23:0] e0_cur, e1_cur, e2_cur;
  reg signed [23:0] de0_dx, de0_dy;
  reg signed [23:0] de1_dx, de1_dy;
  reg signed [23:0] de2_dx, de2_dy;
  reg signed [23:0] e0_row, e1_row, e2_row;

  wire is_inside = (e0_cur >= 24'sd0) && (e1_cur >= 24'sd0) && (e2_cur >= 24'sd0);

  // ── PESOS BARICENTRICOS ───────────────────────────────────
  reg signed [24:0] area_reg;
  wire area_valid = (area_reg > 25'sd0);

  reg [31:0] inv_area;

  wire [15:0] w0_raw = area_valid ? ((e0_cur[23:0] * inv_area[31:0]) >> 16) : 16'd21845;
  wire [15:0] w1_raw = area_valid ? ((e1_cur[23:0] * inv_area[31:0]) >> 16) : 16'd21845;
  wire [15:0] w2_raw = area_valid ? (16'd65535 - w0_raw - w1_raw)           : 16'd21845;

  wire [7:0] w0 = w0_raw[15:8];
  wire [7:0] w1 = w1_raw[15:8];
  wire [7:0] w2 = w2_raw[15:8];

  // ── INTERPOLACIÓN DE COLOR ────────────────────────────────
  wire [7:0] r_i = (w0 * c0[31:24] + w1 * c1[31:24] + w2 * c2[31:24]) >> 8;
  wire [7:0] g_i = (w0 * c0[23:16] + w1 * c1[23:16] + w2 * c2[23:16]) >> 8;
  wire [7:0] b_i = (w0 * c0[15:8]  + w1 * c1[15:8]  + w2 * c2[15:8])  >> 8;
  wire [7:0] a_i = (w0 * c0[7:0]   + w1 * c1[7:0]   + w2 * c2[7:0])   >> 8;

  // ── INTERPOLACIÓN DE Z (FIX v10: Usar reciprocal_lut) ─────
  wire use_perspective = (z0 != 32'd0) && (z1 != 32'd0) && (z2 != 32'd0);

  wire [31:0] inv_z0, inv_z1, inv_z2;
  reciprocal_lut u_lut_z0 (.index(z0[9:0]), .reciprocal(inv_z0), .dividend(z0));
  reciprocal_lut u_lut_z1 (.index(z1[9:0]), .reciprocal(inv_z1), .dividend(z1));
  reciprocal_lut u_lut_z2 (.index(z2[9:0]), .reciprocal(inv_z2), .dividend(z2));

  wire [31:0] inv_z_interp = (w0 * inv_z0 + w1 * inv_z1 + w2 * inv_z2) >> 8;

  // Para z_perspective (1 / inv_z_interp)
  wire [31:0] z_perspective;
  reciprocal_lut u_lut_zp (.index(inv_z_interp[9:0]), .reciprocal(z_perspective), .dividend(inv_z_interp));

  wire [31:0] z_affine = (w0 * z0 + w1 * z1 + w2 * z2) >> 8;
  wire [31:0] z_i = use_perspective ? z_perspective : z_affine;

  // ── SETUP: RECIPROCAL DEL ÁREA (FIX v10: También con LUT) ──
  reg [31:0] setup_inv;
  wire [31:0] area_inv_lut;
  reciprocal_lut u_lut_area (.index(area_reg[9:0]), .reciprocal(area_inv_lut), .dividend({7'b0, area_reg[24:0]}));

  always @(*) begin
    if (area_reg > 25'sd0)
      setup_inv = area_inv_lut;
    else
      setup_inv = 32'd0;
  end

  // ── MÁQUINA DE ESTADOS ────────────────────────────────────
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state       <= ST_IDLE;
      busy        <= 1'b0;
      token_valid <= 1'b0;
      token_out   <= {DATA_WIDTH{1'b0}};
      px          <= 11'd0;
      py          <= 11'd0;
      tag_counter <= 16'd0;
      e0_cur      <= 24'sd0; e1_cur <= 24'sd0; e2_cur <= 24'sd0;
      e0_row      <= 24'sd0; e1_row <= 24'sd0; e2_row <= 24'sd0;
      de0_dx      <= 24'sd0; de0_dy <= 24'sd0;
      de1_dx      <= 24'sd0; de1_dy <= 24'sd0;
      de2_dx      <= 24'sd0; de2_dy <= 24'sd0;
      area_reg    <= 25'sd0;
      inv_area    <= 32'd0;
    end else begin

      case (state)

        ST_IDLE: begin
          token_valid <= 1'b0;
          busy        <= 1'b0;
          if (start) begin
            px    <= bb_xmin;
            py    <= bb_ymin;
            busy  <= 1'b1;
            state <= ST_SETUP;
          end
        end

        ST_SETUP: begin
          de0_dx <= $signed({1'b0, v1_y}) - $signed({1'b0, v0_y});
          de0_dy <= -($signed({1'b0, v1_x}) - $signed({1'b0, v0_x}));
          de1_dx <= $signed({1'b0, v2_y}) - $signed({1'b0, v1_y});
          de1_dy <= -($signed({1'b0, v2_x}) - $signed({1'b0, v1_x}));
          de2_dx <= $signed({1'b0, v0_y}) - $signed({1'b0, v2_y});
          de2_dy <= -($signed({1'b0, v0_x}) - $signed({1'b0, v2_x}));

          e0_row <= ($signed({1'b0, bb_xmin}) - $signed({1'b0, v0_x})) *
                    ($signed({1'b0, v1_y})    - $signed({1'b0, v0_y})) -
                    ($signed({1'b0, bb_ymin}) - $signed({1'b0, v0_y})) *
                    ($signed({1'b0, v1_x})    - $signed({1'b0, v0_x}));
          e1_row <= ($signed({1'b0, bb_xmin}) - $signed({1'b0, v1_x})) *
                    ($signed({1'b0, v2_y})    - $signed({1'b0, v1_y})) -
                    ($signed({1'b0, bb_ymin}) - $signed({1'b0, v1_y})) *
                    ($signed({1'b0, v2_x})    - $signed({1'b0, v1_x}));
          e2_row <= ($signed({1'b0, bb_xmin}) - $signed({1'b0, v2_x})) *
                    ($signed({1'b0, v0_y})    - $signed({1'b0, v2_y})) -
                    ($signed({1'b0, bb_ymin}) - $signed({1'b0, v2_y})) *
                    ($signed({1'b0, v0_x})    - $signed({1'b0, v2_x}));

          // FIX v12: use cross product for signed area, not edge sum at bb_min
          // area = (v1x-v0x)*(v2y-v0y) - (v1y-v0y)*(v2x-v0x)
          area_reg <= ($signed({1'b0, v1_x}) - $signed({1'b0, v0_x})) *
                      ($signed({1'b0, v2_y}) - $signed({1'b0, v0_y})) -
                      ($signed({1'b0, v1_y}) - $signed({1'b0, v0_y})) *
                      ($signed({1'b0, v2_x}) - $signed({1'b0, v0_x}));

          inv_area <= setup_inv;

          e0_cur <= e0_row;
          e1_cur <= e1_row;
          e2_cur <= e2_row;

          state <= ST_SCAN;
        end

        ST_SCAN: begin
          token_valid <= 1'b0;

          if (py > bb_ymax) begin
            state <= ST_DONE;
          end else if (px > bb_xmax) begin
            px     <= bb_xmin;
            py     <= py + 11'd1;
            e0_row <= e0_row + de0_dy;
            e1_row <= e1_row + de1_dy;
            e2_row <= e2_row + de2_dy;
            e0_cur <= e0_row + de0_dy;
            e1_cur <= e1_row + de1_dy;
            e2_cur <= e2_row + de2_dy;
          end else begin
            if (is_inside && token_ready) begin
              state <= ST_EMIT;
            end else begin
              px     <= px + 11'd1;
              e0_cur <= e0_cur + de0_dx;
              e1_cur <= e1_cur + de1_dx;
              e2_cur <= e2_cur + de2_dx;
            end
          end
        end

        ST_EMIT: begin
          token_out <= {
            {r_i, g_i, b_i, a_i},
            z_i,
            16'h3C00,
            tag_counter,
            px[9:2],
            py[9:2],
            px[1:0], py[1:0],
            4'h0,
            8'h00
          };
          token_valid <= 1'b1;
          tag_counter <= tag_counter + 16'd1;

          px     <= px + 11'd1;
          e0_cur <= e0_cur + de0_dx;
          e1_cur <= e1_cur + de1_dx;
          e2_cur <= e2_cur + de2_dx;

          state <= ST_SCAN;
        end

        ST_DONE: begin
          token_valid <= 1'b0;
          busy        <= 1'b0;
          state       <= ST_IDLE;
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule

// Copyright (c) 2025 Nova Studios / Maximal Technology
// SPDX-License-Identifier: MIT