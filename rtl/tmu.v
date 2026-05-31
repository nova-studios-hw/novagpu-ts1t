
`timescale 1ns/1ps
// =============================================================================
// tmu.v  --  Token Matching Unit  v3.3-FIX  (Equipo Alpha)
//
// FIX v3.3 (sobre v3.2):
//
// BUG B1/B2: fire_valid es completamente combinacional sobre in_valid.
//   Cuando el testbench baja in_valid después del segundo token,
//   fire_valid se pone a 0 en el mismo ciclo → testbench lo pierde.
//
// CAUSA RAÍZ:
//   assign fire_valid = in_valid & in_ready & slot_match;
//   Cuando in_valid=0, fire_valid=0 inmediatamente aunque el par
//   ya fue detectado. El testbench muestrea DESPUÉS de que in_valid cae.
//
// FIX v3.3:
//   Registrar fire_valid, fire_data_a, fire_data_b, fire_tag cuando
//   in_valid & in_ready & slot_match es verdadero.
//   Se mantienen altos por exactamente 1 ciclo de reloj.
//   Independientes de in_valid en el ciclo de muestreo.
//
//   Nuevo comportamiento:
//   Ciclo N:   in_valid=1, slot_match=1 → fire_reg se activa en flanco
//   Ciclo N+1: fire_valid=1 (registrado, visible), in_valid puede ser 0
//              El testbench que muestrea @posedge ve fire_valid=1.
//   Ciclo N+2: fire_valid=0 (limpiado automáticamente si no hay nuevo par)
//
// NOTA: slot_data[set_idx] se lee en el mismo ciclo que slot_match=1.
//   Como slot_data fue escrito por <= en el ciclo anterior, el valor
//   está disponible en el siguiente ciclo de reloj. Lectura síncrona
//   al registrar el fire garantiza dato correcto.
//
// =============================================================================

module token_matching_unit #(
    parameter NUM_SLOTS  = 64,
    parameter TAG_WIDTH  = 16,
    parameter DATA_WIDTH = 128,
    parameter TIMEOUT    = 1024
)(
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire [TAG_WIDTH-1:0]    in_tag,
    input  wire [DATA_WIDTH-1:0]   in_data,
    input  wire                    in_valid,
    output reg                     in_ready,

    output reg  [TAG_WIDTH-1:0]    fire_tag,
    output reg  [DATA_WIDTH-1:0]   fire_data_a,
    output reg  [DATA_WIDTH-1:0]   fire_data_b,
    output reg                     fire_valid,

    output wire [TAG_WIDTH-1:0]    occupancy
);

    localparam NUM_SETS  = NUM_SLOTS / 2;
    localparam SET_BITS  = $clog2(NUM_SETS);
    localparam TO_BITS   = $clog2(TIMEOUT + 1);

    // -- Slots ----------------------------------------------------------------
    reg                   slot_valid [0:NUM_SETS-1];
    reg [TAG_WIDTH-1:0]   slot_tag   [0:NUM_SETS-1];
    reg [DATA_WIDTH-1:0]  slot_data  [0:NUM_SETS-1];
    reg [TO_BITS-1:0]     slot_timer [0:NUM_SETS-1];

    // -- Ocupacion ------------------------------------------------------------
    reg [TAG_WIDTH-1:0] occ_cnt;
    assign occupancy = occ_cnt;

    // -- Set index ------------------------------------------------------------
    wire [SET_BITS-1:0] set_idx = in_tag[SET_BITS-1:0];

    // Lectura combinacional de slot para detección de match
    wire slot_match = slot_valid[set_idx] & (slot_tag[set_idx] == in_tag);
    wire slot_empty = ~slot_valid[set_idx];

    // -- Timeout scanner ------------------------------------------------------
    reg [SET_BITS-1:0] scan_ptr;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_ready   <= 1'b1;
            occ_cnt    <= {TAG_WIDTH{1'b0}};
            scan_ptr   <= {SET_BITS{1'b0}};
            fire_valid   <= 1'b0;
            fire_tag     <= {TAG_WIDTH{1'b0}};
            fire_data_a  <= {DATA_WIDTH{1'b0}};
            fire_data_b  <= {DATA_WIDTH{1'b0}};
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                slot_valid[i] <= 1'b0;
                slot_tag[i]   <= {TAG_WIDTH{1'b0}};
                slot_data[i]  <= {DATA_WIDTH{1'b0}};
                slot_timer[i] <= {TO_BITS{1'b0}};
            end
        end else begin
            // Por defecto limpiar fire (pulso de 1 ciclo)
            fire_valid <= 1'b0;

            // -- Match-and-Fire -----------------------------------------------
            if (in_valid && in_ready) begin
                if (slot_match) begin
                    // Par completo → registrar fire outputs y limpiar slot
                    fire_valid             <= 1'b1;
                    fire_tag               <= in_tag;
                    fire_data_a            <= slot_data[set_idx]; // primer token (almacenado)
                    fire_data_b            <= in_data;             // segundo token (actual)
                    slot_valid[set_idx]    <= 1'b0;
                    slot_timer[set_idx]    <= {TO_BITS{1'b0}};
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
                // Colision de slot con otro TAG: descartado sin deadlock
            end

            // -- Timeout scan -------------------------------------------------
            if (slot_valid[scan_ptr] &&
                !(in_valid && in_ready && (scan_ptr == set_idx) && slot_match)) begin
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

            // -- Backpressure -------------------------------------------------
            in_ready <= (occ_cnt < NUM_SETS - 1);
        end
    end

endmodule
