`timescale 1ns/1ps
// =============================================================================
// tmu.v  —  Token Matching Unit  v3.0
// NovaGPU TS 2T  —  Nova Studios / Maximal Technology
//
// Arquitectura Match-and-Fire:
//   - Cada token lleva TAG de 16 bits
//   - Primer token del par → almacenado en slot (TAG % NUM_SETS)
//   - Segundo token con mismo TAG → dispara fire con ambos operandos
//   - Timeout por slot para evitar deadlocks
//   - Backpressure mediante in_ready
//
// Correcciones v3.0:
//   - SET_BITS correctamente calculado con $clog2
//   - TO_BITS alineado para evitar overflow
//   - fire_valid limpiado en el ciclo post-fire (no acumulativo)
// =============================================================================

module token_matching_unit #(
    parameter NUM_SLOTS  = 64,
    parameter TAG_WIDTH  = 16,
    parameter DATA_WIDTH = 128,
    parameter TIMEOUT    = 1024
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // Input stream
    input  wire [TAG_WIDTH-1:0]    in_tag,
    input  wire [DATA_WIDTH-1:0]   in_data,
    input  wire                    in_valid,
    output reg                     in_ready,

    // Fire output
    output reg  [TAG_WIDTH-1:0]    fire_tag,
    output reg  [DATA_WIDTH-1:0]   fire_data_a,
    output reg  [DATA_WIDTH-1:0]   fire_data_b,
    output reg                     fire_valid,

    // Ocupación
    output wire [TAG_WIDTH-1:0]    occupancy
);

    localparam NUM_SETS  = NUM_SLOTS / 2;
    localparam SET_BITS  = $clog2(NUM_SETS);
    localparam TO_BITS   = $clog2(TIMEOUT + 1);

    // ── Slots ─────────────────────────────────────────────────
    reg                   slot_valid [0:NUM_SETS-1];
    reg [TAG_WIDTH-1:0]   slot_tag   [0:NUM_SETS-1];
    reg [DATA_WIDTH-1:0]  slot_data  [0:NUM_SETS-1];
    reg [TO_BITS-1:0]     slot_timer [0:NUM_SETS-1];

    // ── Ocupación ─────────────────────────────────────────────
    reg [TAG_WIDTH-1:0] occ_cnt;
    assign occupancy = occ_cnt;

    // ── Set index ─────────────────────────────────────────────
    wire [SET_BITS-1:0] set_idx = in_tag[SET_BITS-1:0];

    wire slot_match = slot_valid[set_idx] & (slot_tag[set_idx] == in_tag);
    wire slot_empty = ~slot_valid[set_idx];

    // ── Timeout scanner (un slot por ciclo) ───────────────────
    reg [SET_BITS-1:0] scan_ptr;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fire_valid <= 1'b0;
            in_ready   <= 1'b1;
            occ_cnt    <= {TAG_WIDTH{1'b0}};
            scan_ptr   <= {SET_BITS{1'b0}};
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                slot_valid[i] <= 1'b0;
                slot_tag[i]   <= {TAG_WIDTH{1'b0}};
                slot_data[i]  <= {DATA_WIDTH{1'b0}};
                slot_timer[i] <= {TO_BITS{1'b0}};
            end
        end else begin
            // Default: bajar fire_valid
            fire_valid <= 1'b0;

            // ── Match-and-Fire ─────────────────────────────────
            if (in_valid && in_ready) begin
                if (slot_match) begin
                    // Par completo → FIRE
                    fire_tag              <= in_tag;
                    fire_data_a           <= slot_data[set_idx];
                    fire_data_b           <= in_data;
                    fire_valid            <= 1'b1;
                    slot_valid[set_idx]   <= 1'b0;
                    slot_timer[set_idx]   <= {TO_BITS{1'b0}};
                    if (occ_cnt > {TAG_WIDTH{1'b0}})
                        occ_cnt <= occ_cnt - {{(TAG_WIDTH-1){1'b0}}, 1'b1};
                end else if (slot_empty) begin
                    // Primer token → almacenar
                    slot_valid[set_idx]   <= 1'b1;
                    slot_tag[set_idx]     <= in_tag;
                    slot_data[set_idx]    <= in_data;
                    slot_timer[set_idx]   <= {TO_BITS{1'b0}};
                    occ_cnt               <= occ_cnt + {{(TAG_WIDTH-1){1'b0}}, 1'b1};
                end
                // Colisión de slot con otro TAG: descartado (sin deadlock)
            end

            // ── Timeout scan ───────────────────────────────────
            if (slot_valid[scan_ptr]) begin
                if (slot_timer[scan_ptr] >= TIMEOUT[TO_BITS-1:0]) begin
                    slot_valid[scan_ptr] <= 1'b0;
                    slot_timer[scan_ptr] <= {TO_BITS{1'b0}};
                    if (occ_cnt > {TAG_WIDTH{1'b0}})
                        occ_cnt <= occ_cnt - {{(TAG_WIDTH-1){1'b0}}, 1'b1};
                end else begin
                    slot_timer[scan_ptr] <= slot_timer[scan_ptr] +
                                            {{(TO_BITS-1){1'b0}}, 1'b1};
                end
            end

            scan_ptr <= (scan_ptr == NUM_SETS - 1) ?
                        {SET_BITS{1'b0}} : scan_ptr + {{(SET_BITS-1){1'b0}}, 1'b1};

            // ── Backpressure ────────────────────────────────────
            in_ready <= (occ_cnt < (NUM_SETS - 1));
        end
    end

endmodule