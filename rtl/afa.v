`timescale 1ns/1ps



































module afa #(
    parameter integer LUT_SIZE    = 64,
    parameter integer PHASE_MAX   = 32,
    parameter integer PHASE_PERIOD = 16,
    parameter integer DATA_WIDTH  = 128
)(
    input  wire        clk,
    input  wire        rst_n,

    
    input  wire        enable,          
    input  wire        phase_reset,     

    
    input  wire [7:0]  lut_x,           
    input  wire [7:0]  lut_y,           
    input  wire        lut_valid,       

    
    output reg  signed [15:0] delta_x,  
    output reg  signed [15:0] delta_y,  
    output reg  signed [15:0] delta_z,  
    output reg                out_valid, 

    
    output reg  [4:0]  phase_out,       
    output wire        wave_ready,      
    output reg  [15:0] lookups_done,    
    output reg  [15:0] phase_cycles     
);

    
    

    
    
    
    
    reg [23:0] wave_lut [0:LUT_SIZE-1];

    integer li;
    initial begin
        
        
        wave_lut[ 0] = 24'h00_00_00; wave_lut[ 1] = 24'h0C_0C_F4;
        wave_lut[ 2] = 24'h18_18_E8; wave_lut[ 3] = 24'h23_23_DD;
        wave_lut[ 4] = 24'h2D_2D_D3; wave_lut[ 5] = 24'h36_36_CA;
        wave_lut[ 6] = 24'h3E_3E_C2; wave_lut[ 7] = 24'h45_45_BB;
        wave_lut[ 8] = 24'h4A_4A_B6; wave_lut[ 9] = 24'h4E_4E_B2;
        wave_lut[10] = 24'h51_51_AF; wave_lut[11] = 24'h53_53_AD;
        wave_lut[12] = 24'h54_54_AC; wave_lut[13] = 24'h53_53_AD;
        wave_lut[14] = 24'h51_51_AF; wave_lut[15] = 24'h4E_4E_B2;
        wave_lut[16] = 24'h4A_4A_B6; wave_lut[17] = 24'h45_45_BB;
        wave_lut[18] = 24'h3E_3E_C2; wave_lut[19] = 24'h36_36_CA;
        wave_lut[20] = 24'h2D_2D_D3; wave_lut[21] = 24'h23_23_DD;
        wave_lut[22] = 24'h18_18_E8; wave_lut[23] = 24'h0C_0C_F4;
        wave_lut[24] = 24'h00_00_00; wave_lut[25] = 24'hF4_F4_0C;
        wave_lut[26] = 24'hE8_E8_18; wave_lut[27] = 24'hDD_DD_23;
        wave_lut[28] = 24'hD3_D3_2D; wave_lut[29] = 24'hCA_CA_36;
        wave_lut[30] = 24'hC2_C2_3E; wave_lut[31] = 24'hBB_BB_45;
        wave_lut[32] = 24'hB6_B6_4A; wave_lut[33] = 24'hB2_B2_4E;
        wave_lut[34] = 24'hAF_AF_51; wave_lut[35] = 24'hAD_AD_53;
        wave_lut[36] = 24'hAC_AC_54; wave_lut[37] = 24'hAD_AD_53;
        wave_lut[38] = 24'hAF_AF_51; wave_lut[39] = 24'hB2_B2_4E;
        wave_lut[40] = 24'hB6_B6_4A; wave_lut[41] = 24'hBB_BB_45;
        wave_lut[42] = 24'hC2_C2_3E; wave_lut[43] = 24'hCA_CA_36;
        wave_lut[44] = 24'hD3_D3_2D; wave_lut[45] = 24'hDD_DD_23;
        wave_lut[46] = 24'hE8_E8_18; wave_lut[47] = 24'hF4_F4_0C;
        wave_lut[48] = 24'h00_00_00; wave_lut[49] = 24'h0C_0C_F4;
        wave_lut[50] = 24'h18_18_E8; wave_lut[51] = 24'h23_23_DD;
        wave_lut[52] = 24'h2D_2D_D3; wave_lut[53] = 24'h36_36_CA;
        wave_lut[54] = 24'h3E_3E_C2; wave_lut[55] = 24'h45_45_BB;
        wave_lut[56] = 24'h4A_4A_B6; wave_lut[57] = 24'h4E_4E_B2;
        wave_lut[58] = 24'h51_51_AF; wave_lut[59] = 24'h53_53_AD;
        wave_lut[60] = 24'h54_54_AC; wave_lut[61] = 24'h53_53_AD;
        wave_lut[62] = 24'h51_51_AF; wave_lut[63] = 24'h4E_4E_B2;
    end

    
    reg [7:0]  phase_timer;   
    reg [4:0]  phase_reg;     

    
    reg        lut_valid_r;
    reg [7:0]  lut_x_r, lut_y_r;
    reg [4:0]  phase_r;

    
    assign wave_ready = enable;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_timer   <= 8'd0;
            phase_reg     <= 5'd0;
            phase_out     <= 5'd0;
            lut_valid_r   <= 1'b0;
            lut_x_r       <= 8'd0;
            lut_y_r       <= 8'd0;
            phase_r       <= 5'd0;
            delta_x       <= 16'sd0;
            delta_y       <= 16'sd0;
            delta_z       <= 16'sd0;
            out_valid     <= 1'b0;
            lookups_done  <= 16'd0;
            phase_cycles  <= 16'd0;
        end else begin
            
            if (phase_reset) begin
                phase_timer <= 8'd0;
                phase_reg   <= 5'd0;
                phase_out   <= 5'd0;
            end else if (enable) begin
                if (phase_timer >= PHASE_PERIOD - 1) begin
                    phase_timer <= 8'd0;
                    phase_reg   <= (phase_reg == PHASE_MAX - 1) ?
                                    5'd0 : phase_reg + 5'd1;
                    phase_out   <= (phase_reg == PHASE_MAX - 1) ?
                                    5'd0 : phase_reg + 5'd1;
                    phase_cycles <= phase_cycles + 16'd1;
                end else begin
                    phase_timer <= phase_timer + 8'd1;
                end
            end

            
            lut_valid_r <= lut_valid & enable;
            lut_x_r     <= lut_x;
            lut_y_r     <= lut_y;
            phase_r     <= phase_reg;

            
            out_valid <= 1'b0;
            if (lut_valid_r) begin
                
                
                
                begin : blk_afa_lut
                    reg [5:0] idx;
                    reg [23:0] lut_val;
                    idx     = (lut_x_r[5:0] ^ lut_y_r[5:0] ^ {1'b0, phase_r});
                    lut_val = wave_lut[idx];
                    
                    delta_x <= {{8{lut_val[7]}},  lut_val[7:0]};
                    delta_y <= {{8{lut_val[15]}}, lut_val[15:8]};
                    delta_z <= {{8{lut_val[23]}}, lut_val[23:16]};
                    out_valid     <= 1'b1;
                    lookups_done  <= lookups_done + 16'd1;
                end
            end
        end
    end

endmodule
