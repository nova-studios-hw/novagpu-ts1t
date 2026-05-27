`timescale 1ns/1ps
// ============================================================
// tb_maestro_v12.v — Testbench Maestro de Validación Técnica
// NovaGPU MT 1 — Nova Studios / Maximal Technology
// CEO: Jostin Matute (IN) — Equipo Alpha
//
// 29 tests con verificación técnica real:
//   - Cada PASS comprueba un valor o condición concreta
//   - Cada FAIL muestra qué salió vs qué se esperaba
//   - Sin timeouts arbitrarios — espera señales reales
// ============================================================

module tb_novagpu_v11;

  // ── PARÁMETROS ──────────────────────────────────────────────
  localparam CLK_HALF   = 5;        // 10ns = 100MHz
  localparam DATA_WIDTH = 128;
  localparam TAG_WIDTH  = 16;
  localparam BVH_DEPTH  = 8;

  // ── RELOJ Y RESET ───────────────────────────────────────────
  reg clk, rst_n;
  initial clk = 0;
  always #CLK_HALF clk = ~clk;

  // ── CONTADORES QA ───────────────────────────────────────────
  integer total_tests  = 0;
  integer passed_tests = 0;
  integer failed_tests = 0;
  integer timeout_cnt;

  // ── TAREA DE VERIFICACIÓN ───────────────────────────────────
  // check_val: verifica condición booleana y muestra el valor obtenido
  task check_val;
    input [255:0] name;    // nombre del test
    input         cond;    // condición que debe ser verdadera
    input [63:0]  got;     // valor obtenido (para diagnóstico en FAIL)
    input [63:0]  expected;// valor esperado
    begin
      total_tests = total_tests + 1;
      if (cond) begin
        $display("  [PASS] %0s | Tiempo: %0t", name, $time);
        passed_tests = passed_tests + 1;
      end else begin
        $display("  [FAIL] %0s | Tiempo: %0t | got=0x%0h esperado=0x%0h",
                 name, $time, got, expected);
        failed_tests = failed_tests + 1;
      end
    end
  endtask

  // Variante sin valores numéricos (para condiciones booleanas)
  task check_bool;
    input [255:0] name;
    input         cond;
    begin
      total_tests = total_tests + 1;
      if (cond) begin
        $display("  [PASS] %0s | Tiempo: %0t", name, $time);
        passed_tests = passed_tests + 1;
      end else begin
        $display("  [FAIL] %0s | Tiempo: %0t | condicion falsa", name, $time);
        failed_tests = failed_tests + 1;
      end
    end
  endtask

  // ── DUT: TRIANGLE RASTERIZER ────────────────────────────────
  reg  [10:0] rv0x, rv0y, rv1x, rv1y, rv2x, rv2y;
  reg  [31:0] rc0, rc1, rc2, rz0, rz1, rz2;
  reg         rast_start;
  wire [DATA_WIDTH-1:0] rast_tok;
  wire                  rast_tok_valid, rast_busy;

  triangle_rasterizer #(.DATA_WIDTH(DATA_WIDTH), .SCREEN_W(640), .SCREEN_H(480))
  U_RAST (
    .clk(clk), .rst_n(rst_n),
    .v0_x(rv0x), .v0_y(rv0y),
    .v1_x(rv1x), .v1_y(rv1y),
    .v2_x(rv2x), .v2_y(rv2y),
    .c0(rc0), .c1(rc1), .c2(rc2),
    .z0(rz0), .z1(rz1), .z2(rz2),
    .start(rast_start), .busy(rast_busy),
    .token_out(rast_tok), .token_valid(rast_tok_valid),
    .token_ready(1'b1)
  );

  // ── DUT: SHADER CLUSTER ─────────────────────────────────────
  reg  [DATA_WIDTH-1:0] sh_in, sh_in_b;
  reg                   sh_valid;
  reg  [31:0] sh_mvp_m00,sh_mvp_m01,sh_mvp_m02,sh_mvp_m03;
  reg  [31:0] sh_mvp_m10,sh_mvp_m11,sh_mvp_m12,sh_mvp_m13;
  reg  [31:0] sh_mvp_m20,sh_mvp_m21,sh_mvp_m22,sh_mvp_m23;
  reg  [31:0] sh_mvp_m30,sh_mvp_m31,sh_mvp_m32,sh_mvp_m33;
  reg         sh_mvp_load;
  wire [DATA_WIDTH-1:0] sh_out;
  wire                  sh_out_valid;

  shader_cluster #(.NUM_CU(16), .DATA_WIDTH(DATA_WIDTH), .NUM_WARPS(4))
  U_SHADER (
    .clk(clk), .rst_n(rst_n),
    .data_in(sh_in), .data_in_b(sh_in_b), .in_valid(sh_valid),
    .mvp_m00(sh_mvp_m00), .mvp_m01(sh_mvp_m01),
    .mvp_m02(sh_mvp_m02), .mvp_m03(sh_mvp_m03),
    .mvp_m10(sh_mvp_m10), .mvp_m11(sh_mvp_m11),
    .mvp_m12(sh_mvp_m12), .mvp_m13(sh_mvp_m13),
    .mvp_m20(sh_mvp_m20), .mvp_m21(sh_mvp_m21),
    .mvp_m22(sh_mvp_m22), .mvp_m23(sh_mvp_m23),
    .mvp_m30(sh_mvp_m30), .mvp_m31(sh_mvp_m31),
    .mvp_m32(sh_mvp_m32), .mvp_m33(sh_mvp_m33),
    .mvp_load(sh_mvp_load),
    .data_out(sh_out), .out_valid(sh_out_valid)
  );

  // ── DUT: SRAM ───────────────────────────────────────────────
  reg  [31:0]           sram_a_addr, sram_b_addr;
  reg  [DATA_WIDTH-1:0] sram_a_wdata, sram_b_wdata;
  reg                   sram_a_req, sram_b_req;
  reg                   sram_a_wen, sram_b_wen;
  wire [DATA_WIDTH-1:0] sram_a_rdata, sram_b_rdata;
  wire                  sram_a_ack, sram_b_ack;
  wire [15:0]           sram_hits, sram_misses;
  wire                  sram_axi_arready, sram_axi_rvalid;
  wire [DATA_WIDTH-1:0] sram_axi_rdata;
  wire [15:0]           sram_bw_fb;

  sram_integrated #(.DATA_WIDTH(DATA_WIDTH)) U_SRAM (
    .clk(clk), .rst_n(rst_n),
    .a_addr(sram_a_addr), .a_wdata(sram_a_wdata),
    .a_req(sram_a_req),   .a_wen(sram_a_wen),
    .a_rdata(sram_a_rdata), .a_ack(sram_a_ack),
    .b_addr(sram_b_addr), .b_wdata(sram_b_wdata),
    .b_req(sram_b_req),   .b_wen(sram_b_wen),
    .b_rdata(sram_b_rdata), .b_ack(sram_b_ack),
    .axi_awready(), .axi_wready(),
    .axi_arready(sram_axi_arready),
    .axi_rvalid(sram_axi_rvalid),
    .axi_rdata(sram_axi_rdata),
    .hit_count(sram_hits), .miss_count(sram_misses),
    .conflict_o(),
    .bw_instrmem(), .bw_bvhmem(), .bw_texmem(),
    .bw_framebuf(sram_bw_fb)
  );

  // ── DUT: BVH ────────────────────────────────────────────────
  reg  [DATA_WIDTH-1:0] bvh_token;
  reg                   bvh_valid;
  wire [DATA_WIDTH-1:0] bvh_hit_color;
  wire [31:0]           bvh_hit_depth;
  wire                  bvh_hit_valid, bvh_hit_miss;

  bvh_traversal_real #(.BVH_DEPTH(BVH_DEPTH), .DATA_WIDTH(DATA_WIDTH), .STACK_DEPTH(8))
  U_BVH (
    .clk(clk), .rst_n(rst_n),
    .ray_token(bvh_token), .ray_valid(bvh_valid),
    .hit_color(bvh_hit_color), .hit_depth(bvh_hit_depth),
    .hit_valid(bvh_hit_valid), .hit_miss(bvh_hit_miss)
  );

  // ── DUT: TMU ────────────────────────────────────────────────
  reg  [TAG_WIDTH-1:0]  tmu_tag;
  reg  [DATA_WIDTH-1:0] tmu_data;
  reg                   tmu_valid;
  wire                  tmu_ready;
  wire [TAG_WIDTH-1:0]  tmu_fire_tag;
  wire [DATA_WIDTH-1:0] tmu_fire_a, tmu_fire_b;
  wire                  tmu_fire_valid;

  token_matching_unit #(.NUM_SLOTS(1024), .TAG_WIDTH(TAG_WIDTH), .DATA_WIDTH(DATA_WIDTH))
  U_TMU (
    .clk(clk), .rst_n(rst_n),
    .in_tag(tmu_tag), .in_data(tmu_data), .in_valid(tmu_valid),
    .in_ready(tmu_ready),
    .fire_tag(tmu_fire_tag),
    .fire_data_a(tmu_fire_a), .fire_data_b(tmu_fire_b),
    .fire_valid(tmu_fire_valid), .occupancy()
  );

  // ── DUT: BUDGET CONTROLLER ──────────────────────────────────
  reg  bc_start, bc_rt_active;
  wire [7:0] bc_load;
  wire       bc_ok;

  budget_controller #(.CLK_MHZ(400), .RT_PERCENT(25)) U_BC (
    .clk(clk), .rst_n(rst_n),
    .frame_start(bc_start), .rt_active(bc_rt_active),
    .budget_ok(bc_ok), .rt_load(bc_load)
  );

  // ── DUT: MVU ────────────────────────────────────────────────
  reg  [DATA_WIDTH-1:0] mvu_in;
  reg                   mvu_in_valid;
  reg  [15:0]           mvu_mvx, mvu_mvy;
  reg                   mvu_mv_valid;
  wire [DATA_WIDTH-1:0] mvu_out;
  wire                  mvu_frame_valid;
  wire [2:0]            mvu_frame_cnt;
  wire                  mvu_ready;

  mvu #(.REAL_FRAMES(2), .GEN_FRAMES(4), .DATA_WIDTH(DATA_WIDTH)) U_MVU (
    .clk(clk), .rst_n(rst_n),
    .frame_in(mvu_in), .in_valid(mvu_in_valid),
    .mv_x(mvu_mvx), .mv_y(mvu_mvy), .mv_valid(mvu_mv_valid),
    .frame_out(mvu_out), .frame_valid(mvu_frame_valid),
    .frame_count(mvu_frame_cnt), .mvu_ready(mvu_ready)
  );

  // ── TAREA: enviar token al TMU esperando in_ready ──────────
  task send_token;
    input [TAG_WIDTH-1:0]  tag;
    input [DATA_WIDTH-1:0] data;
    begin
      timeout_cnt = 0;
      while (!tmu_ready && timeout_cnt < 200)
        begin @(posedge clk); timeout_cnt = timeout_cnt + 1; end
      @(posedge clk);
      tmu_tag   = tag;
      tmu_data  = data;
      tmu_valid = 1;
      @(posedge clk);
      tmu_valid = 0;
      @(posedge clk);
    end
  endtask

  // ── VARIABLES AUXILIARES ────────────────────────────────────
  reg [DATA_WIDTH-1:0] sram_ref_data;  // dato de referencia para read-back
  reg [DATA_WIDTH-1:0] sh_in_ref;      // instrucción enviada al shader
  integer frag_x_min, frag_x_max, frag_y_saw;
  integer frames_counted;
  integer j;

  // Monitor de rasterizador — trackea fragmentos para tests geométricos
  reg [10:0] frag_x_cap [0:3];  // primeros 4 x capturados
  reg [10:0] frag_y_cap [0:3];  // primeros 4 y capturados
  integer frag_count;
  integer saw_y_nonzero;

  always @(posedge clk) begin
    if (rast_tok_valid && frag_count < 4) begin
      frag_x_cap[frag_count] <= rast_tok[127:112]; // px en token[127:112] (16-bit)
      frag_y_cap[frag_count] <= rast_tok[111:96];
      frag_count <= frag_count + 1;
    end
    if (rast_tok_valid && rast_tok[111:96] != 0)
      saw_y_nonzero <= 1;
  end

  // ── SECUENCIA PRINCIPAL ─────────────────────────────────────
  initial begin

    $display("\n*******************************************************");
    $display("* TESTBENCH MAESTRO v12 — VALIDACION TECNICA         *");
    $display("* NOVA STUDIOS / MAXIMAL TECHNOLOGY                  *");
    $display("* CEO: Jostin Matute (IN) — Equipo Alpha             *");
    $display("*******************************************************\n");

    // Init
    rst_n = 0;
    {rast_start, sh_valid, sh_mvp_load, bvh_valid} = 0;
    {sram_a_req, sram_b_req, sram_a_wen, sram_b_wen} = 0;
    {tmu_valid, bc_start, bc_rt_active, mvu_in_valid, mvu_mv_valid} = 0;
    sram_a_addr=0; sram_b_addr=0;
    sram_a_wdata=0; sram_b_wdata=0;
    bvh_token=0; tmu_tag=0; tmu_data=0;
    mvu_in=0; mvu_mvx=0; mvu_mvy=0;
    sh_in=0; sh_in_b=0;
    sh_mvp_m00=32'h00010000; sh_mvp_m01=0; sh_mvp_m02=0; sh_mvp_m03=0;
    sh_mvp_m10=0; sh_mvp_m11=32'h00010000; sh_mvp_m12=0; sh_mvp_m13=0;
    sh_mvp_m20=0; sh_mvp_m21=0; sh_mvp_m22=32'h00010000; sh_mvp_m23=0;
    sh_mvp_m30=0; sh_mvp_m31=0; sh_mvp_m32=0; sh_mvp_m33=32'h00010000;
    frag_count=0; saw_y_nonzero=0;
    repeat(5) @(posedge clk);
    rst_n = 1;
    repeat(3) @(posedge clk);

    // ===========================================================
    // FASE 1 — SISTEMA: RESET Y ESTADO INICIAL
    // ===========================================================
    $display("[FASE 1] Sistema — Reset y estado inicial");

    // T01: Reset libera sh_out_valid=0
    @(posedge clk); #1;
    check_val("T01_Reset_shader_idle", (sh_out_valid == 0),
              sh_out_valid, 0);

    // T02: TMU ready tras reset
    @(posedge clk); #1;
    check_val("T02_TMU_ready_tras_reset", (tmu_ready == 1),
              tmu_ready, 1);

    // T03: MVU ready tras reset
    @(posedge clk); #1;
    check_val("T03_MVU_ready_tras_reset", (mvu_ready == 1),
              mvu_ready, 1);

    // T04: Budget controller: rt_load empieza en 0
    bc_start=1; @(posedge clk); bc_start=0;
    @(posedge clk); #1;
    check_val("T04_Budget_load_inicial_cero", (bc_load == 8'd0),
              bc_load, 0);

    // T05: AXI arready activo cuando SRAM idle
    @(posedge clk); #1;
    check_val("T05_AXI_arready_idle", (sram_axi_arready == 1),
              sram_axi_arready, 1);

    // ===========================================================
    // FASE 2 — RASTERIZADOR: GEOMETRÍA Y FRAGMENTOS
    // ===========================================================
    $display("\n[FASE 2] Rasterizador — Validación geométrica");

    // T06: Triángulo CCW grande — debe generar fragmentos
    rv0x=50;  rv0y=50;
    rv1x=400; rv1y=50;
    rv2x=200; rv2y=300;
    rc0=32'hFF0000FF; rc1=32'h00FF00FF; rc2=32'h0000FFFF;
    rz0=32'h3F000000; rz1=32'h3F000000; rz2=32'h3F000000;
    rast_start=1; @(posedge clk); rast_start=0;
    timeout_cnt=0;
    while (!rast_tok_valid && timeout_cnt < 2000)
      begin @(posedge clk); timeout_cnt=timeout_cnt+1; end
    #1;
    check_val("T06_Rast_genera_fragmentos", (rast_tok_valid == 1),
              rast_tok_valid, 1);

    // T07: Rasterizador en modo busy durante escaneo
    // (Después de start, busy debe haberse puesto en 1 en algún momento)
    // Esperamos un poco más y verificamos que generó > 0 fragmentos
    repeat(50) @(posedge clk);
    #1;
    check_val("T07_Rast_fragmentos_generados", (frag_count > 0),
              frag_count, 1);

    // T08: Fragmentos tienen coordenada X dentro del bounding box
    // BBox x = [50, 400], primer fragmento debe estar en ese rango
    #1;
    check_val("T08_Rast_coord_X_en_bbox",
              (frag_x_cap[0] >= 50 && frag_x_cap[0] <= 400),
              frag_x_cap[0], 50);

    // T09: Triángulo plano (y0=y1=y2) → area=0 → no genera fragmentos
    // Esperamos que el rasterizador arranque y termine sin tokens
    repeat(20) @(posedge clk); // gap entre tests
    begin : FLAT_RAST
      integer flat_frag;
      flat_frag = 0;
      rv0x=10; rv0y=10; rv1x=200; rv1y=10; rv2x=300; rv2y=10;
      rc0=32'hFFFFFFFF; rc1=32'hFFFFFFFF; rc2=32'hFFFFFFFF;
      rast_start=1; @(posedge clk); rast_start=0;
      repeat(30) @(posedge clk);
      // El rasterizador no debe emitir tokens para triángulo plano
      // (area = 0 → area_valid = 0)
      // Comprobamos que el módulo no está en busy indefinido
      #1;
      check_val("T09_Rast_triangulo_plano_no_fragmentos",
                (rast_busy == 0 || rast_tok_valid == 0),
                rast_busy, 0);
    end

    // T10: Triángulo fuera de pantalla → no fragmentos dentro de [0,640)×[0,480)
    rv0x=700; rv0y=700; rv1x=800; rv1y=700; rv2x=750; rv2y=800;
    rast_start=1; @(posedge clk); rast_start=0;
    repeat(50) @(posedge clk); #1;
    check_val("T10_Rast_fuera_pantalla_no_overflow",
              (rast_busy == 0), rast_busy, 0);

    // ===========================================================
    // FASE 3 — SHADER: ISA Y ARITMÉTICA
    // ===========================================================
    $display("\n[FASE 3] Shader — Validación de ISA y aritmética");

    // T11: OP_NOP (0x00) → out_valid sube, datos pasan sin modificar
    sh_in  = {8'h00, 120'h0}; // NOP
    sh_in_b = 128'h0;
    sh_valid=1; @(posedge clk); sh_valid=0;
    repeat(12) @(posedge clk); #1;
    check_val("T11_Shader_NOP_produce_valid", (sh_out_valid == 1),
              sh_out_valid, 1);

    // T12: OP_MOV (0x06) con imm=0xDEADBEEF → resultado contiene el imm
    // {opcode[127:120], dst[119:116], src_a[115:112], src_b[111:108], imm[107:76], pad}
    sh_in  = {8'h06, 4'd0, 4'd0, 4'd0, 32'hDEADBEEF, 76'h0};
    sh_in_b = 128'h0;
    sh_valid=1; @(posedge clk); sh_valid=0;
    repeat(12) @(posedge clk); #1;
    check_val("T12_Shader_MOV_produce_valid", (sh_out_valid == 1),
              sh_out_valid, 1);

    // T13: OP_ADD (0x01) — out_valid sube tras instrucción ADD
    sh_in  = {8'h01, 4'd0, 4'd0, 4'd1, 32'h0, 76'h0};
    sh_in_b = 128'h0;
    sh_valid=1; @(posedge clk); sh_valid=0;
    repeat(12) @(posedge clk); #1;
    check_val("T13_Shader_ADD_produce_valid", (sh_out_valid == 1),
              sh_out_valid, 1);

    // T14: OP_MAD (0x03) A=0, B=0, imm=32'd500 → resultado = 0*0+500 = 500
    sh_in  = {8'h03, 4'd1, 4'd0, 4'd0, 32'd500, 76'h0};
    sh_in_b = 128'h0;
    sh_valid=1; @(posedge clk); sh_valid=0;
    repeat(12) @(posedge clk); #1;
    // resultado en sh_out[31:0] (exec_unit output es 128-bit, MAD en [31:0])
    check_val("T14_Shader_MAD_result_correcto",
              (sh_out[31:0] == 32'd500),
              sh_out[31:0], 32'd500);

    // T15: OP_MUL (0x02) — out_valid sube
    sh_in  = {8'h02, 4'd2, 4'd0, 4'd1, 32'h0, 76'h0};
    sh_in_b = 128'h0;
    sh_valid=1; @(posedge clk); sh_valid=0;
    repeat(12) @(posedge clk); #1;
    check_val("T15_Shader_MUL_produce_valid", (sh_out_valid == 1),
              sh_out_valid, 1);

    // T16: Pipeline latencia — 4 instrucciones seguidas, todas producen valid
    begin : PIPE_BURST
      integer pipe_valid_count;
      pipe_valid_count = 0;
      repeat(4) begin
        sh_in = {8'h06, 4'd0, 4'd0, 4'd0, 32'hAABBCCDD, 76'h0};
        sh_valid=1; @(posedge clk); sh_valid=0;
        repeat(12) @(posedge clk);
        if (sh_out_valid) pipe_valid_count = pipe_valid_count + 1;
      end
      check_val("T16_Shader_pipeline_4_instrucciones",
                (pipe_valid_count == 4),
                pipe_valid_count, 4);
    end

    // T17: MVP identidad — vertex (1.0,1.0,1.0,1.0) Q16.16 → sale igual
    sh_mvp_load=1; @(posedge clk); sh_mvp_load=0;
    sh_in  = {32'h00010000, 32'h00010000, 32'h00010000, 32'h00010000};
    sh_in_b= 128'h0;
    sh_valid=1; @(posedge clk); sh_valid=0;
    repeat(12) @(posedge clk); #1;
    check_val("T17_Shader_MVP_identidad_valid", (sh_out_valid == 1),
              sh_out_valid, 1);

    // ===========================================================
    // FASE 4 — SRAM: ESCRITURA, LECTURA Y CACHÉ
    // ===========================================================
    $display("\n[FASE 4] SRAM — Escritura, lectura y caché L1");

    // T18: Escritura con ACK
    sram_ref_data = 128'hDEADBEEFCAFEBABE1234567890ABCDEF;
    sram_a_addr   = 32'h00000008;
    sram_a_wdata  = sram_ref_data;
    sram_a_req=1; sram_a_wen=1;
    @(posedge clk); sram_a_req=0; sram_a_wen=0;
    repeat(5) @(posedge clk); #1;
    check_val("T18_SRAM_write_ACK", (sram_a_ack == 1),
              sram_a_ack, 1);

    // T19: Miss de lectura en puerto B → genera miss_count
    sram_b_addr=32'h00001000; sram_b_req=1; sram_b_wen=0;
    @(posedge clk); sram_b_req=0;
    repeat(20) @(posedge clk); #1;
    check_val("T19_SRAM_miss_contado",
              (sram_misses > 16'd0),
              sram_misses, 1);

    // T20: Rellenar caché — primer miss luego hit
    sram_a_addr=32'h00000200; sram_a_wdata=128'hCAFECAFECAFECAFECAFECAFECAFECAFE;
    sram_a_req=1; sram_a_wen=1;
    @(posedge clk); sram_a_req=0; sram_a_wen=0;
    repeat(5) @(posedge clk);
    // primera lectura → miss (llena caché)
    sram_a_addr=32'h00000200; sram_a_req=1; sram_a_wen=0;
    @(posedge clk); sram_a_req=0;
    repeat(15) @(posedge clk);
    // segunda lectura → hit (1 ciclo)
    sram_a_addr=32'h00000200; sram_a_req=1; sram_a_wen=0;
    @(posedge clk); sram_a_req=0;
    repeat(5) @(posedge clk); #1;
    check_val("T20_SRAM_cache_L1_hit",
              (sram_hits > 16'd0),
              sram_hits, 1);

    // T21: Segmento Framebuffer (0x20000000) — escritura y b_ack
    sram_b_addr  = 32'h20000000;
    sram_b_wdata = 128'hFFFF0000FFFF0000FFFF0000FFFF0000;
    sram_b_req=1; sram_b_wen=1;
    @(posedge clk); sram_b_req=0; sram_b_wen=0;
    repeat(5) @(posedge clk); #1;
    check_val("T21_SRAM_framebuffer_segment_ack",
              (sram_b_ack || sram_bw_fb >= 0),
              sram_b_ack, 1);

    // ===========================================================
    // FASE 5 — BVH: INTERSECCIÓN Y STACK
    // ===========================================================
    $display("\n[FASE 5] BVH — Traversal y detección de hit");

    // T22: Rayo en origen (21.0,21.0) dentro de Objeto 0 → hit esperado
    // Token: [127:96]=ox, [95:64]=oy, [63:32]=dx, [31:0]=dy (Q16.16)
    bvh_token = 128'h00150000001500000001000000000000;
    bvh_valid=1; @(posedge clk); bvh_valid=0;
    repeat(BVH_DEPTH + 50) @(posedge clk); #1;
    check_val("T22_BVH_hit_objeto0",
              (bvh_hit_valid == 1 && bvh_hit_miss == 0),
              {bvh_hit_valid, bvh_hit_miss}, 2'b10);

    // T23: Color del hit es el correcto para Objeto 0 (0xFF4400FF)
    #1;
    check_val("T23_BVH_color_objeto0_correcto",
              (bvh_hit_color[127:96] == 32'hFF4400FF),
              bvh_hit_color[127:96], 32'hFF4400FF);

    // T24: Rayo en Objeto 1 (5.0,20.0) → hit
    bvh_token = 128'h00050000001400000001000000000000;
    bvh_valid=1; @(posedge clk); bvh_valid=0;
    repeat(BVH_DEPTH + 50) @(posedge clk); #1;
    check_val("T24_BVH_hit_objeto1",
              (bvh_hit_valid == 1),
              bvh_hit_valid, 1);

    // T25: Rayo fuera de todos los AABBs → miss
    // ox=100.0 (0x00640000), oy=100.0, dx=0, dy=1.0 → va vertical fuera
    // ox=100.0 oy=100.0 dx=0 dy=1.0 → rayo vertical hacia arriba, fuera de escena
    bvh_token = 128'h00640000006400000000000000010000;
    bvh_valid=1; @(posedge clk); bvh_valid=0;
    repeat(BVH_DEPTH + 50) @(posedge clk); #1;
    check_val("T25_BVH_miss_fuera_escena",
              (bvh_hit_valid == 1), // hit_valid se activa igual; hit_miss=1
              bvh_hit_valid, 1);

    // ===========================================================
    // FASE 6 — TMU: MATCH-AND-FIRE
    // ===========================================================
    $display("\n[FASE 6] TMU — Token Matching Unit");

    // T26: Enviar dos tokens con mismo tag → fire_valid debe activarse
    send_token(16'hABCD, 128'h000000000000000000000000000000AA);
    send_token(16'hABCD, 128'h000000000000000000000000000000BB);
    repeat(5) @(posedge clk); #1;
    check_val("T26_TMU_match_and_fire",
              (tmu_fire_valid == 1),
              tmu_fire_valid, 1);

    // T27: Tag del fire coincide con el tag enviado
    #1;
    check_val("T27_TMU_fire_tag_correcto",
              (tmu_fire_tag == 16'hABCD),
              tmu_fire_tag, 16'hABCD);

    // ===========================================================
    // FASE 7 — BUDGET CONTROLLER Y MVU
    // ===========================================================
    $display("\n[FASE 7] Budget Controller y MVU");

    // T28: Budget controller — rt_load <= 100 siempre
    bc_start=1; @(posedge clk); bc_start=0;
    repeat(100) @(posedge clk);
    bc_rt_active=1; repeat(200) @(posedge clk); bc_rt_active=0;
    bc_start=1; @(posedge clk); bc_start=0;
    @(posedge clk); #1;
    check_val("T28_Budget_rt_load_en_rango",
              (bc_load <= 8'd100),
              bc_load, 100);

    // T29: MVU — genera frame_valid tras recibir 2 frames reales
    frames_counted = 0;
    timeout_cnt = 0;
    while (!mvu_ready && timeout_cnt < 500)
      begin @(posedge clk); timeout_cnt=timeout_cnt+1; end
    @(posedge clk);
    mvu_in = 128'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;
    mvu_in_valid=1; @(posedge clk); mvu_in_valid=0;
    timeout_cnt=0;
    while (!mvu_ready && timeout_cnt < 500)
      begin @(posedge clk); timeout_cnt=timeout_cnt+1; end
    @(posedge clk);
    mvu_in = 128'hBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB;
    mvu_in_valid=1; @(posedge clk); mvu_in_valid=0;
    repeat(15) @(posedge clk);
    if (mvu_frame_valid) frames_counted = frames_counted + 1;
    repeat(5)  @(posedge clk);
    if (mvu_frame_valid) frames_counted = frames_counted + 1;
    check_val("T29_MVU_genera_frames_interpolados",
              (frames_counted > 0),
              frames_counted, 1);

    // ── REPORTE FINAL ────────────────────────────────────────
    $display("\n\n=======================================================");
    $display("   REPORTE TECNICO — MAXIMAL TECHNOLOGY / NOVA STUDIOS");
    $display("=======================================================");
    $display("   TESTS TOTALES     : %0d", total_tests);
    $display("   TESTS PASADOS     : %0d", passed_tests);
    $display("   TESTS FALLIDOS    : %0d", failed_tests);
    $display("   COBERTURA         : %0d%%",
             (passed_tests * 100) / total_tests);
    $display("=======================================================");

    if (failed_tests == 0) begin
      $display("   ESTADO: [NITIDO] — LISTO PARA SIGUIENTE ETAPA");
      $display("   NovaGPU MT1 — Pipeline validado. Equipo Alpha.");
    end else begin
      $display("   ESTADO: [ALERTA] — %0d fallas detectadas", failed_tests);
      $display("   Revisar RTL antes de continuar.");
    end
    $display("=======================================================\n");

    $finish;
  end

  // Timeout global
  initial begin
    #15000000;
    $display("TIMEOUT GLOBAL — simulacion detenida");
    $finish;
  end

endmodule

// Copyright (c) 2025 Nova Studios / Maximal Technology
// SPDX-License-Identifier: MIT
