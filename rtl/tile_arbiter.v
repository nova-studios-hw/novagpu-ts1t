`timescale 1ns/1ps
// ============================================================
// tile_arbiter.v — Árbitro de Tile v10 (CORREGIDO)
// NovaGPU TS 1T — Maximal Technology / Nova Studios
//
// FIX v10 (Auditoría):
//   PROBLEMA: Loop de reset de 307,200 iteraciones (bloquea síntesis).
//   SOLUCIÓN: Estrategia de "Dirty Bit" por tile.
//   - Se mantiene un registro 'z_dirty' de 1 bit por cada tile (80 bits).
//   - En reset, solo se limpian los dirty bits.
//   - Al leer Z, si el tile no está dirty, se asume Z = 0xFFFFFFFF.
//   - Al escribir Z, se marca el tile como dirty.
// ============================================================

module tile_arbiter #(
  parameter DATA_WIDTH   = 128,
  parameter SCREEN_W     = 640,
  parameter SCREEN_H     = 480,
  parameter TILE_SIZE    = 8,
  parameter Z_WIDTH      = 32,
  parameter COLOR_WIDTH  = 32
)(
  input  wire                    clk,
  input  wire                    rst_n,

  input  wire  [DATA_WIDTH-1:0]  frag_in,
  input  wire                    frag_valid,
  output reg                     frag_ready,

  output reg   [COLOR_WIDTH-1:0] pixel_color,
  output reg   [18:0]            pixel_addr,
  output reg                     pixel_write,

  output reg   [15:0]            fragments_written,
  output reg   [15:0]            fragments_discarded
);

  // ── EXTRAER CAMPOS DEL TOKEN ──────────────────────────────
  wire [31:0] color_in = frag_in[127:96];
  wire [31:0] z_in     = frag_in[95:64];
  wire [7:0]  pixel_x  = frag_in[31:24];
  wire [7:0]  pixel_y  = frag_in[23:16];

  // ── DIRECCIÓN DE FRAMEBUFFER ──────────────────────────────
  wire [18:0] fb_addr = ({11'b0, pixel_y} * SCREEN_W[18:0]) + {11'b0, pixel_x};

  // ── TILE ID ───────────────────────────────────────────────
  localparam TILES_X     = SCREEN_W / TILE_SIZE;
  localparam TILES_Y     = SCREEN_H / TILE_SIZE;
  localparam NUM_TILES   = TILES_X * TILES_Y;

  wire [7:0] tile_x  = {2'b0, pixel_x[7:3]};  // pixel_x / 8
  wire [7:0] tile_y  = {2'b0, pixel_y[7:3]};  // pixel_y / 8
  wire [15:0] tile_id = ({8'b0, tile_y} * TILES_X[15:0]) + {8'b0, tile_x};

  // ── Z-BUFFER LOCAL ────────────────────────────────────────
  reg [Z_WIDTH-1:0] z_buffer [0:SCREEN_W*SCREEN_H-1];

  // ── DIRTY BITS (FIX v10) ──────────────────────────────────
  reg z_dirty [0:NUM_TILES-1];

  // ── LOCK DE TILE ──────────────────────────────────────────
  reg tile_locked;
  reg [15:0] locked_tile_id;

  wire tile_conflict = frag_valid && tile_locked &&
                       (tile_id == locked_tile_id);

  // ── ESTADOS ───────────────────────────────────────────────
  localparam ST_IDLE    = 2'd0;
  localparam ST_ZTEST   = 2'd1;
  localparam ST_WRITE   = 2'd2;
  localparam ST_DISCARD = 2'd3;

  reg [1:0] state;

  reg [DATA_WIDTH-1:0] frag_reg;
  reg [31:0]           z_current;
  reg [18:0]           addr_reg;
  reg [15:0]           tile_reg;

  wire [31:0] z_reg_in  = frag_reg[95:64];
  wire [31:0] color_reg = frag_reg[127:96];
  wire [7:0]  x_reg     = frag_reg[31:24];
  wire [7:0]  y_reg     = frag_reg[23:16];

  wire z_pass = (z_reg_in < z_current);

  integer ti;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state               <= ST_IDLE;
      frag_ready          <= 1'b1;
      pixel_write         <= 1'b0;
      pixel_color         <= 32'h0;
      pixel_addr          <= 19'h0;
      addr_reg            <= 19'h0;
      tile_reg            <= 16'h0;
      frag_reg            <= {DATA_WIDTH{1'b0}};
      z_current           <= {Z_WIDTH{1'b1}};
      tile_locked         <= 1'b0;
      locked_tile_id      <= 16'h0;
      fragments_written   <= 16'd0;
      fragments_discarded <= 16'd0;
      
      // FIX v10: Solo resetear dirty bits (80 entradas), no 307,200
      for (ti = 0; ti < NUM_TILES; ti = ti + 1)
        z_dirty[ti] <= 1'b0;

    end else begin

      case (state)

        ST_IDLE: begin
          pixel_write <= 1'b0;
          tile_locked <= 1'b0;
          frag_ready  <= 1'b1;

          if (frag_valid && !tile_conflict) begin
            frag_reg       <= frag_in;
            addr_reg       <= fb_addr;
            tile_reg       <= tile_id;
            frag_ready     <= 1'b0;
            tile_locked    <= 1'b1;
            locked_tile_id <= tile_id;
            state          <= ST_ZTEST;
          end
        end

        ST_ZTEST: begin
          // FIX v10: Si el tile no está dirty, retornar Z máximo
          z_current <= z_dirty[tile_reg] ? z_buffer[addr_reg] : {Z_WIDTH{1'b1}};
          state     <= ST_WRITE;
        end

        ST_WRITE: begin
          if (z_pass) begin
            z_buffer[addr_reg] <= z_reg_in;
            z_dirty[tile_reg]  <= 1'b1; // Marcar como dirty al escribir
            pixel_color        <= color_reg;
            pixel_addr         <= addr_reg;
            pixel_write        <= 1'b1;
            fragments_written  <= fragments_written + 16'd1;
          end else begin
            pixel_write         <= 1'b0;
            fragments_discarded <= fragments_discarded + 16'd1;
          end
          tile_locked <= 1'b0;
          state       <= ST_IDLE;
        end

        default: begin
          tile_locked <= 1'b0;
          state       <= ST_IDLE;
        end
      endcase
    end
  end

endmodule

// Copyright (c) 2025 Nova Studios / Maximal Technology
// SPDX-License-Identifier: MIT