`timescale 1ns/1ps






























module pva #(
    parameter integer TILE_COLS = 16,
    parameter integer TILE_ROWS = 12,
    parameter integer DATA_WIDTH = 128
)(
    input  wire        clk,
    input  wire        rst_n,

    
    input  wire signed [15:0]  cam_dx,     
    input  wire signed [15:0]  cam_dy,     
    input  wire                cam_mv_valid, 

    
    input  wire [3:0]          upd_tile_x, 
    input  wire [3:0]          upd_tile_y, 
    input  wire                upd_visible,
    input  wire                upd_valid,  

    
    input  wire [3:0]          q_tile_x,   
    input  wire [3:0]          q_tile_y,   
    input  wire                q_valid,    

    
    output reg                 vis_result,     
    output reg  [7:0]          vis_confidence, 
    output reg                 vis_out_valid,  

    
    output reg  [3:0]          prefetch_tile_x,
    output reg  [3:0]          prefetch_tile_y,
    output reg                 prefetch_valid,

    
    output reg  [15:0]         vis_hits,    
    output reg  [15:0]         vis_culls,   
    output reg  [15:0]         map_updates  
);

    
    
    reg [8:0] vis_map [0:TILE_ROWS-1][0:TILE_COLS-1];

    
    reg signed [15:0] last_cam_dx;
    reg signed [15:0] last_cam_dy;
    reg               cam_moved;

    
    wire signed [4:0] shift_x = cam_dx[12:8];  
    wire signed [4:0] shift_y = cam_dy[12:8];

    integer ri, ci;

    
    initial begin
        for (ri = 0; ri < TILE_ROWS; ri = ri + 1)
            for (ci = 0; ci < TILE_COLS; ci = ci + 1)
                vis_map[ri][ci] = 9'h1_FF; 
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_cam_dx     <= 16'sd0;
            last_cam_dy     <= 16'sd0;
            cam_moved       <= 1'b0;
            vis_result      <= 1'b0;
            vis_confidence  <= 8'd0;
            vis_out_valid   <= 1'b0;
            prefetch_tile_x <= 4'd0;
            prefetch_tile_y <= 4'd0;
            prefetch_valid  <= 1'b0;
            vis_hits        <= 16'd0;
            vis_culls       <= 16'd0;
            map_updates     <= 16'd0;
            
            for (ri = 0; ri < TILE_ROWS; ri = ri + 1)
                for (ci = 0; ci < TILE_COLS; ci = ci + 1)
                    vis_map[ri][ci] <= 9'h1_FF;
        end else begin
            
            vis_out_valid  <= 1'b0;
            prefetch_valid <= 1'b0;

            
            if (upd_valid) begin
                vis_map[upd_tile_y][upd_tile_x] <=
                    {upd_visible, upd_visible ? 8'hFF : 8'h00};
                map_updates <= map_updates + 16'd1;
            end

            
            if (cam_mv_valid) begin
                last_cam_dx <= cam_dx;
                last_cam_dy <= cam_dy;
                cam_moved   <= 1'b1;

                
                
                
                if (cam_dx > 16'sd0) begin
                    
                    for (ri = 0; ri < TILE_ROWS; ri = ri + 1)
                        vis_map[ri][0] <= 9'h1_40; 
                end else if (cam_dx < 16'sd0) begin
                    for (ri = 0; ri < TILE_ROWS; ri = ri + 1)
                        vis_map[ri][TILE_COLS-1] <= 9'h1_40;
                end

                if (cam_dy > 16'sd0) begin
                    for (ci = 0; ci < TILE_COLS; ci = ci + 1)
                        vis_map[0][ci] <= 9'h1_40;
                end else if (cam_dy < 16'sd0) begin
                    for (ci = 0; ci < TILE_COLS; ci = ci + 1)
                        vis_map[TILE_ROWS-1][ci] <= 9'h1_40;
                end

                
                prefetch_tile_x <= (cam_dx > 16'sd0) ? 4'd0  : 4'd15;
                prefetch_tile_y <= 4'd6;
                prefetch_valid  <= 1'b1;
            end

            
            if (q_valid) begin
                begin : blk_pva_vis
                    reg [8:0] entry;
                    entry          = vis_map[q_tile_y][q_tile_x];
                    vis_result     = entry[8];        
                    vis_confidence = entry[7:0];      
                    vis_out_valid  <= 1'b1;
                    if (entry[8])
                        vis_hits  <= vis_hits + 16'd1;
                    else
                        vis_culls <= vis_culls + 16'd1;
                end
            end
        end
    end

endmodule