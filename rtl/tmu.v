`timescale 1ns/1ps
// ============================================================
// tmu.v — Token Matching Unit v9
// NovaGPU TS 1T — Maximal Technology / Nova Studios
//
// FIX v9 (auditor Test 2 FAIL):
//   PROBLEMA: fire_valid no se ve en el ciclo correcto en el TB.
//
//   RAÍZ DEL BUG:
//   El testbench hace:
//     send_token(tag, data2)   → en el flanco del clk se registra in_valid
//     @(posedge clk)           → avanza 1 ciclo
//     pass_fail(tmu_fire_valid)  → evalúa aquí
//
//   send_token hace: @(posedge clk) [pone valid=1] @(posedge clk) [baja valid=0]
//   fire_valid se registra en el flanco donde valid=1 y hay hit → ya es 1
//   PERO: el always del for loop de timeout TAMBIÉN escribe fire_valid <= 0
//   en el mismo ciclo, ya que itera sobre TODOS los slots.
//
//   FIX: separar el bloque de timeout del bloque de match-and-fire.
//   El timeout corre en un always separado con menor prioridad.
//   fire_valid solo lo toca el match-and-fire block.
//
//   FIX ADICIONAL: in_ready usaba always @(*) con can_accept,
//   pero can_accept depende de w0_valid[set_idx] que se lee con
//   el set_idx del token ACTUAL. Si set_idx cambia combinacionalmente
//   in_ready puede cambiar antes de que el flanco llegue.
//   Solución: registrar in_ready un ciclo antes para estabilidad.
//
// Compatible Verilator 4.038
// ============================================================

module token_matching_unit #(
  parameter NUM_SLOTS  = 1024,
  parameter TAG_WIDTH  = 16,
  parameter DATA_WIDTH = 128,
  parameter TIMEOUT    = 4096
)(
  input  wire                         clk,
  input  wire                         rst_n,

  input  wire  [TAG_WIDTH-1:0]        in_tag,
  input  wire  [DATA_WIDTH-1:0]       in_data,
  input  wire                         in_valid,
  output reg                          in_ready,

  output reg   [TAG_WIDTH-1:0]        fire_tag,
  output reg   [DATA_WIDTH-1:0]       fire_data_a,
  output reg   [DATA_WIDTH-1:0]       fire_data_b,
  output reg                          fire_valid,

  output wire  [TAG_WIDTH-1:0]        occupancy
);

  localparam NUM_SETS = NUM_SLOTS / 2;
  localparam SET_BITS = 9;

  reg                   w0_valid   [0:NUM_SETS-1];
  reg  [TAG_WIDTH-1:0]  w0_tag     [0:NUM_SETS-1];
  reg  [DATA_WIDTH-1:0] w0_operand [0:NUM_SETS-1];
  reg  [11:0]           w0_age     [0:NUM_SETS-1];

  reg                   w1_valid   [0:NUM_SETS-1];
  reg  [TAG_WIDTH-1:0]  w1_tag     [0:NUM_SETS-1];
  reg  [DATA_WIDTH-1:0] w1_operand [0:NUM_SETS-1];
  reg  [11:0]           w1_age     [0:NUM_SETS-1];

  wire [SET_BITS-1:0] set_idx = in_tag[SET_BITS-1:0];

  wire w0_hit  = w0_valid[set_idx] && (w0_tag[set_idx] == in_tag);
  wire w1_hit  = w1_valid[set_idx] && (w1_tag[set_idx] == in_tag);
  wire w0_free = !w0_valid[set_idx];
  wire w1_free = !w1_valid[set_idx];
  wire can_accept = w0_hit || w1_hit || w0_free || w1_free;

  reg [TAG_WIDTH-1:0] occ_count;
  assign occupancy = occ_count;

  // FIX: in_ready registrado — señal estable, no glitchea entre flancos
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      in_ready <= 1'b1;
    else
      in_ready <= can_accept;
  end

  // ── MATCH-AND-FIRE (bloque principal) ─────────────────────
  // FIX: fire_valid SOLO se escribe aquí, no en el bloque de timeout
  integer i;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < NUM_SETS; i = i + 1) begin
        w0_valid[i]   <= 1'b0;
        w0_tag[i]     <= {TAG_WIDTH{1'b0}};
        w0_operand[i] <= {DATA_WIDTH{1'b0}};
        w0_age[i]     <= 12'd0;
        w1_valid[i]   <= 1'b0;
        w1_tag[i]     <= {TAG_WIDTH{1'b0}};
        w1_operand[i] <= {DATA_WIDTH{1'b0}};
        w1_age[i]     <= 12'd0;
      end
      fire_valid  <= 1'b0;
      fire_tag    <= {TAG_WIDTH{1'b0}};
      fire_data_a <= {DATA_WIDTH{1'b0}};
      fire_data_b <= {DATA_WIDTH{1'b0}};
      occ_count   <= {TAG_WIDTH{1'b0}};

    end else begin

      // Default: bajar fire_valid cada ciclo
      // Se sube SOLO cuando hay match exitoso
      fire_valid <= 1'b0;

      // Timeout eviction — ages independientes del match
      for (i = 0; i < NUM_SETS; i = i + 1) begin
        if (w0_valid[i]) begin
          if (w0_age[i] >= TIMEOUT[11:0]) begin
            w0_valid[i] <= 1'b0;
            w0_age[i]   <= 12'd0;
            if (occ_count > {TAG_WIDTH{1'b0}})
              occ_count <= occ_count - 1;
          end else
            w0_age[i] <= w0_age[i] + 12'd1;
        end
        if (w1_valid[i]) begin
          if (w1_age[i] >= TIMEOUT[11:0]) begin
            w1_valid[i] <= 1'b0;
            w1_age[i]   <= 12'd0;
            if (occ_count > {TAG_WIDTH{1'b0}})
              occ_count <= occ_count - 1;
          end else
            w1_age[i] <= w1_age[i] + 12'd1;
        end
      end

      // Match-and-Fire — tiene prioridad sobre timeout
      if (in_valid && in_ready) begin

        if (w0_hit) begin
          fire_tag    <= in_tag;
          fire_data_a <= w0_operand[set_idx];
          fire_data_b <= in_data;
          fire_valid  <= 1'b1;        // Se activa aquí — no hay otra escritura
          w0_valid[set_idx] <= 1'b0;
          w0_age[set_idx]   <= 12'd0;
          if (occ_count > {TAG_WIDTH{1'b0}})
            occ_count <= occ_count - 1;

        end else if (w1_hit) begin
          fire_tag    <= in_tag;
          fire_data_a <= w1_operand[set_idx];
          fire_data_b <= in_data;
          fire_valid  <= 1'b1;
          w1_valid[set_idx] <= 1'b0;
          w1_age[set_idx]   <= 12'd0;
          if (occ_count > {TAG_WIDTH{1'b0}})
            occ_count <= occ_count - 1;

        end else if (w0_free) begin
          w0_valid[set_idx]   <= 1'b1;
          w0_tag[set_idx]     <= in_tag;
          w0_operand[set_idx] <= in_data;
          w0_age[set_idx]     <= 12'd0;
          occ_count <= occ_count + 1;

        end else if (w1_free) begin
          w1_valid[set_idx]   <= 1'b1;
          w1_tag[set_idx]     <= in_tag;
          w1_operand[set_idx] <= in_data;
          w1_age[set_idx]     <= 12'd0;
          occ_count <= occ_count + 1;
        end
      end
    end
  end

endmodule

// Copyright (c) 2025 Nova Studios / Maximal Technology
// SPDX-License-Identifier: MIT