`timescale 1ns/1ps

































module mpe #(
    parameter integer HISTORY_DEPTH = 4,
    parameter integer NUM_ENTRIES   = 16,
    parameter integer DATA_WIDTH    = 128,
    parameter integer CONF_THRESH   = 192   
)(
    input  wire                    clk,
    input  wire                    rst_n,

    
    input  wire [DATA_WIDTH-1:0]   obs_token,   
    input  wire                    obs_valid,   

    
    input  wire                    frame_tick,  
    input  wire                    flush,       

    
    output reg  [DATA_WIDTH-1:0]   pred_token,       
    output reg  [7:0]              pred_confidence,  
    output reg                     pred_valid,       
    output reg                     prefetch_req,     

    
    output reg  [15:0]             predictions_made, 
    output reg  [15:0]             prefetches_issued,
    output reg  [3:0]              history_fill      
);

    
    reg [DATA_WIDTH-1:0] history [0:HISTORY_DEPTH-1];
    reg [1:0]            hist_ptr;  
    

    
    
    reg [DATA_WIDTH-1:0] pred_table_tok [0:NUM_ENTRIES-1];
    reg [7:0]            pred_table_cnt [0:NUM_ENTRIES-1];
    reg [3:0]            pred_table_ptr; 

    
    
    localparam ST_IDLE    = 2'd0;
    localparam ST_OBSERVE = 2'd1;
    localparam ST_PREDICT = 2'd2;
    localparam ST_EMIT    = 2'd3;

    reg [1:0]  state;
    reg [DATA_WIDTH-1:0] obs_latch;
    reg [3:0]  search_idx;
    reg        found_match;
    reg [7:0]  best_conf;
    reg [DATA_WIDTH-1:0] best_tok;

    integer init_i;

    initial begin
        for (init_i = 0; init_i < NUM_ENTRIES; init_i = init_i + 1) begin
            pred_table_tok[init_i] = {DATA_WIDTH{1'b0}};
            pred_table_cnt[init_i] = 8'd0;
        end
        for (init_i = 0; init_i < HISTORY_DEPTH; init_i = init_i + 1)
            history[init_i] = {DATA_WIDTH{1'b0}};
    end

    
    

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hist_ptr         <= 2'd0;
            history_fill        <= 4'd0;
            pred_table_ptr   <= 4'd0;
            state            <= ST_IDLE;
            obs_latch        <= {DATA_WIDTH{1'b0}};
            search_idx       <= 4'd0;
            found_match      <= 1'b0;
            best_conf        <= 8'd0;
            best_tok         <= {DATA_WIDTH{1'b0}};
            pred_token       <= {DATA_WIDTH{1'b0}};
            pred_confidence  <= 8'd0;
            pred_valid       <= 1'b0;
            prefetch_req     <= 1'b0;
            predictions_made <= 16'd0;
            prefetches_issued<= 16'd0;
        end else begin
            
            prefetch_req <= 1'b0;
            pred_valid   <= 1'b0;

            if (flush) begin
                hist_ptr       <= 2'd0;
                history_fill      <= 4'd0;
                pred_table_ptr <= 4'd0;
                state          <= ST_IDLE;
            end else begin
                case (state)
                    
                    ST_IDLE: begin
                        if (obs_valid) begin
                            obs_latch <= obs_token;
                            state     <= ST_OBSERVE;
                        end
                    end

                    
                    ST_OBSERVE: begin
                        history[hist_ptr] <= obs_latch;
                        hist_ptr <= (hist_ptr == HISTORY_DEPTH - 1) ?
                                     2'd0 : hist_ptr + 2'd1;
                        if (history_fill < HISTORY_DEPTH)
                            history_fill <= history_fill + 4'd1;

                        
                        
                        
                        begin : blk_mpe_upd
                            reg found_upd;
                            reg [3:0] upd_idx;
                            integer si;
                            found_upd = 1'b0;
                            upd_idx   = 4'd0;
                            for (si = 0; si < NUM_ENTRIES; si = si + 1) begin
                                if (!found_upd &&
                                    pred_table_tok[si] == obs_latch) begin
                                    found_upd = 1'b1;
                                    upd_idx   = si[3:0];
                                end
                            end
                            if (found_upd) begin
                                
                                if (pred_table_cnt[upd_idx] < 8'hFF)
                                    pred_table_cnt[upd_idx] <=
                                        pred_table_cnt[upd_idx] + 8'd1;
                            end else begin
                                
                                if (pred_table_ptr < NUM_ENTRIES) begin
                                    pred_table_tok[pred_table_ptr] <= obs_latch;
                                    pred_table_cnt[pred_table_ptr] <= 8'd1;
                                    pred_table_ptr <= pred_table_ptr + 4'd1;
                                end
                            end
                        end

                        
                        search_idx  <= 4'd0;
                        found_match <= 1'b0;
                        best_conf   <= 8'd0;
                        best_tok    <= {DATA_WIDTH{1'b0}};
                        state       <= ST_PREDICT;
                    end

                    
                    ST_PREDICT: begin
                        begin : blk_mpe_pred
                            reg [3:0] si2;
                            reg [7:0] max_cnt;
                            reg [DATA_WIDTH-1:0] max_tok;
                            integer pj;
                            max_cnt = 8'd0;
                            max_tok = {DATA_WIDTH{1'b0}};
                            for (pj = 0; pj < NUM_ENTRIES; pj = pj + 1) begin
                                if (pred_table_cnt[pj] > max_cnt) begin
                                    max_cnt = pred_table_cnt[pj];
                                    max_tok = pred_table_tok[pj];
                                end
                            end
                            best_conf <= max_cnt;
                            best_tok  <= max_tok;
                        end
                        state <= ST_EMIT;
                    end

                    
                    ST_EMIT: begin
                        pred_token      <= best_tok;
                        pred_confidence <= best_conf;
                        pred_valid      <= 1'b1;
                        predictions_made <= predictions_made + 16'd1;

                        if (best_conf >= CONF_THRESH) begin
                            prefetch_req      <= 1'b1;
                            prefetches_issued <= prefetches_issued + 16'd1;
                        end
                        state <= ST_IDLE;
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
