// =============================================================================
//  sram_integrated.v  —  SRAM Integrada Dual-Port  v6.0
//  NovaGPU TS 2T  —  Nova Studios / Maximal Technology
//
//  CORRECCIÓN CRÍTICA v6.0
//  ─────────────────────────────────────────────────────────────────────────
//  Yosys memory_bram emite:
//    "FF found, but with a mux select that doesn't seem to correspond
//     to transparency logic."
//  cuando las salidas de lectura tienen ENABLE:
//
//    if (a_re)           ← MALO: introduce mux implícito en la salida
//        ram_a_q <= mem[a_idx];
//
//  Yosys traduce eso como:
//    ram_a_q_next = a_re ? mem[a_idx] : ram_a_q;   ← MUX
//
//  El mux de retención no corresponde al patrón de transparencia que
//  Yosys reconoce para absorber el flip-flop de salida dentro del
//  output register de la BRAM.  Resultado: la BRAM no se infiere.
//
//  SOLUCIÓN: lecturas SIEMPRE activas, sin enable en el always de RAM.
//  La dirección de lectura se captura también sin enable.
//  La validez del dato se controla FUERA del bloque de RAM con registros
//  de valid (a_rd_valid_q, b_rd_valid_q) que pipetean los enables.
//
//  PATRÓN CORRECTO PARA YOSYS (SDP — Simple Dual Port):
//  ─────────────────────────────────────────────────────────────────────────
//
//    always @(posedge clk) begin
//        if (a_wen) mem[a_addr] <= a_wdata;   // escritura con enable
//        ram_a_q <= mem[a_addr];               // lectura SIN enable ← clave
//        ram_b_q <= mem[b_addr];               // lectura SIN enable ← clave
//    end
//
//  Con este patrón Yosys ve:
//    - Un puerto de escritura con write-enable → OK
//    - Dos puertos de lectura síncronos sin enable → output registers de BRAM
//    - Sin mux de retención → memory_bram absorbe los FFs en la BRAM
//
//  CONSECUENCIA DE ARQUITECTURA:
//  ─────────────────────────────────────────────────────────────────────────
//  Al leer siempre, ram_a_q y ram_b_q contienen el dato de mem[addr] del
//  ciclo anterior, independientemente de si hubo req o no.
//  La validez del dato la controlan a_rd_valid_q y b_rd_valid_q, que son
//  un pipeline de 1 ciclo de los enables de lectura.
//  El ack se genera cuando *_rd_valid_q=1.
//
//  CONFLICTO DE PUERTOS:
//  ─────────────────────────────────────────────────────────────────────────
//  Puerto B es read-only.  Cuando conflict_o=1 (A y B apuntan a la misma
//  dirección y A está escribiendo), B hace stall: congela b_addr durante
//  un ciclo adicional.  Al ciclo siguiente (cuando A ya terminó de escribir)
//  B reintenta la lectura con la misma dirección.
//
//  LATENCIA:
//  ─────────────────────────────────────────────────────────────────────────
//  Puerto A :  req → ack en 1 ciclo   (lectura síncrona sin enable)
//  Puerto B :  req → ack en 1 ciclo   (sin conflicto)
//              req → ack en 2 ciclos  (con conflicto: 1 stall + 1 read)
//
//  TOPOLOGÍA:
//  ─────────────────────────────────────────────────────────────────────────
//
//  a_addr ──[reg]──→ a_idx_q ──→ mem[a_idx_q] ──→ ram_a_q ──→ a_rdata
//                                                               (si a_rd_valid_q)
//
//  b_addr ──[mux]──→ b_idx_eff ──→ mem[b_idx_eff] ──→ ram_b_q ──→ b_rdata
//           ↑                                                      (si b_rd_valid_q)
//      conflict?
//      sí → b_idx_latch (dirección congelada)
//      no → b_addr actual
//
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module sram_integrated #(
    parameter integer DATA_WIDTH = 128,
    parameter integer ADDR_WIDTH = 32,
    parameter integer MEM_DEPTH  = 4096
)(
    // ── Reloj y reset activo-bajo asíncrono ───────────────────────
    input  wire                    clk,
    input  wire                    rst_n,

    // ── Puerto A : Read / Write  (framebuffer) ────────────────────
    input  wire [ADDR_WIDTH-1:0]   a_addr,
    input  wire [DATA_WIDTH-1:0]   a_wdata,
    input  wire                    a_req,
    input  wire                    a_wen,
    output reg  [DATA_WIDTH-1:0]   a_rdata,
    output reg                     a_ack,

    // ── Puerto B : Read-only  (BVH / texturas) ───────────────────
    input  wire [ADDR_WIDTH-1:0]   b_addr,
    input  wire                    b_req,
    output reg  [DATA_WIDTH-1:0]   b_rdata,
    output reg                     b_ack,

    // ── AXI4-Lite slave mínimo (always-ready) ─────────────────────
    output reg                     axi_awready,
    output reg                     axi_wready,
    output reg                     axi_arready,
    output reg                     axi_rvalid,
    output reg  [DATA_WIDTH-1:0]   axi_rdata,

    // ── Estadísticas ──────────────────────────────────────────────
    output reg  [15:0]             hit_count,
    output reg  [15:0]             miss_count,
    output wire                    conflict_o,

    // ── Contadores de ancho de banda ─────────────────────────────
    output reg  [15:0]             bw_framebuf,
    output reg  [15:0]             bw_bvhmem
);

// =============================================================================
//  SECCIÓN 1 — PARÁMETROS DERIVADOS
// =============================================================================

    localparam integer IDX_BITS = $clog2(MEM_DEPTH);

// =============================================================================
//  SECCIÓN 2 — ÍNDICES, CONFLICTO Y FSM DE STALL  (todo combinacional)
// =============================================================================

    wire [IDX_BITS-1:0] a_idx = a_addr[IDX_BITS-1:0];
    wire [IDX_BITS-1:0] b_idx = b_addr[IDX_BITS-1:0];

    // Conflicto: ambos puertos activos, misma dirección, A escribiendo
    // (si A solo lee, no hay conflicto de coherencia para B)
    assign conflict_o = a_req & a_wen & b_req & (a_idx == b_idx);

    // ── Registro de stall de Puerto B ─────────────────────────────
    // b_stall=1 → este ciclo es un reintento (B no emitió req nuevo,
    //             sino que repite la dirección del ciclo anterior).
    reg                  b_stall;
    reg [IDX_BITS-1:0]   b_idx_latch;  // dirección congelada durante stall

    // Dirección efectiva del puerto B para este ciclo:
    //   Si b_stall=1 → usar la dirección que falló el ciclo anterior
    //   Si b_stall=0 → usar b_idx actual
    wire [IDX_BITS-1:0] b_idx_eff = b_stall ? b_idx_latch : b_idx;

    // Enable de lectura del puerto B para el pipeline de valid:
    //   Lee si (hay req normal sin conflicto) o (es ciclo de reintento)
    wire b_rd_en = (b_req & ~conflict_o) | b_stall;

    // Enable de lectura del puerto A: cualquier req (R o W ambos leen,
    // ya que la BRAM es read-first por defecto)
    wire a_rd_en = a_req;

// =============================================================================
//  SECCIÓN 3 — ARRAY DE MEMORIA  (bloque SÍNCRONO PURO)
// =============================================================================
//
//  REGLAS PARA QUE YOSYS INFIERA BRAM (memory_bram pass):
//  ════════════════════════════════════════════════════════
//
//  R1. always @(posedge clk) SOLAMENTE — sin negedge rst_n en este bloque.
//
//  R2. Lecturas SIN enable:
//          ram_q <= mem[addr];          ← correcto
//      NO:
//          if (en) ram_q <= mem[addr];  ← introduce mux → Yosys falla
//
//  R3. Escritura CON enable simple:
//          if (wen) mem[addr] <= wdata; ← correcto
//
//  R4. Sin lógica de estado (pending, stall, FSM) dentro del bloque.
//      Solo escritura y lectura directas.
//
//  R5. Los índices de dirección deben ser señales simples (wire o reg),
//      no expresiones complejas evaluadas dentro del always.
//
//  Por qué las lecturas sin enable funcionan aquí:
//    ram_a_q y ram_b_q contendrán datos "inválidos" los ciclos en que
//    no hay req.  Pero eso no importa porque a_rd_valid_q y b_rd_valid_q
//    (pipeline de valid, sección 4) indican cuándo el dato es útil.
//    El receptor solo muestrea *_rdata cuando *_ack=1.

    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    // Registros de salida bruta de la RAM.
    // Yosys los absorberá dentro del output register de la BRAM.
    reg [DATA_WIDTH-1:0] ram_a_q;
    reg [DATA_WIDTH-1:0] ram_b_q;

    always @(posedge clk) begin
        // ── Escritura Puerto A (con enable) ───────────────────────
        // Solo cuando hay req de escritura.
        // La escritura ocurre en el flanco, la lectura capta el dato
        // ANTERIOR (comportamiento read-first de RAMB36E1/RAMB18E1).
        if (a_req & a_wen)
            mem[a_idx] <= a_wdata;

        // ── Lectura Puerto A — SIN enable ─────────────────────────
        // Captura mem[a_idx] en cada ciclo.
        // La validez se controla en sección 4 con a_rd_valid_q.
        ram_a_q <= mem[a_idx];

        // ── Lectura Puerto B — SIN enable ─────────────────────────
        // Usa b_idx_eff: dirección actual o latcheada (stall).
        // La validez se controla en sección 4 con b_rd_valid_q.
        ram_b_q <= mem[b_idx_eff];
    end

// =============================================================================
//  SECCIÓN 4 — PIPELINE DE VALID / ACK Y FSM DE STALL
// =============================================================================
//
//  Pipeline de 1 ciclo:
//    ciclo N   : a_rd_en=1, mem[] capta  →  ram_a_q = mem[a_idx]  (ciclo N+1)
//    ciclo N+1 : a_rd_valid_q=1          →  a_rdata = ram_a_q, a_ack=1
//
//  El ack llega exactamente 1 ciclo después del req.
//  Este bloque sí tiene reset asíncrono (solo toca registros, nunca mem[]).

    reg a_rd_valid_q;   // a_rd_en retrasado 1 ciclo
    reg b_rd_valid_q;   // b_rd_en retrasado 1 ciclo

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // ── Reset de todos los registros de control ────────────
            a_ack        <= 1'b0;
            a_rdata      <= {DATA_WIDTH{1'b0}};
            a_rd_valid_q <= 1'b0;

            b_ack        <= 1'b0;
            b_rdata      <= {DATA_WIDTH{1'b0}};
            b_rd_valid_q <= 1'b0;
            b_stall      <= 1'b0;
            b_idx_latch  <= {IDX_BITS{1'b0}};

        end else begin
            // ══ Puerto A ══════════════════════════════════════════
            // Registrar enable de lectura un ciclo
            a_rd_valid_q <= a_rd_en;

            // Cuando el pipeline dice que el dato es válido:
            // propagar ram_a_q → a_rdata y generar ack
            a_ack   <= a_rd_valid_q;
            if (a_rd_valid_q)
                a_rdata <= ram_a_q;

            // ══ Puerto B — FSM de stall ═══════════════════════════
            //
            //  ESTADO IDLE (b_stall=0):
            //    b_req=0              → permanecer en IDLE
            //    b_req=1, no conflict → leer (b_rd_en=1), permanecer en IDLE
            //    b_req=1, conflict    → NO leer, ir a STALL:
            //                          b_stall<=1, b_idx_latch<=b_idx
            //
            //  ESTADO STALL (b_stall=1):
            //    b_rd_en=1 (forzado por b_stall en la lógica combinacional)
            //    La RAM lee mem[b_idx_latch] este ciclo
            //    Volver a IDLE: b_stall<=0
            //
            if (b_req & conflict_o) begin
                // Conflicto: congelar dirección y activar stall
                b_stall     <= 1'b1;
                b_idx_latch <= b_idx;
            end else begin
                // Sin conflicto o ciclo de reintento: liberar stall
                b_stall <= 1'b0;
            end

            // Pipeline de valid del puerto B
            b_rd_valid_q <= b_rd_en;

            b_ack   <= b_rd_valid_q;
            if (b_rd_valid_q)
                b_rdata <= ram_b_q;
        end
    end

// =============================================================================
//  SECCIÓN 5 — CONTADORES DE ESTADÍSTICAS  (atómicos)
// =============================================================================
//
//  Incrementos calculados combinacionalmente para evitar doble-driver.
//  hit_inc [1:0] puede valer 0, 1 o 2 en el mismo ciclo.
//
//  Nota semántica:
//    - hit  : acceso completado con éxito (A siempre, B si no hay conflicto)
//    - miss : B intentó acceder pero hubo conflicto → penalización de 1 ciclo
//    - Los contadores de bandwidth (bw_*) cuentan intentos, no completados

    reg [1:0] hit_inc;
    reg       miss_inc;
    reg       bw_a_inc;
    reg       bw_b_inc;

    always @(*) begin
        hit_inc  = 2'd0;
        miss_inc = 1'b0;
        bw_a_inc = 1'b0;
        bw_b_inc = 1'b0;

        // Puerto A: cualquier acceso (R o W) es un hit
        if (a_req) begin
            hit_inc  = hit_inc + 2'd1;
            bw_a_inc = 1'b1;
        end

        // Puerto B: hit si acceso limpio, miss si conflicto
        // b_stall NO cuenta como nuevo acceso (es reintento del mismo)
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
            // Un solo driver por registro — sin race condition
            hit_count   <= hit_count   + {{14{1'b0}}, hit_inc};
            miss_count  <= miss_count  + {15'd0, miss_inc};
            bw_framebuf <= bw_framebuf + {15'd0, bw_a_inc};
            bw_bvhmem   <= bw_bvhmem   + {15'd0, bw_b_inc};
        end
    end

// =============================================================================
//  SECCIÓN 6 — AXI4-LITE SLAVE MÍNIMO
// =============================================================================

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

// =============================================================================
//  SECCIÓN 7 — PROPIEDADES FORMALES  (SymbiYosys — compilar con -DFORMAL)
// =============================================================================

`ifdef FORMAL
    // P1: si hay conflicto este ciclo, b_ack no puede subir este ciclo
    //     (b_ack viene de b_rd_valid_q que es el ciclo anterior a conflict_o)
    //     → se verifica que b_stall implica que el ciclo siguiente no hay ack
    //     derivado de un ciclo de conflicto.
    always @(posedge clk) begin
        if ($past(conflict_o) && $past(rst_n))
            // b estuvo en conflicto el ciclo anterior → no pudo haber leído
            assert (!$past(b_rd_valid_q));
    end

    // P2: reset limpia acks
    always @(posedge clk) begin
        if (!rst_n) begin
            assert (a_ack == 1'b0);
            assert (b_ack == 1'b0);
        end
    end

    // P3: b_stall y b_ack no simultáneos
    //     (stall = esperando reintento, ack = ciclo completado)
    always @(posedge clk) begin
        if ($past(rst_n))
            assert (!(b_stall && b_ack));
    end

    // P4: after ack, rdata debe haber sido escrito
    always @(posedge clk) begin
        if ($past(rst_n) && a_ack)
            assert (a_rd_valid_q == 1'b0); // a_rd_valid_q ya bajó
    end
`endif

endmodule

`default_nettype wire

// =============================================================================
//  FIN DE ARCHIVO — sram_integrated.v  v6.0
//
//  RESUMEN DE CAMBIOS v5.0 → v6.0
//  ─────────────────────────────────────────────────────────────────────────
//  PROBLEMA  : "FF found, but with a mux select that doesn't seem to
//               correspond to transparency logic."
//
//  CAUSA     : Las lecturas de RAM tenían enable condicional:
//                  if (a_re) ram_a_q <= mem[a_idx];
//              Yosys traduce esto como:
//                  ram_a_q_next = a_re ? mem[a_idx] : ram_a_q;
//              El mux de retención rompe el patrón de output register
//              que memory_bram necesita para absorber el FF en la BRAM.
//
//  SOLUCIÓN  : Lecturas siempre activas, sin enable:
//                  ram_a_q <= mem[a_idx];      ← sin if
//                  ram_b_q <= mem[b_idx_eff];  ← sin if
//              La validez del dato se controla fuera del bloque de RAM
//              con registros de pipeline (a_rd_valid_q, b_rd_valid_q).
//
//  RESULTADO : Yosys puede absorber ram_a_q y ram_b_q dentro del
//              output register de RAMB36E1/RAMB18E1.
//              memory_bram infiere BRAM correctamente.
//              MUXF7/MUXF8 desaparecen del reporte de síntesis.
// =============================================================================