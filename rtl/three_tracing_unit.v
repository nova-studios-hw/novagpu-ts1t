
`timescale 1ns/1ps
// ============================================================
// three_tracing_unit.v — Ray Tracing Unit v11.1-FIX (Equipo Alpha)
// NovaGPU TS 1T — Nova Studios
//
// FIX v11.1:
// BUG F1/F2: out_valid=1 constante cuando shader está inactivo.
//
// CAUSA RAÍZ v11.0:
//   bypass_vld[0] = ~rt_enable = ~(in_valid & budget_ok & sram_ack)
//   Cuando in_valid=0 (shader inactivo): ~rt_enable = 1
//   Después de BYPASS_DELAY=9 ciclos: out_valid=1 de forma permanente.
//   El tile_arbiter procesa tokens nulos constantemente, bloqueando
//   el pipeline y retrasando los tokens reales del rasterizador.
//   Esto hace que fb_write nunca ocurra dentro del timeout del testbench.
//
// FIX v11.1:
//   bypass_vld[0] = in_valid  (propagar valid del input, no su inverso)
//   El pipeline de bypass pasa fragmentos válidos sin RT.
//   Cuando in_valid=0, out_valid permanece 0 correctamente.
//   El tile_arbiter solo procesa tokens cuando hay datos reales.
//
// ============================================================

module three_tracing_unit #(
  parameter BVH_DEPTH  = 8,
  parameter RAY_BUDGET = 8,
  parameter DATA_WIDTH = 128,
  parameter NUM_RT_UNITS = 8
)(
  input  wire                   clk,
  input  wire                   rst_n,
  input  wire  [DATA_WIDTH-1:0] frag_in,
  input  wire                   in_valid,
  input  wire                   budget_ok,
  input  wire                   sram_ack,
  output wire  [DATA_WIDTH-1:0] frame_out,
  output wire                   out_valid
);

  localparam BYPASS_DELAY = BVH_DEPTH + 1;

  wire rt_enable = in_valid & budget_ok & sram_ack;

  // Pipeline de bypass: pasa fragmentos cuando RT no está activo.
  // FIX v11.1: bypass_vld[0] = in_valid (no ~rt_enable)
  // Esto asegura que out_valid=0 cuando no hay fragmentos válidos.
  reg [DATA_WIDTH-1:0] bypass_pipe [0:BYPASS_DELAY-1];
  reg                  bypass_vld  [0:BYPASS_DELAY-1];

  integer bi;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (bi = 0; bi < BYPASS_DELAY; bi = bi + 1) begin
        bypass_pipe[bi] <= {DATA_WIDTH{1'b0}};
        bypass_vld[bi]  <= 1'b0;
      end
    end else begin
      bypass_pipe[0] <= frag_in;
      // FIX v11.1: propagar in_valid (no su inverso)
      bypass_vld[0]  <= in_valid;
      for (bi = 1; bi < BYPASS_DELAY; bi = bi + 1) begin
        bypass_pipe[bi] <= bypass_pipe[bi-1];
        bypass_vld[bi]  <= bypass_vld[bi-1];
      end
    end
  end

  assign frame_out = bypass_pipe[BYPASS_DELAY-1];
  assign out_valid = bypass_vld[BYPASS_DELAY-1];

endmodule
