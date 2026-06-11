`timescale 1ns/1ps






























module gia #(
    parameter integer NUM_OBJECTS = 8,
    parameter integer DATA_WIDTH  = 128,
    parameter integer HIST_LEN    = 2
)(
    input  wire        clk,
    input  wire        rst_n,

    
    input  wire [7:0]              obj_id,      
    input  wire signed [31:0]      pos_x,       
    input  wire signed [31:0]      pos_y,       
    input  wire signed [31:0]      pos_z,       
    input  wire                    pos_valid,   

    
    input  wire                    frame_tick,  
    input  wire                    flush,       

    
    output reg  signed [31:0]      pred_x,      
    output reg  signed [31:0]      pred_y,      
    output reg  signed [31:0]      pred_z,      
    output reg  [7:0]              pred_obj_id, 
    output reg  [7:0]              pred_conf,   
    output reg                     pred_valid,  

    
    output reg  [15:0]             geom_predictions, 
    output reg  [7:0]              active_objects    
);

    
    
    reg signed [31:0] hist_x [0:NUM_OBJECTS-1][0:HIST_LEN-1];
    reg signed [31:0] hist_y [0:NUM_OBJECTS-1][0:HIST_LEN-1];
    reg signed [31:0] hist_z [0:NUM_OBJECTS-1][0:HIST_LEN-1];
    reg        [1:0]  hist_valid [0:NUM_OBJECTS-1]; 

    
    localparam ST_IDLE    = 2'd0;
    localparam ST_STORE   = 2'd1;
    localparam ST_PREDICT = 2'd2;
    localparam ST_EMIT    = 2'd3;

    reg [1:0]  state;
    reg [7:0]  obj_id_r;
    reg signed [31:0] px_r, py_r, pz_r;
    reg signed [31:0] vel_x, vel_y, vel_z;
    reg [7:0]  conf_calc;

    
    reg [7:0]  active_cnt;

    integer oi, hi;

    initial begin
        for (oi = 0; oi < NUM_OBJECTS; oi = oi + 1) begin
            hist_valid[oi] = 2'b00;
            hist_x[oi][0]  = 32'sd0; hist_x[oi][1] = 32'sd0;
            hist_y[oi][0]  = 32'sd0; hist_y[oi][1] = 32'sd0;
            hist_z[oi][0]  = 32'sd0; hist_z[oi][1] = 32'sd0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_IDLE;
            obj_id_r         <= 8'd0;
            px_r             <= 32'sd0;
            py_r             <= 32'sd0;
            pz_r             <= 32'sd0;
            vel_x            <= 32'sd0;
            vel_y            <= 32'sd0;
            vel_z            <= 32'sd0;
            conf_calc        <= 8'd0;
            pred_x           <= 32'sd0;
            pred_y           <= 32'sd0;
            pred_z           <= 32'sd0;
            pred_obj_id      <= 8'd0;
            pred_conf        <= 8'd0;
            pred_valid       <= 1'b0;
            geom_predictions <= 16'd0;
            active_objects   <= 8'd0;
            active_cnt       <= 8'd0;
        end else begin
            pred_valid <= 1'b0;  

            if (flush) begin
                state      <= ST_IDLE;
                active_cnt <= 8'd0;
            end else begin
                case (state)
                    ST_IDLE: begin
                        if (pos_valid) begin
                            obj_id_r <= obj_id;
                            px_r     <= pos_x;
                            py_r     <= pos_y;
                            pz_r     <= pos_z;
                            state    <= ST_STORE;
                        end
                    end

                    ST_STORE: begin
                        begin : blk_gia_store
                            reg [2:0] safe_id;
                            safe_id = obj_id_r[2:0]; 

                            
                            hist_x[safe_id][1] <= hist_x[safe_id][0];
                            hist_y[safe_id][1] <= hist_y[safe_id][0];
                            hist_z[safe_id][1] <= hist_z[safe_id][0];
                            hist_x[safe_id][0] <= px_r;
                            hist_y[safe_id][0] <= py_r;
                            hist_z[safe_id][0] <= pz_r;

                            
                            if (hist_valid[safe_id] == 2'b00) begin
                                hist_valid[safe_id] <= 2'b01;  
                                active_cnt <= active_cnt + 8'd1;
                            end else begin
                                hist_valid[safe_id] <= 2'b11;  
                            end
                        end
                        state <= ST_PREDICT;
                    end

                    ST_PREDICT: begin
                        begin : blk_gia_predict
                            reg [2:0] sid;
                            sid = obj_id_r[2:0];

                            if (hist_valid[sid] == 2'b11) begin
                                
                                vel_x <= hist_x[sid][0] - hist_x[sid][1];
                                vel_y <= hist_y[sid][0] - hist_y[sid][1];
                                vel_z <= hist_z[sid][0] - hist_z[sid][1];
                                
                                conf_calc <= 8'hC0;  
                            end else begin
                                
                                vel_x     <= 32'sd0;
                                vel_y     <= 32'sd0;
                                vel_z     <= 32'sd0;
                                conf_calc <= 8'h40;  
                            end
                        end
                        state <= ST_EMIT;
                    end

                    ST_EMIT: begin
                        begin : blk_gia_emit
                            reg [2:0] sid2;
                            sid2 = obj_id_r[2:0];
                            
                            pred_x      <= hist_x[sid2][0] + vel_x;
                            pred_y      <= hist_y[sid2][0] + vel_y;
                            pred_z      <= hist_z[sid2][0] + vel_z;
                            pred_obj_id <= obj_id_r;
                            pred_conf   <= conf_calc;
                            pred_valid  <= 1'b1;
                            geom_predictions <= geom_predictions + 16'd1;
                            active_objects   <= active_cnt;
                        end
                        state <= ST_IDLE;
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
