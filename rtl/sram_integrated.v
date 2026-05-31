// =============================================================================
//  sram_integrated.v  --  SRAM Integrada Dual-Port  v6.5-FIX (Final)
//  NovaGPU TS 1T  --  Nova Studios / Maximal Technology
//
//  CORRECCIONES v6.5:
//    - FIX E1_sram_ack: Se agregó a_rdata_held para retener el dato de
//      lectura (hold) y evitar que se pierda si el testbench cambia a_addr.
//    - a_ack alineado para caer junto con a_req y evitar acks fantasma.
//    - Mantiene 100% la inferencia de BRAM en Yosys y Vivado.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module sram_integrated #(
    parameter integer DATA_WIDTH = 128,
    parameter integer ADDR_WIDTH = 32,
    parameter integer MEM_DEPTH  = 4096
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // Puerto A : Read / Write
    input  wire [ADDR_WIDTH-1:0]   a_addr,
    input  wire [DATA_WIDTH-1:0]   a_wdata,
    input  wire                    a_req,
    input  wire                    a_wen,
    output reg  [DATA_WIDTH-1:0]   a_rdata,
    output wire                    a_ack,

    // Puerto B : Read-only
    input  wire [ADDR_WIDTH-1:0]   b_addr,
    input  wire                    b_req,
    output reg  [DATA_WIDTH-1:0]   b_rdata,
    output reg                     b_ack,

    // AXI4-Lite slave minimo
    output reg                     axi_awready,
    output reg                     axi_wready,
    output reg                     axi_arready,
    output reg                     axi_rvalid,
    output reg  [DATA_WIDTH-1:0]   axi_rdata,

    // Estadisticas
    output reg  [15:0]             hit_count,
    output reg  [15:0]             miss_count,
    output wire                    conflict_o,

    // Ancho de banda
    output reg  [15:0]             bw_framebuf,
    output reg  [15:0]             bw_bvhmem
);
    localparam integer IDX_BITS = $clog2(MEM_DEPTH);

    wire [IDX_BITS-1:0] a_idx = a_addr[IDX_BITS-1:0];
    wire [IDX_BITS-1:0] b_idx = b_addr[IDX_BITS-1:0];

    // Conflicto: A escribe mientras B lee la misma direccion
    assign conflict_o = a_req & a_wen & b_req & (a_idx == b_idx);

    // -- Stall del Puerto B -------------------------------------------------
    reg                  b_stall;
    reg [IDX_BITS-1:0]   b_idx_latch;

    wire [IDX_BITS-1:0] b_idx_eff = b_stall ? b_idx_latch : b_idx;
    wire b_rd_en = (b_req & ~conflict_o) | b_stall;

    // -- Memoria (bloque sincrono puro para inferencia BRAM) ----------------
    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];
    reg [DATA_WIDTH-1:0] ram_a_q;
    reg [DATA_WIDTH-1:0] ram_b_q;

    always @(posedge clk) begin
        if (a_req & a_wen)
            mem[a_idx] <= a_wdata;
        ram_a_q <= mem[a_idx];
        ram_b_q <= mem[b_idx_eff];
    end

    // -- FIX E1 v6.5: Lógica de ACK y Retención (Hold) ----------------------
    reg  a_ack_rd;   
    reg  b_rd_en_q;
    reg  [DATA_WIDTH-1:0] a_rdata_held;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_ack_rd     <= 1'b0;
            b_ack        <= 1'b0;
            b_rdata      <= {DATA_WIDTH{1'b0}};
            b_rd_en_q    <= 1'b0;
            b_stall      <= 1'b0;
            b_idx_latch  <= {IDX_BITS{1'b0}};
            a_rdata_held <= {DATA_WIDTH{1'b0}};
        end else begin
            // == Puerto A ==================================================
            a_ack_rd <= a_req & ~a_wen;

            // Latch para retener el dato cuando el ack se activa
            if (a_ack_rd)
                a_rdata_held <= ram_a_q;

            // == Puerto B ==================================================
            if (b_req & conflict_o) begin
                b_stall     <= 1'b1;
                b_idx_latch <= b_idx;
            end else begin
                b_stall <= 1'b0;
            end

            b_rd_en_q <= b_rd_en;
            b_ack     <= b_rd_en_q;
            if (b_rd_en_q)
                b_rdata <= ram_b_q;
        end
    end

    // FIX E1 v6.5: Multiplexor para dar 1 ciclo de latencia pero mantener el hold
    always @(*) begin
        if (!rst_n)
            a_rdata = {DATA_WIDTH{1'b0}};
        else if (a_ack_rd)
            a_rdata = ram_a_q;      // Dato fresco con 1 ciclo exacto de latencia
        else
            a_rdata = a_rdata_held; // Retiene el dato si el testbench quita el a_req
    end

    // Escritura combinacional; Lectura registrada alineada a a_req para no dar dobles acks
    assign a_ack = (a_req & a_wen) ? 1'b1 : (a_req & a_ack_rd);

    // -- Estadisticas -------------------------------------------------------
    reg [1:0] hit_inc;
    reg       miss_inc;
    reg       bw_a_inc;
    reg       bw_b_inc;

    always @(*) begin
        hit_inc  = 2'd0;
        miss_inc = 1'b0;
        bw_a_inc = 1'b0;
        bw_b_inc = 1'b0;

        if (a_req) begin
            hit_inc  = hit_inc + 2'd1;
            bw_a_inc = 1'b1;
        end

        if (b_req & ~b_stall) begin
            bw_b_inc = 1'b1;
            if (!conflict_o)
                hit_inc  = hit_inc + 2'd1;
            else
                miss_inc = 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hit_count   <= 16'd0;
            miss_count  <= 16'd0;
            bw_framebuf <= 16'd0;
            bw_bvhmem   <= 16'd0;
        end else begin
            hit_count   <= hit_count   + {{14{1'b0}}, hit_inc};
            miss_count  <= miss_count  + {15'd0, miss_inc};
            bw_framebuf <= bw_framebuf + {15'd0, bw_a_inc};
            bw_bvhmem   <= bw_bvhmem   + {15'd0, bw_b_inc};
        end
    end

    // -- AXI4-Lite slave minimo ---------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_awready <= 1'b0;
            axi_wready  <= 1'b0;
            axi_arready <= 1'b0;
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

`ifdef FORMAL
    always @(posedge clk) begin
        if ($past(conflict_o) && $past(rst_n))
            assert (!$past(b_rd_en_q));
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            assert (a_ack == 1'b0);
            assert (b_ack == 1'b0);
        end
    end
`endif

endmodule