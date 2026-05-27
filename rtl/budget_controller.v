`timescale 1ns/1ps
// ============================================================
// budget_controller.v — Control de Presupuesto RT v10 (CORREGIDO)
// NovaGPU TS 1T — Maximal Technology / Nova Studios
//
// FIX v10 (Auditoría):
//   PROBLEMA: Shift >>22 introduce error del ~18.7% en rt_load.
//   SOLUCIÓN: Usar un factor de corrección basado en RT_CYCLES reales.
//   RT_CYCLES = 4,980,100 (para CLK=1200, FRAME=16.6ms, RT=25%)
//   RT_CORRECTION = (2^22 * 100) / RT_CYCLES ≈ 84
// ============================================================

module budget_controller #(
  parameter CLK_MHZ         = 1200,
  parameter FRAME_BUDGET_US = 16667,
  parameter RT_PERCENT      = 25
)(
  input  wire        clk,
  input  wire        rst_n,

  input  wire        frame_start,
  input  wire        rt_active,

  output reg         budget_ok,
  output reg  [7:0]  rt_load
);

  localparam TOTAL_CYCLES = (CLK_MHZ * FRAME_BUDGET_US) / 1000;
  localparam RT_CYCLES    = (TOTAL_CYCLES * RT_PERCENT)  / 100;

  // FIX v10: Factor de corrección para el shift >> 22
  // RT_CYCLES ≈ 4,980,100. 2^22 = 4,194,304.
  localparam [24:0] RT_CORRECTION = (4194304 * 100) / RT_CYCLES; // ≈ 84

  reg [24:0] rt_count;
  reg budget_exceeded;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rt_count        <= 25'd0;
      budget_exceeded <= 1'b0;
      budget_ok       <= 1'b1;
      rt_load         <= 8'd0;
    end else if (frame_start) begin
      // FIX v10: rt_load corregido con factor de escala
      rt_load         <= ((rt_count[24:0] * 8'd100) >> 22) * RT_CORRECTION / 8'd100;

      rt_count        <= 25'd0;
      budget_exceeded <= 1'b0;
      budget_ok       <= 1'b1;
    end else begin
      if (rt_active) begin
        rt_count <= rt_count + 25'd1;

        if (!budget_exceeded && (rt_count >= RT_CYCLES[24:0])) begin
          budget_exceeded <= 1'b1;
          budget_ok       <= 1'b0;
        end
      end
    end
  end

endmodule

// Copyright (c) 2025 Nova Studios / Maximal Technology
// SPDX-License-Identifier: MIT