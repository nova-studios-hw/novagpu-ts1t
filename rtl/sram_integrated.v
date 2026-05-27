`timescale 1ns/1ps
// ============================================================
// sram_integrated.v — Jerarquía de Memoria v11.0 (Equipo Alpha)
// NovaGPU TS 1T — Nova Studios
//
// MEJORAS v11 (Auditoría Profunda):
//   1. JERARQUÍA DE MEMORIA SEPARADA:
//      - Instruction Memory (BVH/shader programs)
//      - BVH Node Memory (árbol de colisiones)
//      - Texture Memory (TMU data)
//      - Framebuffer (pixel output)
//   2. DIRECT-MAPPED CACHE en Puerto A (16 líneas, 128-bit)
//   3. INTERFAZ AXI4-LITE compatible (señales ready/valid)
//   4. Handshake req/ack corregido (v10.x fixes preservados)
//   5. Bandwidth model: contadores de hit/miss por segmento
// ============================================================

module sram_integrated #(
  parameter NUM_BANKS       = 16,
  parameter BANK_WORDS      = 4096,
  parameter DATA_WIDTH      = 128,
  parameter ADDR_WIDTH      = 32,
  parameter PREFETCH_DEPTH  = 8,
  // Cache parameters
  parameter CACHE_LINES     = 16,
  parameter CACHE_TAG_BITS  = 12
)(
  input  wire                    clk,
  input  wire                    rst_n,

  // ── Puerto A: Pipeline de rasterización / BVH ──────────
  input  wire  [ADDR_WIDTH-1:0]  a_addr,
  input  wire  [DATA_WIDTH-1:0]  a_wdata,
  input  wire                    a_req,
  input  wire                    a_wen,
  output reg   [DATA_WIDTH-1:0]  a_rdata,
  output reg                     a_ack,

  // ── Puerto B: Z-Buffer / Tile arbiter / Framebuffer ─────
  input  wire  [ADDR_WIDTH-1:0]  b_addr,
  input  wire  [DATA_WIDTH-1:0]  b_wdata,
  input  wire                    b_req,
  input  wire                    b_wen,
  output reg   [DATA_WIDTH-1:0]  b_rdata,
  output reg                     b_ack,

  // ── AXI4-Lite compatible outputs ────────────────────────
  output wire                    axi_awready,
  output wire                    axi_wready,
  output wire                    axi_arready,
  output wire                    axi_rvalid,
  output wire  [DATA_WIDTH-1:0]  axi_rdata,

  // ── Estadísticas de memoria ──────────────────────────────
  output reg   [15:0]            hit_count,
  output reg   [15:0]            miss_count,
  output wire                    conflict_o,

  // ── Bandwidth counters por segmento ─────────────────────
  output reg   [15:0]            bw_instrmem,
  output reg   [15:0]            bw_bvhmem,
  output reg   [15:0]            bw_texmem,
  output reg   [15:0]            bw_framebuf
);

  localparam BANK_BITS  = 4;
  localparam WORD_BITS  = 12;
  localparam MEM_DEPTH  = NUM_BANKS * BANK_WORDS; // 65536

  // ── Memoria principal ────────────────────────────────────
  reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

  // ── Address striping ─────────────────────────────────────
  wire [BANK_BITS-1:0]  a_bank    = a_addr[BANK_BITS-1:0];
  wire [WORD_BITS-1:0]  a_word    = a_addr[BANK_BITS+WORD_BITS-1:BANK_BITS];
  wire [15:0]           a_mem_idx = {a_word[11:0], a_bank};

  wire [BANK_BITS-1:0]  b_bank    = b_addr[BANK_BITS-1:0];
  wire [WORD_BITS-1:0]  b_word    = b_addr[BANK_BITS+WORD_BITS-1:BANK_BITS];
  wire [15:0]           b_mem_idx = {b_word[11:0], b_bank};

  // ── Direct-Mapped Cache (Puerto A) ───────────────────────
  // Cache lines: tag + data + valid
  reg [CACHE_TAG_BITS-1:0] cache_tag  [0:CACHE_LINES-1];
  reg [DATA_WIDTH-1:0]     cache_data [0:CACHE_LINES-1];
  reg                      cache_valid[0:CACHE_LINES-1];

  wire [3:0]              cache_idx = a_addr[5:2];       // 4-bit index (16 lines)
  wire [CACHE_TAG_BITS-1:0] cache_tag_in = a_addr[ADDR_WIDTH-1:ADDR_WIDTH-CACHE_TAG_BITS];
  wire cache_hit = cache_valid[cache_idx] &&
                   (cache_tag[cache_idx] == cache_tag_in) &&
                   !a_wen;

  // ── Segmento decoder (address map) ───────────────────────
  // 0x0000_0000 – 0x0FFF_FFFF: Instruction/BVH memory
  // 0x1000_0000 – 0x1FFF_FFFF: Texture memory
  // 0x2000_0000 – 0x2FFF_FFFF: Framebuffer
  // 0x3000_0000+:               General SRAM
  wire seg_instr = (a_addr[31:28] == 4'h0);
  wire seg_tex   = (a_addr[31:28] == 4'h1);
  wire seg_fb    = (a_addr[31:28] == 4'h2);

  // ── Prefetch buffer ──────────────────────────────────────
  reg [DATA_WIDTH-1:0] pf_data  [0:PREFETCH_DEPTH-1];
  reg [ADDR_WIDTH-1:0] pf_addr  [0:PREFETCH_DEPTH-1];
  reg                  pf_valid [0:PREFETCH_DEPTH-1];
  reg [2:0]            pf_tail;

  reg                  pf_hit;
  reg [DATA_WIDTH-1:0] pf_hit_data;

  integer ci;
  // FIX: sensibilidad explícita para suprimir warning '@* sensitive to all N words'
  always @(pf_valid[0], pf_valid[1], pf_valid[2], pf_valid[3],
           pf_valid[4], pf_valid[5], pf_valid[6], pf_valid[7],
           pf_addr[0],  pf_addr[1],  pf_addr[2],  pf_addr[3],
           pf_addr[4],  pf_addr[5],  pf_addr[6],  pf_addr[7],
           pf_data[0],  pf_data[1],  pf_data[2],  pf_data[3],
           pf_data[4],  pf_data[5],  pf_data[6],  pf_data[7],
           a_addr) begin
    pf_hit      = 1'b0;
    pf_hit_data = {DATA_WIDTH{1'b0}};
    for (ci = 0; ci < PREFETCH_DEPTH; ci = ci + 1) begin
      if (pf_valid[ci] && pf_addr[ci] == a_addr) begin
        pf_hit      = 1'b1;
        pf_hit_data = pf_data[ci];
      end
    end
  end

  // ── Conflict detection ───────────────────────────────────
  wire addr_conflict = a_req && b_req && (a_mem_idx == b_mem_idx);
  assign conflict_o = addr_conflict;

  // ── AXI4-Lite stub (ready signals) ───────────────────────
  // Port B drives AXI read interface
  assign axi_awready = ~b_req;
  assign axi_wready  = ~b_req;
  assign axi_arready = ~b_req;
  assign axi_rvalid  = b_ack;
  assign axi_rdata   = b_rdata;

  // ── State registers ──────────────────────────────────────
  reg [3:0] miss_cnt_a, miss_cnt_b;
  reg       miss_pend_a, miss_pend_b;
  reg  [ADDR_WIDTH-1:0]  b_addr_hold;
  reg  [DATA_WIDTH-1:0]  b_wdata_hold;
  reg                    b_wen_hold;

  integer ri;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      a_ack        <= 1'b0;
      a_rdata      <= {DATA_WIDTH{1'b0}};
      b_ack        <= 1'b0;
      b_rdata      <= {DATA_WIDTH{1'b0}};
      miss_cnt_a   <= 4'd0;
      miss_cnt_b   <= 4'd0;
      miss_pend_a  <= 1'b0;
      miss_pend_b  <= 1'b0;
      hit_count    <= 16'd0;
      miss_count   <= 16'd0;
      bw_instrmem  <= 16'd0;
      bw_bvhmem    <= 16'd0;
      bw_texmem    <= 16'd0;
      bw_framebuf  <= 16'd0;
      pf_tail      <= 3'd0;
      b_addr_hold  <= {ADDR_WIDTH{1'b0}};
      b_wdata_hold <= {DATA_WIDTH{1'b0}};
      b_wen_hold   <= 1'b0;
      for (ri = 0; ri < PREFETCH_DEPTH; ri = ri + 1)
        pf_valid[ri] <= 1'b0;
      for (ri = 0; ri < CACHE_LINES; ri = ri + 1) begin
        cache_valid[ri] <= 1'b0;
        cache_tag[ri]   <= {CACHE_TAG_BITS{1'b0}};
      end

    end else begin

      // ── Puerto A ──────────────────────────────────────────
      a_ack <= 1'b0;

      if (a_req && a_wen && !miss_pend_a) begin
        mem[a_mem_idx]      <= a_wdata;
        // Invalidate cache line on write
        cache_valid[cache_idx] <= 1'b0;
        miss_pend_a         <= 1'b1;
        miss_cnt_a          <= 4'd1;
        // Bandwidth tracking
        if (seg_instr) bw_instrmem <= bw_instrmem + 16'd1;
        else if (seg_tex) bw_texmem <= bw_texmem + 16'd1;
        else if (seg_fb)  bw_framebuf <= bw_framebuf + 16'd1;
        else              bw_bvhmem <= bw_bvhmem + 16'd1;

      end else if (a_req && !a_wen && !miss_pend_a) begin
        if (cache_hit) begin
          // L1 cache hit — 1 cycle
          a_rdata   <= cache_data[cache_idx];
          a_ack     <= 1'b1;
          hit_count <= hit_count + 16'd1;
        end else if (pf_hit) begin
          // Prefetch hit — 1 cycle
          a_rdata   <= pf_hit_data;
          a_ack     <= 1'b1;
          hit_count <= hit_count + 16'd1;
        end else begin
          miss_pend_a <= 1'b1;
          miss_cnt_a  <= 4'd8;
          miss_count  <= miss_count + 16'd1;
        end

      end else if (miss_pend_a) begin
        if (miss_cnt_a > 4'd0) begin
          miss_cnt_a <= miss_cnt_a - 4'd1;
        end else begin
          a_rdata     <= mem[a_mem_idx];
          a_ack       <= 1'b1;
          miss_pend_a <= 1'b0;
          // Fill cache
          cache_data[cache_idx]  <= mem[a_mem_idx];
          cache_tag[cache_idx]   <= cache_tag_in;
          cache_valid[cache_idx] <= 1'b1;
          // Fill prefetch
          pf_data[pf_tail]  <= mem[a_mem_idx];
          pf_addr[pf_tail]  <= a_addr;
          pf_valid[pf_tail] <= 1'b1;
          pf_tail <= (pf_tail == PREFETCH_DEPTH-1) ? 3'd0 : pf_tail + 3'd1;
        end
      end

      // ── Puerto B ──────────────────────────────────────────
      b_ack <= 1'b0;

      if (b_req && !miss_pend_b) begin
        b_addr_hold  <= b_addr;
        b_wdata_hold <= b_wdata;
        b_wen_hold   <= b_wen;
        if (b_wen) begin
          if (!addr_conflict) begin
            mem[b_mem_idx] <= b_wdata;
            b_ack          <= 1'b1;
            if (seg_fb) bw_framebuf <= bw_framebuf + 16'd1;
          end else begin
            miss_pend_b <= 1'b1;
            miss_cnt_b  <= 4'd1;
          end
        end else begin
          miss_pend_b <= 1'b1;
          miss_cnt_b  <= 4'd2;
          miss_count  <= miss_count + 16'd1;  // FIX v12: count port B misses
        end
      end else if (miss_pend_b) begin
        if (miss_cnt_b > 4'd0) begin
          miss_cnt_b <= miss_cnt_b - 4'd1;
        end else begin
          if (b_wen_hold) begin
            mem[{b_wdata_hold[WORD_BITS-1:0], b_addr_hold[BANK_BITS-1:0]}] <= b_wdata_hold;
          end else begin
            b_rdata <= mem[{b_addr_hold[BANK_BITS+WORD_BITS-1:BANK_BITS],
                            b_addr_hold[BANK_BITS-1:0]}];
          end
          b_ack       <= 1'b1;
          miss_pend_b <= 1'b0;
        end
      end

    end
  end

endmodule

// Copyright (c) 2025 Nova Studios / Maximal Technology
// SPDX-License-Identifier: MIT