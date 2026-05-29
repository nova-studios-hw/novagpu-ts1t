`timescale 1ns/1ps
// =============================================================================
// rotation_matrix.v  —  Rotation Matrix  v3.0
// NovaGPU TS 2T  —  Nova Studios / Maximal Technology
//
// Genera vértices de un triángulo rotando alrededor del centro de pantalla.
// Usa tabla LUT de sin/cos de 64 entradas (Q8.8).
// =============================================================================

module rotation_matrix #(
    parameter SCREEN_W = 640,
    parameter SCREEN_H = 480,
    parameter SCALE    = 100
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_tick,

    output reg  [9:0]  v0_x, v0_y,
    output reg  [9:0]  v1_x, v1_y,
    output reg  [9:0]  v2_x, v2_y,
    output reg         valid
);

    // ── Centros de pantalla ───────────────────────────────────
    localparam [9:0] CX = SCREEN_W / 2;
    localparam [9:0] CY = SCREEN_H / 2;

    // ── Tabla LUT sin/cos (64 entradas, Q8.8, 0..2π) ─────────
    // Valor = round(128 * sin(2π*i/64))
    reg signed [8:0] sin_lut [0:63];
    reg signed [8:0] cos_lut [0:63];

    integer lut_i;
    initial begin
        sin_lut[ 0]=9'sd0;   cos_lut[ 0]=9'sd128;
        sin_lut[ 1]=9'sd13;  cos_lut[ 1]=9'sd127;
        sin_lut[ 2]=9'sd25;  cos_lut[ 2]=9'sd124;
        sin_lut[ 3]=9'sd37;  cos_lut[ 3]=9'sd120;
        sin_lut[ 4]=9'sd48;  cos_lut[ 4]=9'sd114;
        sin_lut[ 5]=9'sd59;  cos_lut[ 5]=9'sd107;
        sin_lut[ 6]=9'sd68;  cos_lut[ 6]=9'sd98;
        sin_lut[ 7]=9'sd77;  cos_lut[ 7]=9'sd89;
        sin_lut[ 8]=9'sd83;  cos_lut[ 8]=9'sd78;
        sin_lut[ 9]=9'sd89;  cos_lut[ 9]=9'sd67;
        sin_lut[10]=9'sd93;  cos_lut[10]=9'sd55;
        sin_lut[11]=9'sd96;  cos_lut[11]=9'sd43;
        sin_lut[12]=9'sd98;  cos_lut[12]=9'sd30;
        sin_lut[13]=9'sd99;  cos_lut[13]=9'sd17;
        sin_lut[14]=9'sd99;  cos_lut[14]=9'sd4;
        sin_lut[15]=9'sd99;  cos_lut[15]=-9'sd10;
        sin_lut[16]=9'sd97;  cos_lut[16]=-9'sd22;
        sin_lut[17]=9'sd95;  cos_lut[17]=-9'sd35;
        sin_lut[18]=9'sd91;  cos_lut[18]=-9'sd47;
        sin_lut[19]=9'sd87;  cos_lut[19]=-9'sd58;
        sin_lut[20]=9'sd82;  cos_lut[20]=-9'sd69;
        sin_lut[21]=9'sd75;  cos_lut[21]=-9'sd79;
        sin_lut[22]=9'sd68;  cos_lut[22]=-9'sd88;
        sin_lut[23]=9'sd60;  cos_lut[23]=-9'sd96;
        sin_lut[24]=9'sd51;  cos_lut[24]=-9'sd103;
        sin_lut[25]=9'sd41;  cos_lut[25]=-9'sd109;
        sin_lut[26]=9'sd31;  cos_lut[26]=-9'sd114;
        sin_lut[27]=9'sd20;  cos_lut[27]=-9'sd117;
        sin_lut[28]=9'sd9;   cos_lut[28]=-9'sd120;
        sin_lut[29]=-9'sd2;  cos_lut[29]=-9'sd122;
        sin_lut[30]=-9'sd14; cos_lut[30]=-9'sd122;
        sin_lut[31]=-9'sd25; cos_lut[31]=-9'sd121;
        sin_lut[32]=-9'sd36; cos_lut[32]=-9'sd119;
        sin_lut[33]=-9'sd46; cos_lut[33]=-9'sd116;
        sin_lut[34]=-9'sd56; cos_lut[34]=-9'sd111;
        sin_lut[35]=-9'sd65; cos_lut[35]=-9'sd105;
        sin_lut[36]=-9'sd73; cos_lut[36]=-9'sd98;
        sin_lut[37]=-9'sd80; cos_lut[37]=-9'sd89;
        sin_lut[38]=-9'sd86; cos_lut[38]=-9'sd80;
        sin_lut[39]=-9'sd91; cos_lut[39]=-9'sd70;
        sin_lut[40]=-9'sd95; cos_lut[40]=-9'sd59;
        sin_lut[41]=-9'sd98; cos_lut[41]=-9'sd47;
        sin_lut[42]=-9'sd100;cos_lut[42]=-9'sd35;
        sin_lut[43]=-9'sd100;cos_lut[43]=-9'sd23;
        sin_lut[44]=-9'sd100;cos_lut[44]=-9'sd11;
        sin_lut[45]=-9'sd99; cos_lut[45]=9'sd2;
        sin_lut[46]=-9'sd97; cos_lut[46]=9'sd14;
        sin_lut[47]=-9'sd94; cos_lut[47]=9'sd26;
        sin_lut[48]=-9'sd90; cos_lut[48]=9'sd37;
        sin_lut[49]=-9'sd85; cos_lut[49]=9'sd48;
        sin_lut[50]=-9'sd79; cos_lut[50]=9'sd58;
        sin_lut[51]=-9'sd73; cos_lut[51]=9'sd68;
        sin_lut[52]=-9'sd65; cos_lut[52]=9'sd76;
        sin_lut[53]=-9'sd57; cos_lut[53]=9'sd83;
        sin_lut[54]=-9'sd48; cos_lut[54]=9'sd89;
        sin_lut[55]=-9'sd38; cos_lut[55]=9'sd94;
        sin_lut[56]=-9'sd28; cos_lut[56]=9'sd98;
        sin_lut[57]=-9'sd17; cos_lut[57]=9'sd101;
        sin_lut[58]=-9'sd6;  cos_lut[58]=9'sd103;
        sin_lut[59]=9'sd5;   cos_lut[59]=9'sd104;
        sin_lut[60]=9'sd16;  cos_lut[60]=9'sd103;
        sin_lut[61]=9'sd27;  cos_lut[61]=9'sd101;
        sin_lut[62]=9'sd38;  cos_lut[62]=9'sd97;
        sin_lut[63]=9'sd48;  cos_lut[63]=9'sd93;
    end

    // ── Ángulo de rotación ────────────────────────────────────
    reg [5:0] angle;

    // ── Posiciones de vértices base (relativas al centro) ─────
    // v0: arriba (0, -SCALE)
    // v1: abajo-izquierda (-SCALE*0.87, +SCALE*0.5)
    // v2: abajo-derecha  (+SCALE*0.87, +SCALE*0.5)
    localparam signed [9:0] BASE0_X = 10'sd0;
    localparam signed [9:0] BASE0_Y = -(SCALE);
    localparam signed [9:0] BASE1_X = -(SCALE * 87 / 100);
    localparam signed [9:0] BASE1_Y = (SCALE / 2);
    localparam signed [9:0] BASE2_X = (SCALE * 87 / 100);
    localparam signed [9:0] BASE2_Y = (SCALE / 2);

    // ── Función de rotación ───────────────────────────────────
    // x' = x*cos - y*sin;  y' = x*sin + y*cos  (escala /128)
    function [9:0] rot_x;
        input signed [9:0] bx, by;
        input [5:0] ang;
        reg signed [17:0] rx;
        begin
            rx = ($signed(bx) * $signed(cos_lut[ang]) -
                  $signed(by) * $signed(sin_lut[ang])) >>> 7;
            rot_x = rx[9:0];
        end
    endfunction

    function [9:0] rot_y;
        input signed [9:0] bx, by;
        input [5:0] ang;
        reg signed [17:0] ry;
        begin
            ry = ($signed(bx) * $signed(sin_lut[ang]) +
                  $signed(by) * $signed(cos_lut[ang])) >>> 7;
            rot_y = ry[9:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            angle <= 6'd0;
            v0_x  <= CX; v0_y <= 10'd0;
            v1_x  <= 10'd0; v1_y <= 10'd479;
            v2_x  <= 10'd639; v2_y <= 10'd479;
            valid <= 1'b0;
        end else begin
            valid <= 1'b0;
            if (frame_tick) begin
                angle <= angle + 6'd1;
                v0_x  <= CX + rot_x(BASE0_X, BASE0_Y, angle);
                v0_y  <= CY + rot_y(BASE0_X, BASE0_Y, angle);
                v1_x  <= CX + rot_x(BASE1_X, BASE1_Y, angle);
                v1_y  <= CY + rot_y(BASE1_X, BASE1_Y, angle);
                v2_x  <= CX + rot_x(BASE2_X, BASE2_Y, angle);
                v2_y  <= CY + rot_y(BASE2_X, BASE2_Y, angle);
                valid <= 1'b1;
            end
        end
    end

endmodule
