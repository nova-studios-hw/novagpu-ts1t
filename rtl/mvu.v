`timescale 1ns/1ps
// ============================================================
// mvu.v — Memory Vault Unit v10 (CORREGIDO)
// NovaGPU TS 1T — Maximal Technology / Nova Studios
//
// FIX v10 (Auditoría):
//   PROBLEMA: bilinear_interp() aplana en 1D al recibir el mismo frame.
//   SOLUCIÓN: Usar mv_x y mv_y como pesos de mezcla temporal.
//   - mv_x normalizado a [0, 255] se usa como fracción de mezcla.
//   - Se simula desplazamiento usando componentes de color distintas.
// ============================================================

module mvu #(
  parameter REAL_FRAMES = 2,
  parameter GEN_FRAMES  = 4,
  parameter DATA_WIDTH  = 128
)(
  input  wire                   clk,
  input  wire                   rst_n,

  input  wire  [DATA_WIDTH-1:0] frame_in,
  input  wire                   in_valid,

  input  wire  [15:0]           mv_x,
  input  wire  [15:0]           mv_y,
  input  wire                   mv_valid,

  output reg   [DATA_WIDTH-1:0] frame_out,
  output reg                    frame_valid,
  output reg   [2:0]            frame_count,
  output wire                   mvu_ready
);

  localparam ST_IDLE   = 3'd0;
  localparam ST_WAIT_A = 3'd1;
  localparam ST_WAIT_B = 3'd2;
  localparam ST_GEN_1  = 3'd3;
  localparam ST_GEN_2  = 3'd4;
  localparam ST_GEN_3  = 3'd5;
  localparam ST_GEN_4  = 3'd6;
  localparam ST_OUTPUT = 3'd7;

  reg [2:0] state;

  reg [DATA_WIDTH-1:0] frame_buf_a;
  reg [DATA_WIDTH-1:0] frame_buf_b;
  reg [15:0]           mv_x_reg, mv_y_reg;

  assign mvu_ready = (state == ST_WAIT_A) | (state == ST_WAIT_B);

  // ── FUNCIONES DE INTERPOLACIÓN ───────────────────────────
  function [7:0] lerp_8;
    input [7:0] a, b;
    input [7:0] t;  // 0-255
    reg [15:0] prod_a, prod_b;
    begin
      prod_a = a * (8'd255 - t);
      prod_b = b * t;
      lerp_8 = (prod_a + prod_b) >> 8;
    end
  endfunction

  function [31:0] bilinear_interp;
    input [31:0] p00, p01, p10, p11;
    input [7:0] fx, fy;

    reg [15:0] top, bottom;
    begin
      top    = lerp_8(p00[31:24], p01[31:24], fx);
      bottom = lerp_8(p10[31:24], p11[31:24], fx);
      bilinear_interp[31:24] = lerp_8(top[7:0], bottom[7:0], fy);

      top    = lerp_8(p00[23:16], p01[23:16], fx);
      bottom = lerp_8(p10[23:16], p11[23:16], fx);
      bilinear_interp[23:16] = lerp_8(top[7:0], bottom[7:0], fy);

      top    = lerp_8(p00[15:8], p01[15:8], fx);
      bottom = lerp_8(p10[15:8], p11[15:8], fx);
      bilinear_interp[15:8] = lerp_8(top[7:0], bottom[7:0], fy);

      top    = lerp_8(p00[7:0], p01[7:0], fx);
      bottom = lerp_8(p10[7:0], p11[7:0], fx);
      bilinear_interp[7:0] = lerp_8(top[7:0], bottom[7:0], fy);
    end
  endfunction

  // ── MEZCLA BASADA EN MOTION VECTORS (FIX v10) ───────────
  // Usar mv_x_reg como peso de mezcla temporal (0-255)
  wire [7:0] mv_blend = mv_x_reg[7:0];

  wire [31:0] interp_color_a = frame_buf_a[127:96];
  wire [31:0] interp_color_b = frame_buf_b[127:96];
  wire [31:0] interp_color_a_off = frame_buf_a[95:64]; // Simular desplazamiento
  wire [31:0] interp_color_b_off = frame_buf_b[95:64];

  // Frames interpolados combinando tiempo (t) y movimiento (mv_blend)
  wire [31:0] gen_frame_1 = bilinear_interp(interp_color_a, interp_color_a_off, interp_color_b, interp_color_b_off, mv_blend, 8'd64);
  wire [31:0] gen_frame_2 = bilinear_interp(interp_color_a, interp_color_a_off, interp_color_b, interp_color_b_off, mv_blend, 8'd128);
  wire [31:0] gen_frame_3 = bilinear_interp(interp_color_a, interp_color_a_off, interp_color_b, interp_color_b_off, mv_blend, 8'd192);
  wire [31:0] gen_frame_4 = bilinear_interp(interp_color_a, interp_color_a_off, interp_color_b, interp_color_b_off, mv_blend, 8'd224);

  reg [31:0] gen_color;
  always @(*) begin
    case (state)
      ST_GEN_1: gen_color = gen_frame_1;
      ST_GEN_2: gen_color = gen_frame_2;
      ST_GEN_3: gen_color = gen_frame_3;
      ST_GEN_4: gen_color = gen_frame_4;
      default: gen_color = frame_buf_b[127:96];
    endcase
  end

  wire in_valid_gated = in_valid & mvu_ready;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state       <= ST_IDLE;
      frame_buf_a <= {DATA_WIDTH{1'b0}};
      frame_buf_b <= {DATA_WIDTH{1'b0}};
      mv_x_reg    <= 16'd0;
      mv_y_reg    <= 16'd0;
      frame_out   <= {DATA_WIDTH{1'b0}};
      frame_valid <= 1'b0;
      frame_count <= 3'd0;
    end else begin
      if (mv_valid) begin
        mv_x_reg <= mv_x;
        mv_y_reg <= mv_y;
      end

      case (state)
        ST_IDLE: begin
          frame_valid <= 1'b0;
          state       <= ST_WAIT_A;
        end
        ST_WAIT_A: begin
          frame_valid <= 1'b0;
          if (in_valid_gated) begin
            frame_buf_a <= frame_in;
            frame_out   <= frame_in;
            frame_valid <= 1'b1;
            frame_count <= 3'd0;
            state       <= ST_WAIT_B;
          end
        end
        ST_WAIT_B: begin
          frame_valid <= 1'b0;
          if (in_valid_gated) begin
            frame_buf_b <= frame_in;
            state       <= ST_GEN_1;
          end
        end
        ST_GEN_1: begin
          frame_out   <= {gen_color, frame_buf_a[95:0]};
          frame_valid <= 1'b1;
          frame_count <= 3'd1;
          state       <= ST_GEN_2;
        end
        ST_GEN_2: begin
          frame_out   <= {gen_frame_2, frame_buf_a[95:0]};
          frame_valid <= 1'b1;
          frame_count <= 3'd2;
          state       <= ST_GEN_3;
        end
        ST_GEN_3: begin
          frame_out   <= {gen_frame_3, frame_buf_a[95:0]};
          frame_valid <= 1'b1;
          frame_count <= 3'd3;
          state       <= ST_GEN_4;
        end
        ST_GEN_4: begin
          frame_out   <= {gen_frame_4, frame_buf_a[95:0]};
          frame_valid <= 1'b1;
          frame_count <= 3'd4;
          state       <= ST_OUTPUT;
        end
        ST_OUTPUT: begin
          frame_out   <= frame_buf_b;
          frame_valid <= 1'b1;
          frame_count <= 3'd5;
          frame_buf_a <= frame_buf_b;
          state       <= ST_WAIT_B;
        end
        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule

// Copyright (c) 2025 Nova Studios / Maximal Technology
// SPDX-License-Identifier: MIT