`timescale 1ns/1ps
// ============================================================
// arbiter.v — Árbitro 16 Puertos v4 (FIX: prio_in aplanado Verilog-2001)
// NovaGPU TS 1T — Maximal Technology / Nova Studios
//
// v3: compatible con Verilator 4.038
//   - Sin typedef struct (buffer como arrays separados)
//   - count con un solo driver (do_push/do_pop combinacional)
//   - Z-Test prioridad absoluta + Round Robin
// ============================================================

module arbiter #(
  parameter NUM_PORTS  = 16,
  parameter BUF_DEPTH  = 64,
  parameter DATA_WIDTH = 128
)(
  input  wire                         clk,
  input  wire                         rst_n,

  input  wire  [NUM_PORTS-1:0]        req,
  input  wire  [DATA_WIDTH-1:0]       data_in_0,  data_in_1,  data_in_2,  data_in_3,
  input  wire  [DATA_WIDTH-1:0]       data_in_4,  data_in_5,  data_in_6,  data_in_7,
  input  wire  [DATA_WIDTH-1:0]       data_in_8,  data_in_9,  data_in_10, data_in_11,
  input  wire  [DATA_WIDTH-1:0]       data_in_12, data_in_13, data_in_14, data_in_15,
  input  wire  [2*NUM_PORTS-1:0]      prio_in_flat,
  // Codificación: prio_in[i] = prio_in_flat[2*i+1:2*i]
  // 00=color, 01=UV, 10=Z-Test (máxima), 11=metadata

  output reg   [NUM_PORTS-1:0]        grant,
  output reg   [DATA_WIDTH-1:0]       data_out,
  output reg                          data_valid,
  output wire                         buf_full
);

  // Buffer FIFO como arrays separados
  reg [DATA_WIDTH-1:0]  buf_data [BUF_DEPTH];
  reg [1:0]             buf_prio [BUF_DEPTH];
  reg [5:0]             head, tail;
  reg [6:0]             count; // 7 bits para 0..64

  assign buf_full = (count >= BUF_DEPTH[6:0]);

  // Desempacar prio_in_flat -> array interno prio_in[]
  wire [1:0] prio_in [0:NUM_PORTS-1];
  genvar ui;
  generate
    for (ui = 0; ui < NUM_PORTS; ui = ui + 1)
      assign prio_in[ui] = prio_in_flat[2*ui+1:2*ui];
  endgenerate

  // Mux de datos de entrada
  reg [DATA_WIDTH-1:0] sel_data;
  always @(*) begin
    case (grant)
      16'h0001: sel_data = data_in_0;
      16'h0002: sel_data = data_in_1;
      16'h0004: sel_data = data_in_2;
      16'h0008: sel_data = data_in_3;
      16'h0010: sel_data = data_in_4;
      16'h0020: sel_data = data_in_5;
      16'h0040: sel_data = data_in_6;
      16'h0080: sel_data = data_in_7;
      16'h0100: sel_data = data_in_8;
      16'h0200: sel_data = data_in_9;
      16'h0400: sel_data = data_in_10;
      16'h0800: sel_data = data_in_11;
      16'h1000: sel_data = data_in_12;
      16'h2000: sel_data = data_in_13;
      16'h4000: sel_data = data_in_14;
      16'h8000: sel_data = data_in_15;
      default:  sel_data = {DATA_WIDTH{1'b0}};
    endcase
  end

  reg [1:0] sel_prio;
  integer pi;
  // FIX: sensibilidad explícita — evita '@* sensitive to all N words in array'
  always @(grant, prio_in[0], prio_in[1],  prio_in[2],  prio_in[3],
                  prio_in[4],  prio_in[5],  prio_in[6],  prio_in[7],
                  prio_in[8],  prio_in[9],  prio_in[10], prio_in[11],
                  prio_in[12], prio_in[13], prio_in[14], prio_in[15]) begin
    sel_prio = 2'b00;
    for (pi = 0; pi < NUM_PORTS; pi = pi + 1)
      if (grant[pi]) sel_prio = prio_in[pi];
  end

  // Detección Z-Test
  wire [NUM_PORTS-1:0] z_req;
  genvar gi;
  generate
    for (gi = 0; gi < NUM_PORTS; gi = gi + 1)
      assign z_req[gi] = req[gi] & (prio_in[gi] == 2'b10);
  endgenerate

  // Selección de ganador
  reg [NUM_PORTS-1:0] rr_mask;
  wire [NUM_PORTS-1:0] winner;
  wire [NUM_PORTS-1:0] rr_eligible = req & rr_mask;

  assign winner = |z_req      ? (z_req      & (~z_req      + 1'b1)) :
                  |rr_eligible ? (rr_eligible & (~rr_eligible + 1'b1)) :
                                 (req         & (~req         + 1'b1));

  // Grant y Round Robin
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      grant   <= {NUM_PORTS{1'b0}};
      rr_mask <= {NUM_PORTS{1'b1}};
    end else if (|req && !buf_full) begin
      grant   <= winner;
      rr_mask <= ((rr_mask & ~winner) == {NUM_PORTS{1'b0}})
                  ? {NUM_PORTS{1'b1}}
                  : (rr_mask & ~winner);
    end else begin
      grant <= {NUM_PORTS{1'b0}};
    end
  end

  // Push + Pop + Count — un solo always_ff
  wire do_push = (|grant) & !buf_full;
  wire do_pop  = (count > 7'd0);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      head       <= 6'd0;
      tail       <= 6'd0;
      count      <= 7'd0;
      data_out   <= {DATA_WIDTH{1'b0}};
      data_valid <= 1'b0;
    end else begin
      if (do_push) begin
        buf_data[tail] <= sel_data;
        buf_prio[tail] <= sel_prio;
        tail           <= (tail == BUF_DEPTH-1) ? 6'd0 : tail + 1;
      end
      if (do_pop) begin
        data_out   <= buf_data[head];
        data_valid <= 1'b1;
        head       <= (head == BUF_DEPTH-1) ? 6'd0 : head + 1;
      end else begin
        data_valid <= 1'b0;
      end
      // Count — un solo driver
      case ({do_push, do_pop})
        2'b10:   count <= count + 1;
        2'b01:   count <= count - 1;
        default: count <= count;
      endcase
    end
  end

endmodule

// Copyright (c) 2025 Nova Studios / Maximal Technology
// SPDX-License-Identifier: MIT