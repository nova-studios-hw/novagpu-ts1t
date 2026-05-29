`timescale 1ns/1ps
// =============================================================================
// arbiter.v  —  Árbitro Round-Robin  v3.0
// NovaGPU TS 2T  —  Nova Studios / Maximal Technology
//
// Árbitro de N puertos con FIFO de bypass BUF_DEPTH entradas.
// NUM_PORTS máximo 8 (3-bit rr_ptr).
// =============================================================================

module arbiter #(
    parameter NUM_PORTS  = 4,
    parameter BUF_DEPTH  = 16,
    parameter DATA_WIDTH = 128
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire [NUM_PORTS-1:0]         req,

    input  wire [DATA_WIDTH-1:0]        data_in_0,
    input  wire [DATA_WIDTH-1:0]        data_in_1,
    input  wire [DATA_WIDTH-1:0]        data_in_2,
    input  wire [DATA_WIDTH-1:0]        data_in_3,
    input  wire [DATA_WIDTH-1:0]        data_in_4,
    input  wire [DATA_WIDTH-1:0]        data_in_5,
    input  wire [DATA_WIDTH-1:0]        data_in_6,
    input  wire [DATA_WIDTH-1:0]        data_in_7,

    input  wire [2*NUM_PORTS-1:0]       prio_in_flat,

    output reg  [NUM_PORTS-1:0]         grant,
    output reg  [DATA_WIDTH-1:0]        data_out,
    output reg                          data_valid,
    output wire                         buf_full
);

    localparam BUF_BITS = $clog2(BUF_DEPTH);

    // ── FIFO ──────────────────────────────────────────────────
    reg [DATA_WIDTH-1:0] fifo [0:BUF_DEPTH-1];
    reg [BUF_BITS-1:0]   wr_ptr, rd_ptr;
    reg [BUF_BITS:0]     fill;

    assign buf_full = (fill >= BUF_DEPTH[BUF_BITS:0]);

    // ── Round-robin pointer ───────────────────────────────────
    reg [2:0] rr;

    // ── Mux de datos de entrada ───────────────────────────────
    reg [DATA_WIDTH-1:0] sel_data;
    always @(*) begin
        case (rr)
            3'd0: sel_data = data_in_0;
            3'd1: sel_data = data_in_1;
            3'd2: sel_data = data_in_2;
            3'd3: sel_data = data_in_3;
            3'd4: sel_data = data_in_4;
            3'd5: sel_data = data_in_5;
            3'd6: sel_data = data_in_6;
            3'd7: sel_data = data_in_7;
            default: sel_data = {DATA_WIDTH{1'b0}};
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rr         <= 3'd0;
            grant      <= {NUM_PORTS{1'b0}};
            data_valid <= 1'b0;
            data_out   <= {DATA_WIDTH{1'b0}};
            wr_ptr     <= {BUF_BITS{1'b0}};
            rd_ptr     <= {BUF_BITS{1'b0}};
            fill       <= {(BUF_BITS+1){1'b0}};
        end else begin
            data_valid <= 1'b0;
            grant      <= {NUM_PORTS{1'b0}};

            // Arbitrar: si hay request y FIFO no lleno
            if (rr < NUM_PORTS[2:0] && req[rr] && !buf_full) begin
                grant[rr]    <= 1'b1;
                fifo[wr_ptr] <= sel_data;
                wr_ptr       <= (wr_ptr == BUF_DEPTH - 1) ?
                                {BUF_BITS{1'b0}} : wr_ptr + {{(BUF_BITS-1){1'b0}}, 1'b1};
                fill         <= fill + {{BUF_BITS{1'b0}}, 1'b1};
            end

            // Avanzar RR
            rr <= (rr >= NUM_PORTS[2:0] - 3'd1) ? 3'd0 : rr + 3'd1;

            // Sacar de FIFO si hay datos
            if (fill > {(BUF_BITS+1){1'b0}}) begin
                data_out   <= fifo[rd_ptr];
                data_valid <= 1'b1;
                rd_ptr     <= (rd_ptr == BUF_DEPTH - 1) ?
                              {BUF_BITS{1'b0}} : rd_ptr + {{(BUF_BITS-1){1'b0}}, 1'b1};
                fill       <= fill - {{BUF_BITS{1'b0}}, 1'b1};
            end
        end
    end

endmodule