`timescale 1ns/1ps


































module token_matching_unit #(
    parameter NUM_SLOTS  = 64,
    parameter TAG_WIDTH  = 16,
    parameter DATA_WIDTH = 128,
    parameter TIMEOUT    = 1024
)(
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire [TAG_WIDTH-1:0]    in_tag,
    input  wire [DATA_WIDTH-1:0]   in_data,
    input  wire                    in_valid,
    output wire                    in_ready,

    output reg  [TAG_WIDTH-1:0]    fire_tag,
    output reg  [DATA_WIDTH-1:0]   fire_data_a,
    output reg  [DATA_WIDTH-1:0]   fire_data_b,
    output reg                     fire_valid,

    output wire [TAG_WIDTH-1:0]    occupancy
);

    localparam NUM_SETS  = NUM_SLOTS / 2;
    localparam SET_BITS  = $clog2(NUM_SETS);
    localparam TO_BITS   = $clog2(TIMEOUT + 1);

    
    reg                   slot_valid [0:NUM_SETS-1];
    reg [TAG_WIDTH-1:0]   slot_tag   [0:NUM_SETS-1];
    reg [DATA_WIDTH-1:0]  slot_data  [0:NUM_SETS-1];
    reg [TO_BITS-1:0]     slot_timer [0:NUM_SETS-1];

    
    reg [TAG_WIDTH-1:0] occ_cnt;
    assign occupancy = occ_cnt;

    
    
    
    reg [TAG_WIDTH-1:0]   in_tag_r;
    reg [DATA_WIDTH-1:0]  in_data_r;
    reg                   in_valid_r;

    
    
    
    assign in_ready = (occ_cnt < (NUM_SETS - 1));

    
    wire [SET_BITS-1:0] set_idx = in_tag_r[SET_BITS-1:0];

    
    wire slot_match = slot_valid[set_idx] & (slot_tag[set_idx] == in_tag_r);
    wire slot_empty = ~slot_valid[set_idx];

    
    reg [SET_BITS-1:0] scan_ptr;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            occ_cnt    <= {TAG_WIDTH{1'b0}};
            scan_ptr   <= {SET_BITS{1'b0}};
            fire_valid   <= 1'b0;
            fire_tag     <= {TAG_WIDTH{1'b0}};
            fire_data_a  <= {DATA_WIDTH{1'b0}};
            fire_data_b  <= {DATA_WIDTH{1'b0}};
            in_tag_r     <= {TAG_WIDTH{1'b0}};
            in_data_r    <= {DATA_WIDTH{1'b0}};
            in_valid_r   <= 1'b0;
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                slot_valid[i] <= 1'b0;
                slot_tag[i]   <= {TAG_WIDTH{1'b0}};
                slot_data[i]  <= {DATA_WIDTH{1'b0}};
                slot_timer[i] <= {TO_BITS{1'b0}};
            end
        end else begin
            
            
            in_tag_r   <= in_tag;
            in_data_r  <= in_data;
            in_valid_r <= in_valid & in_ready;

            
            fire_valid <= 1'b0;

            
            if (in_valid_r) begin
                if (slot_match) begin
                    
                    fire_valid             <= 1'b1;
                    fire_tag               <= in_tag_r;
                    fire_data_a            <= slot_data[set_idx]; 
                    fire_data_b            <= in_data_r;           
                    slot_valid[set_idx]    <= 1'b0;
                    slot_timer[set_idx]    <= {TO_BITS{1'b0}};
                    if (occ_cnt > {TAG_WIDTH{1'b0}})
                        occ_cnt <= occ_cnt - {{(TAG_WIDTH-1){1'b0}}, 1'b1};
                end else if (slot_empty) begin
                    
                    slot_valid[set_idx]   <= 1'b1;
                    slot_tag[set_idx]     <= in_tag_r;
                    slot_data[set_idx]    <= in_data_r;
                    slot_timer[set_idx]   <= {TO_BITS{1'b0}};
                    occ_cnt               <= occ_cnt + {{(TAG_WIDTH-1){1'b0}}, 1'b1};
                end
                
            end

            
            if (slot_valid[scan_ptr] &&
                !(in_valid_r && (scan_ptr == set_idx) && slot_match)) begin
                if (slot_timer[scan_ptr] >= TIMEOUT[TO_BITS-1:0]) begin
                    slot_valid[scan_ptr] <= 1'b0;
                    slot_timer[scan_ptr] <= {TO_BITS{1'b0}};
                    if (occ_cnt > {TAG_WIDTH{1'b0}})
                        occ_cnt <= occ_cnt - {{(TAG_WIDTH-1){1'b0}}, 1'b1};
                end else begin
                    slot_timer[scan_ptr] <= slot_timer[scan_ptr] +
                                            {{(TO_BITS-1){1'b0}}, 1'b1};
                end
            end

            scan_ptr <= (scan_ptr == NUM_SETS - 1) ?
                        {SET_BITS{1'b0}} : scan_ptr + {{(SET_BITS-1){1'b0}}, 1'b1};
        end
    end

endmodule