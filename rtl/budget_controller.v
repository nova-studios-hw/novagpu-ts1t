`timescale 1ns/1ps
// =============================================================================
// budget_controller.v  —  Budget Controller  v3.0
// NovaGPU TS 2T  —  Nova Studios / Maximal Technology
//
// Controla porcentaje de ciclos dedicados a Ray Tracing.
// Ventana de medición: WINDOW ciclos.
// budget_ok = 1 mientras rt_cnt < THRESHOLD en ventana actual.
// =============================================================================

module budget_controller #(
    parameter CLK_MHZ    = 250,
    parameter RT_PERCENT = 25,
    parameter WINDOW     = 1000
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       frame_start,
    input  wire       rt_active,
    output reg        budget_ok,
    output reg  [7:0] rt_load
);

    localparam THRESHOLD = (WINDOW * RT_PERCENT) / 100;

    reg [9:0] window_cnt;
    reg [9:0] rt_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            budget_ok  <= 1'b1;
            rt_load    <= 8'd0;
            window_cnt <= 10'd0;
            rt_cnt     <= 10'd0;
        end else begin
            // Reseteo en frame_start tiene prioridad
            if (frame_start) begin
                rt_cnt     <= 10'd0;
                window_cnt <= 10'd0;
                budget_ok  <= 1'b1;
            end else begin
                window_cnt <= window_cnt + 10'd1;

                if (rt_active)
                    rt_cnt <= rt_cnt + 10'd1;

                if (window_cnt >= WINDOW[9:0] - 10'd1) begin
                    rt_load    <= rt_cnt[7:0];
                    budget_ok  <= (rt_cnt < THRESHOLD[9:0]);
                    window_cnt <= 10'd0;
                    rt_cnt     <= 10'd0;
                end else begin
                    // En ciclos intermedios: evaluar contra umbral parcial
                    budget_ok <= (rt_cnt < THRESHOLD[9:0]);
                end
            end
        end
    end

endmodule