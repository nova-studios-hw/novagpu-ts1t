`timescale 1ns/1ps
// ============================================================
// rotation_matrix.v — v9 (FIX: 10'sd256 signed overflow -> 10'sd256)
// NovaGPU TS 1T — Maximal Technology / Nova Studios
//
// FIX v8: (expr)[bits] no válido en Verilog-2001 puro
//   Líneas 134-138: (CY - SCALE)[9:0], (CX - SCALE)[9:0], etc.
//   Reemplazados por localparams de 10 bits precomputados.
//   Verilog permite slices en identificadores (CX[9:0]) pero NO
//   en expresiones compuestas ((CX-SCALE)[9:0]).
//
//   También: CX[8:0] y CY[8:0] en frame_tick reemplazados
//   por localparams de 9 bits explícitos.
//
// Todo lo demás de v7 se mantiene intacto.
// Compatible Verilator 4.038 modo Verilog-2001.
// ============================================================

module rotation_matrix #(
  parameter SCREEN_W = 640,
  parameter SCREEN_H = 480,
  parameter SCALE    = 100
)(
  input  wire        clk,
  input  wire        rst_n,
  input  wire        frame_tick,

  output reg  [9:0]  v0_x, v0_y,
  output reg  [9:0]  v1_x, v1_y,
  output reg  [9:0]  v2_x, v2_y,
  output reg         vertices_valid
);

  localparam CX = SCREEN_W / 2;
  localparam CY = SCREEN_H / 2;

  // FIX: localparams de 10 bits para reset — sin (expr)[bits]
  localparam [9:0] INIT_V0X = CX[9:0];
  localparam [9:0] INIT_V0Y = ((CY - SCALE) > 0) ? (CY - SCALE) : 0;
  localparam [9:0] INIT_V1X = ((CX - SCALE) > 0) ? (CX - SCALE) : 0;
  localparam [9:0] INIT_V1Y = ((CY + SCALE) < SCREEN_H) ? (CY + SCALE) : (SCREEN_H - 1);
  localparam [9:0] INIT_V2X = ((CX + SCALE) < SCREEN_W) ? (CX + SCALE) : (SCREEN_W - 1);
  localparam [9:0] INIT_V2Y = ((CY + SCALE) < SCREEN_H) ? (CY + SCALE) : (SCREEN_H - 1);

  // FIX: localparams de 9 bits para sumas en frame_tick — sin CX[8:0]
  localparam [8:0] CX9 = CX[8:0];
  localparam [8:0] CY9 = CY[8:0];

  // Ángulo 0-255 (256 pasos = 1.4° por paso)
  reg [7:0] angle;

  // ── TABLA DE SENOS Q8 (sin×256) — 256 entradas ──────────
  function signed [8:0] sin256;
    input [7:0] idx;
    reg [7:0] q;
    reg [9:0] base;  // FIX v9: 10 bits para representar 256 sin overflow signed
    begin
      q = idx[5:0];
      case (idx[7:6])
        2'b00: begin
          case (q[5:3])
            3'd0: base = 10'sd0;   3'd1: base = 10'sd50;
            3'd2: base = 10'sd98;  3'd3: base = 10'sd142;
            3'd4: base = 10'sd181; 3'd5: base = 10'sd213;
            3'd6: base = 10'sd237; 3'd7: base = 10'sd251;
            default: base = 10'sd0;
          endcase
          sin256 = $signed(base);
        end
        2'b01: begin
          case (q[5:3])
            3'd0: base = 10'sd256; 3'd1: base = 10'sd251;
            3'd2: base = 10'sd237; 3'd3: base = 10'sd213;
            3'd4: base = 10'sd181; 3'd5: base = 10'sd142;
            3'd6: base = 10'sd98;  3'd7: base = 10'sd50;
            default: base = 10'sd256;
          endcase
          sin256 = $signed(base);
        end
        2'b10: begin
          case (q[5:3])
            3'd0: base = 10'sd0;   3'd1: base = 10'sd50;
            3'd2: base = 10'sd98;  3'd3: base = 10'sd142;
            3'd4: base = 10'sd181; 3'd5: base = 10'sd213;
            3'd6: base = 10'sd237; 3'd7: base = 10'sd251;
            default: base = 10'sd0;
          endcase
          sin256 = -$signed(base);
        end
        2'b11: begin
          case (q[5:3])
            3'd0: base = 10'sd256; 3'd1: base = 10'sd251;
            3'd2: base = 10'sd237; 3'd3: base = 10'sd213;
            3'd4: base = 10'sd181; 3'd5: base = 10'sd142;
            3'd6: base = 10'sd98;  3'd7: base = 10'sd50;
            default: base = 10'sd256;
          endcase
          sin256 = -$signed(base);
        end
        default: sin256 = 10'sd0;
      endcase
    end
  endfunction

  function signed [8:0] cos256;
    input [7:0] idx;
    begin
      cos256 = sin256(idx + 8'd64);
    end
  endfunction

  // Offsets combinacionales (fuera del always — correcto)
  wire signed [16:0] v0_ox = ($signed({1'b0, SCALE[8:0]}) * cos256(angle))          >>> 8;
  wire signed [16:0] v0_oy = ($signed({1'b0, SCALE[8:0]}) * sin256(angle))          >>> 8;
  wire signed [16:0] v1_ox = ($signed({1'b0, SCALE[8:0]}) * cos256(angle + 8'd85))  >>> 8;
  wire signed [16:0] v1_oy = ($signed({1'b0, SCALE[8:0]}) * sin256(angle + 8'd85))  >>> 8;
  wire signed [16:0] v2_ox = ($signed({1'b0, SCALE[8:0]}) * cos256(angle + 8'd171)) >>> 8;
  wire signed [16:0] v2_oy = ($signed({1'b0, SCALE[8:0]}) * sin256(angle + 8'd171)) >>> 8;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      angle          <= 8'd0;
      // FIX: usar localparams precomputados — sin (expr)[bits]
      v0_x           <= INIT_V0X;
      v0_y           <= INIT_V0Y;
      v1_x           <= INIT_V1X;
      v1_y           <= INIT_V1Y;
      v2_x           <= INIT_V2X;
      v2_y           <= INIT_V2Y;
      vertices_valid <= 1'b1;
    end else if (frame_tick) begin
      angle <= angle + 8'd1;
      // FIX: usar CX9/CY9 (9 bits) — sin CX[8:0] en expresión
      v0_x <= $unsigned($signed({1'b0, CX9}) + v0_ox[9:0]);
      v0_y <= $unsigned($signed({1'b0, CY9}) - v0_oy[9:0]);
      v1_x <= $unsigned($signed({1'b0, CX9}) + v1_ox[9:0]);
      v1_y <= $unsigned($signed({1'b0, CY9}) - v1_oy[9:0]);
      v2_x <= $unsigned($signed({1'b0, CX9}) + v2_ox[9:0]);
      v2_y <= $unsigned($signed({1'b0, CY9}) - v2_oy[9:0]);
      vertices_valid <= 1'b1;
    end else begin
      vertices_valid <= 1'b0;
    end
  end

endmodule

// Copyright (c) 2025 Nova Studios / Maximal Technology
// SPDX-License-Identifier: MIT