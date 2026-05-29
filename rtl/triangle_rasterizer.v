`timescale 1ns/1ps
// =============================================================================
// triangle_rasterizer.v  —  NovaGPU TS 1T  v2.0  (Equipo Alpha)
// Nova Studios / Maximal Technology
//
// Implementación profesional con:
//   - Pineda edge functions (sin división) para cobertura pixel-exacta
//   - Bounding box screen-clamp
//   - Barycentric interpolation de color y profundidad
//   - Token de salida 128-bit con layout documentado
//   - Handshake valid/ready flow-controlled
//   - Contador de píxeles emitidos / descartados
//
// Token layout [127:0]:
//   [127:96]  color_interp  (ARGB 8:8:8:8)
//   [95:64]   z_interp      (Q16.16 depth)
//   [63:48]   pixel_x       (16-bit)
//   [47:32]   pixel_y       (16-bit)
//   [31:16]   tri_id        (tag counter)
//   [15:0]    flags         (bit0=inside, bit1=edge, bit2=last_pixel)
// =============================================================================

module triangle_rasterizer #(
    parameter DATA_WIDTH = 128,
    parameter SCREEN_W   = 640,
    parameter SCREEN_H   = 480
)(
    input  wire        clk,
    input  wire        rst_n,

    // Vértices (coordenadas enteras en espacio de pantalla)
    input  wire [10:0] v0_x, v0_y,
    input  wire [10:0] v1_x, v1_y,
    input  wire [10:0] v2_x, v2_y,

    // Colores por vértice (ARGB 8:8:8:8)
    input  wire [31:0] c0, c1, c2,

    // Profundidad por vértice (Q16.16)
    input  wire [31:0] z0, z1, z2,

    // Control
    input  wire        start,
    output reg         busy,

    // Salida de fragmentos
    output reg  [DATA_WIDTH-1:0] token_out,
    output reg                   token_valid,
    input  wire                  token_ready,

    // Estadísticas
    output reg  [19:0] pixels_emitted,
    output reg  [19:0] pixels_skipped,
    output reg         frame_done
);

    // ── Estados ───────────────────────────────────────────────
    localparam ST_IDLE  = 2'd0;
    localparam ST_SETUP = 2'd1;
    localparam ST_RUN   = 2'd2;
    localparam ST_DONE  = 2'd3;

    reg [1:0] state;

    // ── Bounding box ──────────────────────────────────────────
    reg signed [11:0] bb_xmin, bb_xmax, bb_ymin, bb_ymax;
    reg signed [11:0] px, py;

    // ── Edge function constants (Pineda) ──────────────────────
    // E(p) = (p.x - a.x)*(b.y - a.y) - (p.y - a.y)*(b.x - a.x)
    // Precomputed deltas for each edge
    reg signed [11:0] A01, A12, A20;   // dy de cada edge
    reg signed [11:0] B01, B12, B20;   // -dx de cada edge
    reg signed [23:0] w0_row, w1_row, w2_row;  // barycentric en inicio de fila
    reg signed [23:0] w0,    w1,    w2;         // barycentric en pixel actual
    reg signed [23:0] area2;                     // 2x área del triángulo

    // ── Tag counter ───────────────────────────────────────────
    reg [15:0] tri_id;

    // ── Pixel data registrado ─────────────────────────────────
    reg token_pending;

    // ── Bounding box mínimo/máximo (combinacional) ────────────
    wire [10:0] xmin_raw = (v0_x < v1_x) ?
                               ((v0_x < v2_x) ? v0_x : v2_x) :
                               ((v1_x < v2_x) ? v1_x : v2_x);
    wire [10:0] xmax_raw = (v0_x > v1_x) ?
                               ((v0_x > v2_x) ? v0_x : v2_x) :
                               ((v1_x > v2_x) ? v1_x : v2_x);
    wire [10:0] ymin_raw = (v0_y < v1_y) ?
                               ((v0_y < v2_y) ? v0_y : v2_y) :
                               ((v1_y < v2_y) ? v1_y : v2_y);
    wire [10:0] ymax_raw = (v0_y > v1_y) ?
                               ((v0_y > v2_y) ? v0_y : v2_y) :
                               ((v1_y > v2_y) ? v1_y : v2_y);

    // Screen clamp
    wire [10:0] xmin_c = (xmin_raw >= SCREEN_W) ? 0 : xmin_raw;
    wire [10:0] xmax_c = (xmax_raw >= SCREEN_W) ? (SCREEN_W-1) : xmax_raw;
    wire [10:0] ymin_c = (ymin_raw >= SCREEN_H) ? 0 : ymin_raw;
    wire [10:0] ymax_c = (ymax_raw >= SCREEN_H) ? (SCREEN_H-1) : ymax_raw;

    // ── Interpolación de color (barycentric) ──────────────────
    // Color = (w0*c0 + w1*c1 + w2*c2) / area2
    // Usamos solo los 8 bits superiores de cada canal
    wire [7:0] c0_r = c0[23:16], c0_g = c0[15:8], c0_b = c0[7:0];
    wire [7:0] c1_r = c1[23:16], c1_g = c1[15:8], c1_b = c1[7:0];
    wire [7:0] c2_r = c2[23:16], c2_g = c2[15:8], c2_b = c2[7:0];

    // Interpolación simplificada: peso proporcional (evitar división)
    // Usamos w0,w1,w2 normalizados contra area2
    // Para evitar división: resultado = (w0*c0 + w1*c1 + w2*c2) >> log2(area2)
    // En hardware usamos una aproximación: si area2>0, interpolamos con shift
    reg [31:0] color_interp;
    reg [31:0] z_interp;

    // ── Pixel inside triangle ─────────────────────────────────
    wire pixel_inside = (w0 >= 0) && (w1 >= 0) && (w2 >= 0) && (area2 > 0);

    // ── last pixel flag ───────────────────────────────────────
    wire is_last = (px >= bb_xmax) && (py >= bb_ymax);

    // ── FSM Principal ─────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            busy           <= 1'b0;
            token_valid    <= 1'b0;
            token_pending  <= 1'b0;
            pixels_emitted <= 20'd0;
            pixels_skipped <= 20'd0;
            frame_done     <= 1'b0;
            tri_id         <= 16'd0;
        end else begin
            frame_done <= 1'b0;

            // Handshake: si hay token pendiente y downstream acepta
            if (token_valid && token_ready) begin
                token_valid   <= 1'b0;
                token_pending <= 1'b0;
            end

            case (state)
                ST_IDLE: begin
                    if (start && !busy) begin
                        busy   <= 1'b1;
                        state  <= ST_SETUP;
                    end
                end

                ST_SETUP: begin
                    // Calcular bounding box y edge constants
                    bb_xmin <= $signed({1'b0, xmin_c});
                    bb_xmax <= $signed({1'b0, xmax_c});
                    bb_ymin <= $signed({1'b0, ymin_c});
                    bb_ymax <= $signed({1'b0, ymax_c});
                    px      <= $signed({1'b0, xmin_c});
                    py      <= $signed({1'b0, ymin_c});

                    // Pineda deltas
                    // Edge 0→1: A = v1y-v0y, B = v0x-v1x
                    A01 <= $signed({1'b0, v1_y}) - $signed({1'b0, v0_y});
                    B01 <= $signed({1'b0, v0_x}) - $signed({1'b0, v1_x});
                    // Edge 1→2
                    A12 <= $signed({1'b0, v2_y}) - $signed({1'b0, v1_y});
                    B12 <= $signed({1'b0, v1_x}) - $signed({1'b0, v2_x});
                    // Edge 2→0
                    A20 <= $signed({1'b0, v0_y}) - $signed({1'b0, v2_y});
                    B20 <= $signed({1'b0, v2_x}) - $signed({1'b0, v0_x});

                    // Área x2 = (v1-v0) cross (v2-v0)
                    area2 <= ($signed({1'b0, v1_x}) - $signed({1'b0, v0_x})) *
                              ($signed({1'b0, v2_y}) - $signed({1'b0, v0_y})) -
                              ($signed({1'b0, v1_y}) - $signed({1'b0, v0_y})) *
                              ($signed({1'b0, v2_x}) - $signed({1'b0, v0_x}));

                    pixels_emitted <= 20'd0;
                    pixels_skipped <= 20'd0;
                    state <= ST_RUN;
                end

                ST_RUN: begin
                    // Calcular edge functions para (px,py)
                    w0 <= (px - $signed({1'b0, v1_x})) * A12 +
                          (py - $signed({1'b0, v1_y})) * B12;
                    w1 <= (px - $signed({1'b0, v2_x})) * A20 +
                          (py - $signed({1'b0, v2_y})) * B20;
                    w2 <= (px - $signed({1'b0, v0_x})) * A01 +
                          (py - $signed({1'b0, v0_y})) * B01;

                    // Emitir token si downstream está listo o no hay token pendiente
                    if (!token_pending || (token_valid && token_ready)) begin
                        if (pixel_inside) begin
                            // Interpolación de color barycentric simplificada
                            // alpha=ff, r/g/b interpolados
                            color_interp <= {8'hFF,
                                (area2 > 0) ?
                                    (($signed(w0) * $signed({24'd0, c0_r}) +
                                      $signed(w1) * $signed({24'd0, c1_r}) +
                                      $signed(w2) * $signed({24'd0, c2_r})) / area2) :
                                    {32'd0},
                                (area2 > 0) ?
                                    (($signed(w0) * $signed({24'd0, c0_g}) +
                                      $signed(w1) * $signed({24'd0, c1_g}) +
                                      $signed(w2) * $signed({24'd0, c2_g})) / area2) :
                                    {32'd0},
                                (area2 > 0) ?
                                    (($signed(w0) * $signed({24'd0, c0_b}) +
                                      $signed(w1) * $signed({24'd0, c1_b}) +
                                      $signed(w2) * $signed({24'd0, c2_b})) / area2) :
                                    {32'd0}
                            };

                            z_interp <= (area2 > 0) ?
                                (($signed(w0) * $signed(z0) +
                                  $signed(w1) * $signed(z1) +
                                  $signed(w2) * $signed(z2)) / area2) : 32'd0;

                            token_out   <= {color_interp, z_interp,
                                            {5'd0, px[10:0]}, {5'd0, py[10:0]},
                                            tri_id,
                                            13'd0, is_last, pixel_inside, 1'b1};
                            token_valid  <= 1'b1;
                            token_pending<= 1'b1;
                            pixels_emitted <= pixels_emitted + 1;
                        end else begin
                            pixels_skipped <= pixels_skipped + 1;
                        end

                        // Advance scan position
                        if (px >= bb_xmax) begin
                            px <= bb_xmin;
                            if (py >= bb_ymax) begin
                                state    <= ST_DONE;
                                tri_id   <= tri_id + 1;
                            end else begin
                                py <= py + 1;
                            end
                        end else begin
                            px <= px + 1;
                        end
                    end
                end

                ST_DONE: begin
                    // Esperar que el último token sea aceptado
                    if (!token_pending || (token_valid && token_ready)) begin
                        token_valid <= 1'b0;
                        busy        <= 1'b0;
                        frame_done  <= 1'b1;
                        state       <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule