`timescale 1ns/1ps
// =============================================================================
// sram_integrated.v  —  SRAM Integrada  v3.0
// NovaGPU TS 2T  —  Nova Studios / Maximal Technology
//
// Dual-port SRAM con:
//   - Puerto A: R/W (framebuffer)
//   - Puerto B: R only (BVH/texturas)
//   - AXI4-Lite slave minimal
//   - Hit/miss counters
//   - Bandwidth counters por subsistema
//   - Conflict detection
//
// Correcciones v3.0:
//   - Puerto B: hit_count actualizado en bloque B (no conflicto con bloque A)
//   - Reset block separado para counters (evitar doble-driver)
// =============================================================================

module sram_integrated #(
    parameter DATA_WIDTH = 128,
    parameter ADDR_WIDTH = 32,
    parameter MEM_DEPTH  = 4096
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Puerto A (R/W)
    input  wire [ADDR_WIDTH-1:0]  a_addr,
    input  wire [DATA_WIDTH-1:0]  a_wdata,
    input  wire                   a_req,
    input  wire                   a_wen,
    output reg  [DATA_WIDTH-1:0]  a_rdata,
    output reg                    a_ack,

    // Puerto B (R only)
    input  wire [ADDR_WIDTH-1:0]  b_addr,
    input  wire [DATA_WIDTH-1:0]  b_wdata,
    input  wire                   b_req,
    input  wire                   b_wen,
    output reg  [DATA_WIDTH-1:0]  b_rdata,
    output reg                    b_ack,

    // AXI4-Lite slave minimal
    output reg                    axi_awready,
    output reg                    axi_wready,
    output reg                    axi_arready,
    output reg                    axi_rvalid,
    output reg  [DATA_WIDTH-1:0]  axi_rdata,

    // Stats
    output reg  [15:0]            hit_count,
    output reg  [15:0]            miss_count,
    output wire                   conflict_o,

    // Bandwidth counters
    output reg  [15:0]            bw_instrmem,
    output reg  [15:0]            bw_bvhmem,
    output reg  [15:0]            bw_texmem,
    output reg  [15:0]            bw_framebuf
);

    // ── Memory array ──────────────────────────────────────────
    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    localparam IDX_BITS = $clog2(MEM_DEPTH);
    wire [IDX_BITS-1:0] a_idx = a_addr[IDX_BITS-1:0];
    wire [IDX_BITS-1:0] b_idx = b_addr[IDX_BITS-1:0];

    // ── Conflict detection ────────────────────────────────────
    assign conflict_o = a_req & b_req & (a_idx == b_idx);

    // ── Puerto A ──────────────────────────────────────────────
    reg a_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_ack     <= 1'b0;
            a_rdata   <= {DATA_WIDTH{1'b0}};
            a_pending <= 1'b0;
        end else begin
            a_ack <= 1'b0;

            if (a_req & ~a_pending) begin
                a_pending <= 1'b1;
                if (a_wen)
                    mem[a_idx] <= a_wdata;
                a_rdata   <= mem[a_idx];
                a_ack     <= 1'b1;
                a_pending <= 1'b0;
            end
        end
    end

    // ── Puerto B ──────────────────────────────────────────────
    reg b_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            b_ack     <= 1'b0;
            b_rdata   <= {DATA_WIDTH{1'b0}};
            b_pending <= 1'b0;
        end else begin
            b_ack <= 1'b0;

            if (b_req & ~b_pending) begin
                b_pending <= 1'b1;
                if (~conflict_o) begin
                    b_rdata   <= mem[b_idx];
                    b_ack     <= 1'b1;
                    b_pending <= 1'b0;
                end
                // En conflicto: esperar un ciclo (b_pending permanece)
            end else if (b_pending & ~b_ack) begin
                b_rdata   <= mem[b_idx];
                b_ack     <= 1'b1;
                b_pending <= 1'b0;
            end
        end
    end

    // ── Stats counters ────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hit_count   <= 16'd0;
            miss_count  <= 16'd0;
            bw_instrmem <= 16'd0;
            bw_bvhmem   <= 16'd0;
            bw_texmem   <= 16'd0;
            bw_framebuf <= 16'd0;
        end else begin
            if (a_req & ~a_pending) begin
                hit_count   <= hit_count + 16'd1;
                bw_framebuf <= bw_framebuf + 16'd1;
            end
            if (b_req & ~b_pending) begin
                if (~conflict_o)
                    hit_count  <= hit_count + 16'd1;
                else
                    miss_count <= miss_count + 16'd1;
                bw_bvhmem  <= bw_bvhmem + 16'd1;
            end
        end
    end

    // ── AXI4-Lite minimal (always-ready slave) ────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_awready <= 1'b1;
            axi_wready  <= 1'b1;
            axi_arready <= 1'b1;
            axi_rvalid  <= 1'b0;
            axi_rdata   <= {DATA_WIDTH{1'b0}};
        end else begin
            axi_awready <= 1'b1;
            axi_wready  <= 1'b1;
            axi_arready <= 1'b1;
            axi_rvalid  <= 1'b1;
            axi_rdata   <= {DATA_WIDTH{1'b0}};
        end
    end

endmodule