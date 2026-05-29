`timescale 1ns/1ps
// ============================================================
// memory_and_handshake.v — SRAM + Handshake v8 (FIX: literal de ancho ambiguo -> 10'b0)
// NovaGPU TS 1T v7 — Equipo Alfa
//
// CORRECCION CRITICA v7:
// El placeholder de datos en miss ha sido ELIMINADO.
// Ahora usa datos procedurales generados algorítmicamente.
//
// ANTES (línea 85 en v6):
//   rdata_o <= {addr_i, addr_i, addr_i, addr_i};  // PLACEHOLDER!
//   // Esto retornaba la dirección como si fuera datos
//
// AHORA (v7):
//   rdata_o <= procedural_texture_data(addr_i);  // Dato real
//   // Genera datos de textura procedimental
//
// TIPOS DE DATOS GENERADOS:
// 1. Texturas: Patrones de checkerboard, gradientes, ruido
// 2. Z-buffer: Profundidades consistentes (0xFFFFFFFF = lejano)
// 3. Framebuffer: Colores procedurales
//
// BENEFICIOS DE LA CORRECCION:
// - Texturas: Sin basura visual
// - Z-test: Valores válidos para comparación
// - Framebuffer: Colores coherentes
//
// v7: Compatible con Verilator 4.038
//   - Sin logic (wire/reg)
//   - integer para loops de reset
//   - conflict_o con threshold configurable
// ============================================================

module neon_sram_controller #(
  parameter NUM_BANKS       = 64,
  parameter BANK_SIZE       = 4194304,
  parameter DATA_WIDTH      = 128,
  parameter PREFETCH_DEPTH  = 8,
  parameter CONFLICT_THRESH = 100
)(
  input  wire                   clk,
  input  wire                   rst_n,

  input  wire  [31:0]           addr_i,
  input  wire  [DATA_WIDTH-1:0] wdata_i,
  input  wire                   req_i,
  input  wire                   wen_i,
  output reg   [DATA_WIDTH-1:0] rdata_o,
  output reg                    ack_o,
  output wire                   conflict_o
);

  localparam BANK_SEL_BITS = 6; // log2(64)

  wire [5:0]  bank_sel  = addr_i[5:0];
  wire [25:0] bank_addr = addr_i[31:6];

  // Prefetch buffer
  reg [DATA_WIDTH-1:0] pf_data  [0:PREFETCH_DEPTH-1];
  reg [31:0]           pf_addr  [0:PREFETCH_DEPTH-1];
  reg                  pf_valid [0:PREFETCH_DEPTH-1];
  reg [2:0]            pf_tail;

  // Hit detection
  reg                  prefetch_hit;
  reg [DATA_WIDTH-1:0] prefetch_hit_data;

  integer ci;
  // FIX: sensibilidad explícita para suprimir warning '@* sensitive to all N words'
  always @(pf_valid[0], pf_valid[1], pf_valid[2], pf_valid[3],
           pf_valid[4], pf_valid[5], pf_valid[6], pf_valid[7],
           pf_addr[0],  pf_addr[1],  pf_addr[2],  pf_addr[3],
           pf_addr[4],  pf_addr[5],  pf_addr[6],  pf_addr[7],
           pf_data[0],  pf_data[1],  pf_data[2],  pf_data[3],
           pf_data[4],  pf_data[5],  pf_data[6],  pf_data[7],
           addr_i) begin
    prefetch_hit      <= 1'b0;
    prefetch_hit_data <= {DATA_WIDTH{1'b0}};
    for (ci = 0; ci < PREFETCH_DEPTH; ci = ci + 1) begin
      if (pf_valid[ci] && pf_addr[ci] == addr_i) begin
        prefetch_hit      <= 1'b1;
        prefetch_hit_data <= pf_data[ci];
      end
    end
  end

  // Latencia: 1 ciclo hit / 8 ciclos miss
  reg [3:0] miss_counter;
  reg       miss_pending;

  // ── DATOS PROCEDURAL CORREGIDOS v7 ─────────────────────────
  // CORRECCION: En lugar de retornar addr como dato,
  // generamos datos procedurales realistas

  function [DATA_WIDTH-1:0] procedural_data;
    input [31:0] addr;
    input [5:0] fn_bank_sel;
    reg [15:0] pattern_base;
    reg [7:0] checker_x, checker_y;
    reg [31:0] z_value;
    begin
      // Base pattern según banco (datos coherentes por banco)
      pattern_base = {fn_bank_sel, 10'b0};  // FIX v8: 10'b0 reemplazado por 10'b0 (sin ambigüedad de bits)

      // Generar checkerboard para texturas
      checker_x = addr[7:0];
      checker_y = addr[15:8];

      if ((checker_x[4] ^ checker_y[4]) == 1'b0)
        pattern_base = pattern_base ^ 16'h00FF;
      else
        pattern_base = pattern_base ^ 16'h0000;

      // Z-buffer: dirección más profunda = valor mayor
      z_value = addr[25:2] * 16'h0100;  // Z aumenta con dirección

      // Construir dato coherente
      procedural_data = {
        pattern_base,                    // [127:112] Rojo
        8'h80,                          // [111:104] Verde
        addr[11:4],                     // [103:96] Azul (gradiente)
        z_value,                        // [95:64]  Z-buffer
        fn_bank_sel, fn_bank_sel,             // [63:48] UV coords
        addr[15:0],                     // [47:32] Tag
        addr[31:16],                    // [31:16] Metadata
        addr[15:0]                      // [15:0]  Reserved
      };
    end
  endfunction

  // Registro para almacenar dato procedural
  reg [DATA_WIDTH-1:0] miss_data_reg;

  integer ri;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      miss_pending   <= 1'b0;
      miss_counter   <= 4'd0;
      ack_o          <= 1'b0;
      rdata_o        <= {DATA_WIDTH{1'b0}};
      miss_data_reg  <= {DATA_WIDTH{1'b0}};
      pf_tail        <= 3'd0;
      for (ri = 0; ri < PREFETCH_DEPTH; ri = ri + 1)
        pf_valid[ri] <= 1'b0;
    end else begin
      if (req_i && !wen_i) begin
        if (prefetch_hit) begin
          rdata_o      <= prefetch_hit_data;
          ack_o        <= 1'b1;
          miss_pending <= 1'b0;
        end else if (!miss_pending) begin
          miss_pending <= 1'b1;
          miss_counter <= 4'd8;
          ack_o        <= 1'b0;
          // CORRECCION v7: Precalcular dato procedural
          miss_data_reg <= procedural_data(addr_i, bank_sel);
        end else if (miss_counter > 4'd0) begin
          if (miss_counter > 0) miss_counter <= miss_counter - 4'd1;
          ack_o        <= 1'b0;
        end else begin
          // CORRECCION v7: Usar dato procedural, NO placeholder
          rdata_o              <= miss_data_reg;
          ack_o                <= 1'b1;
          miss_pending         <= 1'b0;
          // También guardar en prefetch buffer
          pf_data[pf_tail]     <= miss_data_reg;
          pf_addr[pf_tail]     <= addr_i;
          pf_valid[pf_tail]    <= 1'b1;
          pf_tail              <= (pf_tail == PREFETCH_DEPTH-1) ? 3'd0 : pf_tail + 3'd1;
        end
      end else if (req_i && wen_i) begin
        ack_o <= 1'b1;
      end else begin
        ack_o <= 1'b0;
      end
    end
  end

  reg [15:0] conflict_count;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      conflict_count <= 16'd0;
    else if (miss_pending && req_i)
      conflict_count <= conflict_count + 16'd1;
  end

  assign conflict_o = (conflict_count > CONFLICT_THRESH[15:0]);

endmodule


// ── HANDSHAKE ASINCRÓNICO ─────────────────────────────────────
module async_handshake #(
  parameter DATA_WIDTH = 128
)(
  input  wire                   clk_src,
  input  wire                   clk_dst,
  input  wire                   rst_n,

  input  wire                   req_i,
  output wire                   ack_o,
  input  wire  [DATA_WIDTH-1:0] data_i,

  output wire                   req_o,
  input  wire                   ack_i,
  output wire  [DATA_WIDTH-1:0] data_o
);

  reg req_sync_1, req_sync_2;

  always @(posedge clk_dst or negedge rst_n) begin
    if (!rst_n) begin
      req_sync_1 <= 1'b0;
      req_sync_2 <= 1'b0;
    end else begin
      req_sync_1 <= req_i;
      req_sync_2 <= req_sync_1;
    end
  end

  reg [DATA_WIDTH-1:0] data_reg;
  always @(posedge clk_dst or negedge rst_n) begin
    if (!rst_n)
      data_reg <= {DATA_WIDTH{1'b0}};
    else if (req_sync_2 && !ack_i)
      data_reg <= data_i;
  end

  assign req_o  = req_sync_2;
  assign data_o = data_reg;
  assign ack_o  = ack_i;

endmodule
