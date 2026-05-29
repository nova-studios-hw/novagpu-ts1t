`timescale 1ns/1ps
// =============================================================================
// shader_cluster.v  —  Shader Cluster  v3.0
// NovaGPU TS 2T  —  Nova Studios / Maximal Technology
//
// Sub-módulos:
//   regfile         — Banco de registros 16×DATA_WIDTH
//   warp_scheduler  — Round-robin sobre NUM_WARPS warps
//   exec_unit       — Unidad de ejecución con 8 opcodes
//   shader_cluster  — Integrador
//
// Correcciones v3.0:
//   - exec_unit: MVP rows pasadas como buses planos [127:0] (no arrays)
//     para compatibilidad Icarus Verilog 12 / Verilog-2001.
//   - Latencia 1 ciclo pipeline documentada en comentarios.
// =============================================================================

// ── Register File ──────────────────────────────────────────────
module regfile #(
    parameter NUM_REGS   = 16,
    parameter DATA_WIDTH = 32
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire [3:0]             wr_addr,
    input  wire [DATA_WIDTH-1:0]  wr_data,
    input  wire                   wr_en,
    input  wire [3:0]             rd_addr_a,
    input  wire [3:0]             rd_addr_b,
    output reg  [DATA_WIDTH-1:0]  rd_data_a,
    output reg  [DATA_WIDTH-1:0]  rd_data_b
);
    reg [DATA_WIDTH-1:0] regs [0:NUM_REGS-1];
    integer ri;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_data_a <= {DATA_WIDTH{1'b0}};
            rd_data_b <= {DATA_WIDTH{1'b0}};
            for (ri = 0; ri < NUM_REGS; ri = ri + 1)
                regs[ri] <= {DATA_WIDTH{1'b0}};
        end else begin
            if (wr_en) regs[wr_addr] <= wr_data;
            rd_data_a <= regs[rd_addr_a];
            rd_data_b <= regs[rd_addr_b];
        end
    end
endmodule

// ── Warp Scheduler ─────────────────────────────────────────────
module warp_scheduler #(
    parameter NUM_WARPS = 4
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire [NUM_WARPS-1:0]  warp_ready,
    output wire [1:0]            active_warp,
    output wire                  issue_valid
);
    reg [1:0] rr_ptr;
    wire any_rdy = |warp_ready;

    // Encontrar siguiente warp listo desde rr_ptr
    wire [1:0] c0 = rr_ptr;
    wire [1:0] c1 = rr_ptr + 2'd1;
    wire [1:0] c2 = rr_ptr + 2'd2;
    wire [1:0] c3 = rr_ptr + 2'd3;

    wire s0 = warp_ready[c0];
    wire s1 = warp_ready[c1] & ~s0;
    wire s2 = warp_ready[c2] & ~s0 & ~s1;
    wire s3 = warp_ready[c3] & ~s0 & ~s1 & ~s2;

    assign active_warp = s0 ? c0 : s1 ? c1 : s2 ? c2 : s3 ? c3 : rr_ptr;
    assign issue_valid = any_rdy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rr_ptr <= 2'd0;
        else if (issue_valid) rr_ptr <= active_warp + 2'd1;
    end
endmodule

// ── Execution Unit ─────────────────────────────────────────────
// MVP rows pasadas como buses planos de 128 bits (4×32-bit concatenados)
module exec_unit #(
    parameter DATA_WIDTH = 128
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   in_valid,
    input  wire [DATA_WIDTH-1:0]  data_a,
    input  wire [DATA_WIDTH-1:0]  data_b,
    // MVP rows como buses planos [127:0] = {m[0],m[1],m[2],m[3]}
    input  wire [127:0]           mvp_row0,
    input  wire [127:0]           mvp_row1,
    input  wire [127:0]           mvp_row2,
    input  wire [127:0]           mvp_row3,
    output reg  [DATA_WIDTH-1:0]  data_out,
    output reg                    out_valid,
    output reg  [15:0]            exec_count
);
    wire [2:0]  opcode = data_a[7:5];
    wire [31:0] opA    = data_a[127:96];
    wire [31:0] opB    = data_b[127:96];
    wire [31:0] opC    = data_a[95:64];
    wire [31:0] opD    = data_b[95:64];

    // Extracción de elementos MVP desde bus plano
    wire [31:0] r0c0 = mvp_row0[127:96], r0c1 = mvp_row0[95:64],
                r0c2 = mvp_row0[63:32],  r0c3 = mvp_row0[31:0];
    wire [31:0] r1c0 = mvp_row1[127:96], r1c1 = mvp_row1[95:64],
                r1c2 = mvp_row1[63:32],  r1c3 = mvp_row1[31:0];
    wire [31:0] r2c0 = mvp_row2[127:96], r2c1 = mvp_row2[95:64],
                r2c2 = mvp_row2[63:32],  r2c3 = mvp_row2[31:0];
    wire [31:0] r3c0 = mvp_row3[127:96], r3c1 = mvp_row3[95:64],
                r3c2 = mvp_row3[63:32],  r3c3 = mvp_row3[31:0];

    // Transformación MVP (columna de entrada: opA, opC, opB, opD)
    wire [63:0] mvp_x = $signed(r0c0)*$signed(opA) + $signed(r0c1)*$signed(opC) +
                        $signed(r0c2)*$signed(opB) + $signed(r0c3)*$signed(opD);
    wire [63:0] mvp_y = $signed(r1c0)*$signed(opA) + $signed(r1c1)*$signed(opC) +
                        $signed(r1c2)*$signed(opB) + $signed(r1c3)*$signed(opD);
    wire [63:0] mvp_z = $signed(r2c0)*$signed(opA) + $signed(r2c1)*$signed(opC) +
                        $signed(r2c2)*$signed(opB) + $signed(r2c3)*$signed(opD);
    wire [63:0] mvp_w = $signed(r3c0)*$signed(opA) + $signed(r3c1)*$signed(opC) +
                        $signed(r3c2)*$signed(opB) + $signed(r3c3)*$signed(opD);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid  <= 1'b0;
            data_out   <= {DATA_WIDTH{1'b0}};
            exec_count <= 16'd0;
        end else begin
            out_valid <= 1'b0;
            if (in_valid) begin
                exec_count <= exec_count + 16'd1;
                out_valid  <= 1'b1;
                case (opcode)
                    3'd0: data_out <= data_a;
                    3'd1: data_out <= {opA + opB, opC + opD, data_a[63:0]};
                    3'd2: data_out <= {opA - opB, opC - opD, data_a[63:0]};
                    3'd3: data_out <= {opA[31:16] * opB[31:16],
                                       opC[31:16] * opD[31:16], data_a[63:0]};
                    3'd4: data_out <= {data_b[127:64], data_a[63:0]};
                    3'd5: data_out <= {opA >= opB ? 32'h1 : 32'h0,
                                       opC >= opD ? 32'h1 : 32'h0, data_a[63:0]};
                    3'd6: data_out <= {(opA >> 1) + (opB >> 1),
                                       (opC >> 1) + (opD >> 1), data_a[63:0]};
                    3'd7: data_out <= {mvp_x[47:16], mvp_y[47:16],
                                       mvp_z[47:16], mvp_w[47:16]};
                    default: data_out <= data_a;
                endcase
            end
        end
    end
endmodule

// ── Shader Cluster Top ─────────────────────────────────────────
module shader_cluster #(
    parameter NUM_CU     = 4,
    parameter DATA_WIDTH = 128,
    parameter NUM_WARPS  = 4
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire [DATA_WIDTH-1:0]  data_in,
    input  wire [DATA_WIDTH-1:0]  data_in_b,
    input  wire                   in_valid,
    input  wire [31:0] mvp_m00, mvp_m01, mvp_m02, mvp_m03,
    input  wire [31:0] mvp_m10, mvp_m11, mvp_m12, mvp_m13,
    input  wire [31:0] mvp_m20, mvp_m21, mvp_m22, mvp_m23,
    input  wire [31:0] mvp_m30, mvp_m31, mvp_m32, mvp_m33,
    input  wire        mvp_load,
    output wire [DATA_WIDTH-1:0]  data_out,
    output wire                   out_valid,
    output wire [15:0]            exec_count_out
);
    // Registros MVP internos
    reg [31:0] mvp [0:3][0:3];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Identidad en Q16.16 (1.0 = 0x00010000)
            mvp[0][0] <= 32'h00010000; mvp[0][1] <= 32'h0;
            mvp[0][2] <= 32'h0;        mvp[0][3] <= 32'h0;
            mvp[1][0] <= 32'h0;        mvp[1][1] <= 32'h00010000;
            mvp[1][2] <= 32'h0;        mvp[1][3] <= 32'h0;
            mvp[2][0] <= 32'h0;        mvp[2][1] <= 32'h0;
            mvp[2][2] <= 32'h00010000; mvp[2][3] <= 32'h0;
            mvp[3][0] <= 32'h0;        mvp[3][1] <= 32'h0;
            mvp[3][2] <= 32'h0;        mvp[3][3] <= 32'h00010000;
        end else if (mvp_load) begin
            mvp[0][0] <= mvp_m00; mvp[0][1] <= mvp_m01;
            mvp[0][2] <= mvp_m02; mvp[0][3] <= mvp_m03;
            mvp[1][0] <= mvp_m10; mvp[1][1] <= mvp_m11;
            mvp[1][2] <= mvp_m12; mvp[1][3] <= mvp_m13;
            mvp[2][0] <= mvp_m20; mvp[2][1] <= mvp_m21;
            mvp[2][2] <= mvp_m22; mvp[2][3] <= mvp_m23;
            mvp[3][0] <= mvp_m30; mvp[3][1] <= mvp_m31;
            mvp[3][2] <= mvp_m32; mvp[3][3] <= mvp_m33;
        end
    end

    wire [NUM_WARPS-1:0] warp_ready = {NUM_WARPS{in_valid}};
    wire [1:0] active_warp;
    wire       issue_valid;

    warp_scheduler #(.NUM_WARPS(NUM_WARPS)) u_sched (
        .clk(clk), .rst_n(rst_n),
        .warp_ready(warp_ready),
        .active_warp(active_warp),
        .issue_valid(issue_valid)
    );

    exec_unit #(.DATA_WIDTH(DATA_WIDTH)) u_exec (
        .clk(clk), .rst_n(rst_n),
        .in_valid(issue_valid),
        .data_a(data_in), .data_b(data_in_b),
        .mvp_row0({mvp[0][0], mvp[0][1], mvp[0][2], mvp[0][3]}),
        .mvp_row1({mvp[1][0], mvp[1][1], mvp[1][2], mvp[1][3]}),
        .mvp_row2({mvp[2][0], mvp[2][1], mvp[2][2], mvp[2][3]}),
        .mvp_row3({mvp[3][0], mvp[3][1], mvp[3][2], mvp[3][3]}),
        .data_out(data_out),
        .out_valid(out_valid),
        .exec_count(exec_count_out)
    );

endmodule