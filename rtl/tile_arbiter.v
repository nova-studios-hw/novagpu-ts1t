`timescale 1ns/1ps
// =============================================================================
// tile_arbiter.v  —  Tile Arbiter  v3.0
// NovaGPU TS 2T  —  Nova Studios / Maximal Technology
//
// Recibe tokens de fragmento, realiza Z-test y escribe al framebuffer.
// Z-buffer hashed de 64 entradas (representativo para simulación).
// =============================================================================

module tile_arbiter #(
    parameter DATA_WIDTH = 128,
    parameter SCREEN_W   = 640,
    parameter SCREEN_H   = 480
)(
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire [DATA_WIDTH-1:0]  frag_in,
    input  wire                   frag_valid,
    output reg                    frag_ready,

    output reg  [31:0]            pixel_color,
    output reg  [18:0]            pixel_addr,
    output reg                    pixel_write,

    output reg  [15:0]            fragments_written,
    output reg  [15:0]            fragments_discarded
);

    // ── Token decode ──────────────────────────────────────────
    // [127:96]=color, [95:64]=z, [63:48]=px, [47:32]=py
    // [15:0]=flags (bit0=valid, bit1=edge, bit2=last)
    wire [31:0] tok_color  = frag_in[127:96];
    wire [31:0] tok_z      = frag_in[95:64];
    wire [15:0] tok_px     = frag_in[63:48];
    wire [15:0] tok_py     = frag_in[47:32];
    wire        tok_valid  = frag_in[0];

    // ── Z-buffer hashed (64 slots) ────────────────────────────
    reg [31:0] z_buf [0:63];
    wire [5:0] z_idx = tok_px[5:0] ^ tok_py[5:0];
    wire       z_pass = (tok_z <= z_buf[z_idx]);

    // ── Bounds check ──────────────────────────────────────────
    wire in_bounds = ({5'd0, tok_px} < SCREEN_W) && ({5'd0, tok_py} < SCREEN_H);

    // ── Address calculation ───────────────────────────────────
    wire [18:0] calc_addr = ({8'd0, tok_py[10:0]} * SCREEN_W[18:0]) +
                             {8'd0, tok_px[10:0]};

    // ── FSM ───────────────────────────────────────────────────
    localparam ST_IDLE  = 2'd0;
    localparam ST_TEST  = 2'd1;
    localparam ST_WRITE = 2'd2;
    localparam ST_DONE  = 2'd3;

    reg [1:0] state;
    reg [31:0] latch_color;
    reg [31:0] latch_z;
    reg [18:0] latch_addr;
    reg [5:0]  latch_zidx;
    reg        latch_ok;
    integer zi;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= ST_IDLE;
            frag_ready          <= 1'b1;
            pixel_write         <= 1'b0;
            fragments_written   <= 16'd0;
            fragments_discarded <= 16'd0;
            for (zi = 0; zi < 64; zi = zi + 1)
                z_buf[zi] <= 32'hFFFFFFFF;
        end else begin
            pixel_write <= 1'b0;

            case (state)
                ST_IDLE: begin
                    frag_ready <= 1'b1;
                    if (frag_valid) begin
                        frag_ready  <= 1'b0;
                        // Latch combinacional para evitar glitches
                        latch_color <= tok_color;
                        latch_z     <= tok_z;
                        latch_addr  <= calc_addr;
                        latch_zidx  <= z_idx;
                        latch_ok    <= tok_valid & in_bounds & z_pass;
                        state       <= ST_TEST;
                    end
                end

                ST_TEST: begin
                    if (latch_ok) begin
                        state <= ST_WRITE;
                    end else begin
                        fragments_discarded <= fragments_discarded + 16'd1;
                        state <= ST_DONE;
                    end
                end

                ST_WRITE: begin
                    pixel_color              <= latch_color;
                    pixel_addr               <= latch_addr;
                    pixel_write              <= 1'b1;
                    z_buf[latch_zidx]        <= latch_z;
                    fragments_written        <= fragments_written + 16'd1;
                    state                    <= ST_DONE;
                end

                ST_DONE: begin
                    frag_ready <= 1'b1;
                    state      <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule