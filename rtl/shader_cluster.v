`timescale 1ns/1ps
// ============================================================
// shader_cluster.v — Shader Cluster v12.0 (Equipo Alpha)
// NovaGPU TS 1T — Nova Studios
//
// FIX v12 — Warp Scheduler timing bug:
//   PROBLEMA: warp_ready = combinational from in_valid. El scheduler
//   registra en posedge. Cuando in_valid=1 por 1 ciclo, el scheduler
//   lee warp_ready=1111 en ese ciclo pero issue_valid sale en el
//   SIGUIENTE ciclo. Para ese momento in_valid ya es 0, y exec_unit
//   recibe in_valid=issue_valid=1 pero in_valid original ya fue.
//   Exec_unit usa issue_valid como su in_valid, lo cual ES correcto.
//   EL VERDADERO BUG: el warp_scheduler hace rr_ptr++ ANTES de
//   comprobar si el warp actual está ready. Si rr_ptr=1 y warp_ready
//   viene en ciclo t con rr_ptr=0, warp 0 se emite (OK). Pero si
//   in_valid llega cuando rr_ptr=3, el scheduler espera otro ciclo
//   hasta que rr_ptr vuelve a un warp ready.
//   FIX: El scheduler emite issue_valid en el MISMO ciclo que detecta
//   warp_ready, usando lógica combinacional para issue_valid,
//   manteniendo solo rr_ptr como registro.
// ============================================================

// ── MICRO-ISA OPCODES ─────────────────────────────────────────
localparam OP_NOP  = 8'h00;
localparam OP_ADD  = 8'h01;
localparam OP_MUL  = 8'h02;
localparam OP_MAD  = 8'h03;
localparam OP_TEX  = 8'h04;
localparam OP_RAY  = 8'h05;
localparam OP_MOV  = 8'h06;
localparam OP_FRAG = 8'h07;


// ── REGISTER FILE ─────────────────────────────────────────────
module regfile #(
  parameter NUM_REGS   = 16,
  parameter DATA_WIDTH = 32
)(
  input  wire                    clk,
  input  wire                    rst_n,
  input  wire [3:0]              wr_addr,
  input  wire [DATA_WIDTH-1:0]   wr_data,
  input  wire                    wr_en,
  input  wire [3:0]              rd_addr_a,
  input  wire [3:0]              rd_addr_b,
  output reg  [DATA_WIDTH-1:0]   rd_data_a,
  output reg  [DATA_WIDTH-1:0]   rd_data_b
);
  reg [DATA_WIDTH-1:0] regs [0:NUM_REGS-1];
  integer ri;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (ri = 0; ri < NUM_REGS; ri = ri + 1)
        regs[ri] <= {DATA_WIDTH{1'b0}};
      rd_data_a <= {DATA_WIDTH{1'b0}};
      rd_data_b <= {DATA_WIDTH{1'b0}};
    end else begin
      if (wr_en) regs[wr_addr] <= wr_data;
      rd_data_a <= regs[rd_addr_a];
      rd_data_b <= regs[rd_addr_b];
    end
  end
endmodule


// ── WARP SCHEDULER v12 ────────────────────────────────────────
// FIX: issue_valid es combinacional — sale en el mismo ciclo que
// se detecta warp_ready. Solo rr_ptr es registrado.
module warp_scheduler #(
  parameter NUM_WARPS  = 4,
  parameter DATA_WIDTH = 128
)(
  input  wire                   clk,
  input  wire                   rst_n,
  input  wire [NUM_WARPS-1:0]   warp_ready,
  output wire [1:0]             active_warp,
  output wire                   issue_valid
);
  reg [1:0] rr_ptr;

  // Combinacional: emite en el ciclo actual si el warp actual está listo
  // O busca el siguiente warp listo (priority + round-robin)
  wire w0_rdy = warp_ready[0];
  wire w1_rdy = warp_ready[1];
  wire w2_rdy = warp_ready[2];
  wire w3_rdy = warp_ready[3];
  wire any_rdy = w0_rdy | w1_rdy | w2_rdy | w3_rdy;

  // Selección combinacional del warp a emitir:
  // Primero comprueba rr_ptr, luego envuelve
  wire [1:0] next_warp =
    warp_ready[rr_ptr]          ? rr_ptr :
    warp_ready[rr_ptr + 2'd1]   ? (rr_ptr + 2'd1) :
    warp_ready[rr_ptr + 2'd2]   ? (rr_ptr + 2'd2) :
                                  (rr_ptr + 2'd3);

  assign issue_valid = any_rdy;
  assign active_warp = any_rdy ? next_warp : rr_ptr;

  // Avanzar rr_ptr registrado para distribuir la carga
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      rr_ptr <= 2'd0;
    else if (any_rdy)
      rr_ptr <= next_warp + 2'd1; // avanzar después del emitido
  end
endmodule


// ── EXECUTION UNIT ────────────────────────────────────────────
module exec_unit #(
  parameter DATA_WIDTH = 128
)(
  input  wire                   clk,
  input  wire                   rst_n,
  input  wire [DATA_WIDTH-1:0]  instr,
  input  wire                   in_valid,
  input  wire [DATA_WIDTH-1:0]  reg_a,
  input  wire [DATA_WIDTH-1:0]  reg_b,
  output reg  [DATA_WIDTH-1:0]  result,
  output reg  [3:0]             dst_reg,
  output reg                    wr_en,
  output reg                    out_valid
);
  wire [7:0]  opcode = instr[127:120];
  wire [3:0]  dst    = instr[119:116];
  wire [31:0] imm32  = instr[107:76];

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      result    <= {DATA_WIDTH{1'b0}};
      dst_reg   <= 4'd0;
      wr_en     <= 1'b0;
      out_valid <= 1'b0;
    end else if (in_valid) begin
      dst_reg   <= dst;
      out_valid <= 1'b1;
      wr_en     <= 1'b0;
      case (opcode)
        OP_NOP: begin result <= instr; wr_en <= 1'b0; end
        OP_ADD: begin
          result <= {{(DATA_WIDTH-32){1'b0}}, reg_a[31:0] + reg_b[31:0]};
          wr_en  <= 1'b1;
        end
        OP_MUL: begin
          result <= {{(DATA_WIDTH-32){1'b0}}, reg_a[31:16] * reg_b[31:16]};
          wr_en  <= 1'b1;
        end
        OP_MAD: begin
          result <= {{(DATA_WIDTH-32){1'b0}},
                     (reg_a[31:16] * reg_b[31:16]) + imm32[31:0]};
          wr_en  <= 1'b1;
        end
        OP_MOV: begin
          result <= {{(DATA_WIDTH-32){1'b0}}, imm32};
          wr_en  <= 1'b1;
        end
        OP_TEX, OP_RAY, OP_FRAG: begin result <= instr; wr_en <= 1'b0; end
        default: begin result <= instr; wr_en <= 1'b0; end
      endcase
    end else begin
      out_valid <= 1'b0;
      wr_en     <= 1'b0;
    end
  end
endmodule


// ── VERTEX SHADER UNIT ────────────────────────────────────────
module vertex_shader_unit #(
  parameter DATA_WIDTH = 128
)(
  input  wire                   clk,
  input  wire                   rst_n,
  input  wire  [DATA_WIDTH-1:0] vertex_in,
  input  wire                   in_valid,
  input  wire  [31:0]           mvp_m00, mvp_m01, mvp_m02, mvp_m03,
  input  wire  [31:0]           mvp_m10, mvp_m11, mvp_m12, mvp_m13,
  input  wire  [31:0]           mvp_m20, mvp_m21, mvp_m22, mvp_m23,
  input  wire  [31:0]           mvp_m30, mvp_m31, mvp_m32, mvp_m33,
  input  wire                   mvp_load,
  output reg   [DATA_WIDTH-1:0] vertex_out,
  output reg                    out_valid
);
  reg [31:0] m [0:15];
  integer mi;

  wire signed [31:0] vx = $signed(vertex_in[127:96]);
  wire signed [31:0] vy = $signed(vertex_in[95:64]);
  wire signed [31:0] vz = $signed(vertex_in[63:32]);
  wire signed [31:0] vw = $signed(vertex_in[31:0]);

  wire signed [63:0] ox_f = $signed(m[0])*vx + $signed(m[1])*vy + $signed(m[2])*vz  + $signed(m[3])*vw;
  wire signed [63:0] oy_f = $signed(m[4])*vx + $signed(m[5])*vy + $signed(m[6])*vz  + $signed(m[7])*vw;
  wire signed [63:0] oz_f = $signed(m[8])*vx + $signed(m[9])*vy + $signed(m[10])*vz + $signed(m[11])*vw;
  wire signed [63:0] ow_f = $signed(m[12])*vx+ $signed(m[13])*vy+ $signed(m[14])*vz + $signed(m[15])*vw;

  wire signed [31:0] ox = ox_f[47:16];
  wire signed [31:0] oy = oy_f[47:16];
  wire signed [31:0] oz = oz_f[47:16];
  wire signed [31:0] ow = ow_f[47:16];

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      vertex_out <= {DATA_WIDTH{1'b0}};
      out_valid  <= 1'b0;
      for (mi = 0; mi < 16; mi = mi + 1) m[mi] <= 32'h00000000;
      m[0]  <= 32'h00010000;
      m[5]  <= 32'h00010000;
      m[10] <= 32'h00010000;
      m[15] <= 32'h00010000;
    end else begin
      if (mvp_load) begin
        m[0]  <= mvp_m00; m[1]  <= mvp_m01; m[2]  <= mvp_m02; m[3]  <= mvp_m03;
        m[4]  <= mvp_m10; m[5]  <= mvp_m11; m[6]  <= mvp_m12; m[7]  <= mvp_m13;
        m[8]  <= mvp_m20; m[9]  <= mvp_m21; m[10] <= mvp_m22; m[11] <= mvp_m23;
        m[12] <= mvp_m30; m[13] <= mvp_m31; m[14] <= mvp_m32; m[15] <= mvp_m33;
      end
      if (in_valid) begin
        vertex_out <= {ox, oy, oz, ow};
        out_valid  <= 1'b1;
      end else begin
        out_valid <= 1'b0;
      end
    end
  end
endmodule


// ── FRAGMENT SHADER UNIT ──────────────────────────────────────
module fragment_shader_unit #(
  parameter DATA_WIDTH = 128
)(
  input  wire                   clk,
  input  wire                   rst_n,
  input  wire  [DATA_WIDTH-1:0] frag_a,
  input  wire  [DATA_WIDTH-1:0] frag_b,
  input  wire                   in_valid,
  output reg   [DATA_WIDTH-1:0] frag_out,
  output reg                    out_valid,
  output reg                    z_pass
);
  wire [31:0] color_a = frag_a[127:96];
  wire [31:0] color_b = frag_b[127:96];
  wire [31:0] z_a     = frag_a[95:64];
  wire [31:0] z_b     = frag_b[95:64];
  wire [15:0] uv_a    = frag_a[63:48];
  wire [15:0] tag_f   = frag_a[47:32];
  wire [15:0] meta_f  = frag_a[31:16];
  wire z_win = ($signed(z_a) <= $signed(z_b));

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      frag_out <= {DATA_WIDTH{1'b0}}; out_valid <= 1'b0; z_pass <= 1'b0;
    end else if (in_valid) begin
      z_pass <= z_win;
      frag_out <= {
        z_win ? color_a[31:24] : color_b[31:24],
        z_win ? color_a[23:16] : color_b[23:16],
        z_win ? color_a[15:8]  : color_b[15:8],
        z_win ? color_a[7:0]   : color_b[7:0],
        z_win ? z_a : z_b,
        uv_a, tag_f, meta_f, 16'h0000
      };
      out_valid <= 1'b1;
    end else begin
      out_valid <= 1'b0;
    end
  end
endmodule


// ── SHADER CLUSTER TOP ────────────────────────────────────────
module shader_cluster #(
  parameter NUM_CU     = 16,
  parameter DATA_WIDTH = 128,
  parameter NUM_WARPS  = 4
)(
  input  wire                   clk,
  input  wire                   rst_n,
  input  wire  [DATA_WIDTH-1:0] data_in,
  input  wire  [DATA_WIDTH-1:0] data_in_b,
  input  wire                   in_valid,
  input  wire  [31:0]           mvp_m00, mvp_m01, mvp_m02, mvp_m03,
  input  wire  [31:0]           mvp_m10, mvp_m11, mvp_m12, mvp_m13,
  input  wire  [31:0]           mvp_m20, mvp_m21, mvp_m22, mvp_m23,
  input  wire  [31:0]           mvp_m30, mvp_m31, mvp_m32, mvp_m33,
  input  wire                   mvp_load,
  output wire  [DATA_WIDTH-1:0] data_out,
  output wire                   out_valid
);
  wire [NUM_WARPS-1:0] warp_ready;
  wire [1:0]           active_warp;
  wire                 issue_valid;

  // warp_ready: any warp is ready when in_valid is asserted
  assign warp_ready = in_valid ? 4'b1111 : 4'b0000;

  warp_scheduler #(.NUM_WARPS(NUM_WARPS), .DATA_WIDTH(DATA_WIDTH)) u_sched (
    .clk(clk), .rst_n(rst_n),
    .warp_ready(warp_ready),
    .active_warp(active_warp),
    .issue_valid(issue_valid)
  );

  wire [3:0]            rf_rd_a  = data_in[115:112];
  wire [3:0]            rf_rd_b  = data_in[111:108];
  wire [DATA_WIDTH-1:0] rf_data_a, rf_data_b;
  wire [3:0]            rf_wr_addr;
  wire [DATA_WIDTH-1:0] rf_wr_data;
  wire                  rf_wr_en;

  regfile #(.NUM_REGS(16), .DATA_WIDTH(DATA_WIDTH)) u_rf (
    .clk(clk), .rst_n(rst_n),
    .wr_addr(rf_wr_addr), .wr_data(rf_wr_data), .wr_en(rf_wr_en),
    .rd_addr_a(rf_rd_a), .rd_addr_b(rf_rd_b),
    .rd_data_a(rf_data_a), .rd_data_b(rf_data_b)
  );

  wire [DATA_WIDTH-1:0] exec_result;
  wire [3:0]            exec_dst;
  wire                  exec_wr_en;
  wire                  exec_valid;

  // FIX v12: exec_unit driven directly by in_valid (combinational issue_valid)
  exec_unit #(.DATA_WIDTH(DATA_WIDTH)) u_exec (
    .clk(clk), .rst_n(rst_n),
    .instr(data_in), .in_valid(issue_valid),
    .reg_a(rf_data_a), .reg_b(rf_data_b),
    .result(exec_result), .dst_reg(exec_dst),
    .wr_en(exec_wr_en), .out_valid(exec_valid)
  );

  assign rf_wr_addr = exec_dst;
  assign rf_wr_data = exec_result;
  assign rf_wr_en   = exec_wr_en;

  wire [DATA_WIDTH-1:0] vertex_out;
  wire                  vertex_valid;

  vertex_shader_unit #(.DATA_WIDTH(DATA_WIDTH)) u_vsu (
    .clk(clk), .rst_n(rst_n),
    .vertex_in(exec_result), .in_valid(exec_valid),
    .mvp_m00(mvp_m00), .mvp_m01(mvp_m01), .mvp_m02(mvp_m02), .mvp_m03(mvp_m03),
    .mvp_m10(mvp_m10), .mvp_m11(mvp_m11), .mvp_m12(mvp_m12), .mvp_m13(mvp_m13),
    .mvp_m20(mvp_m20), .mvp_m21(mvp_m21), .mvp_m22(mvp_m22), .mvp_m23(mvp_m23),
    .mvp_m30(mvp_m30), .mvp_m31(mvp_m31), .mvp_m32(mvp_m32), .mvp_m33(mvp_m33),
    .mvp_load(mvp_load),
    .vertex_out(vertex_out), .out_valid(vertex_valid)
  );

  wire z_pass_nc;
  fragment_shader_unit #(.DATA_WIDTH(DATA_WIDTH)) u_fsu (
    .clk(clk), .rst_n(rst_n),
    .frag_a(vertex_out), .frag_b(data_in_b),
    .in_valid(vertex_valid),
    .frag_out(data_out), .out_valid(out_valid),
    .z_pass(z_pass_nc)
  );

endmodule

// Copyright (c) 2025 Nova Studios / Maximal Technology
// SPDX-License-Identifier: MIT