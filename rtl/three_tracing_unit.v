`timescale 1ns/1ps
// ============================================================
// three_tracing_unit.v — Ray Tracing Unit v11.0 (Equipo Alpha)
// NovaGPU TS 1T — Nova Studios
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

  // ── Versión simplificada (stub) para compilación ──
  // En una implementación real, aquí irían los 8 BVH units
  
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
      bypass_vld[0]  <= ~rt_enable;  // Bypass cuando no hay RT activo
      for (bi = 1; bi < BYPASS_DELAY; bi = bi + 1) begin
        bypass_pipe[bi] <= bypass_pipe[bi-1];
        bypass_vld[bi]  <= bypass_vld[bi-1];
      end
    end
  end

  assign frame_out = bypass_pipe[BYPASS_DELAY-1];
  assign out_valid = bypass_vld[BYPASS_DELAY-1];

endmodule
