`timescale 1ns/1ps


































module nexus #(
    parameter integer TOTAL_ENTRIES = 256,
    parameter integer DATA_WIDTH    = 128,
    parameter integer ADDR_WIDTH    = 32,
    parameter integer NUM_BANKS     = 5
)(
    input  wire                    clk,
    input  wire                    rst_n,

    
    input  wire [ADDR_WIDTH-1:0]   a_addr,
    input  wire [DATA_WIDTH-1:0]   a_wdata,
    input  wire                    a_req,
    input  wire                    a_wen,    
    input  wire [2:0]              a_bank,   
    output reg  [DATA_WIDTH-1:0]   a_rdata,
    output reg                     a_ack,    
    output reg                     a_hit,    

    
    input  wire [ADDR_WIDTH-1:0]   b_addr,
    input  wire                    b_req,
    input  wire [2:0]              b_bank,
    output reg  [DATA_WIDTH-1:0]   b_rdata,
    output reg                     b_ack,
    output reg                     b_hit,

    
    input  wire [ADDR_WIDTH-1:0]   pf_addr,
    input  wire [DATA_WIDTH-1:0]   pf_data,
    input  wire                    pf_valid, 
    input  wire [2:0]              pf_bank,

    
    input  wire [2:0]              flush_bank,
    input  wire                    flush_valid,

    
    output reg  [15:0]             hit_count,
    output reg  [15:0]             miss_count,
    output reg  [15:0]             evict_count,
    output reg  [15:0]             prefetch_fills,
    output wire [7:0]              occupancy  
);

    
    
    
    reg [DATA_WIDTH-1:0] mem_data  [0:TOTAL_ENTRIES-1];
    reg [ADDR_WIDTH-1:0] mem_tag   [0:TOTAL_ENTRIES-1];
    reg [2:0]            mem_bank  [0:TOTAL_ENTRIES-1];
    reg                  mem_valid [0:TOTAL_ENTRIES-1];
    reg [7:0]            mem_lru   [0:TOTAL_ENTRIES-1]; 

    
    reg [7:0]  lru_tick;
    reg [7:0]  occ_cnt;     

    assign occupancy = occ_cnt;

    
    

    integer init_i;
    initial begin
        for (init_i = 0; init_i < TOTAL_ENTRIES; init_i = init_i + 1) begin
            mem_data [init_i] = {DATA_WIDTH{1'b0}};
            mem_tag  [init_i] = {ADDR_WIDTH{1'b0}};
            mem_bank [init_i] = 3'd0;
            mem_valid[init_i] = 1'b0;
            mem_lru  [init_i] = 8'd0;
        end
    end

    
    always @(posedge clk or negedge rst_n) begin : blk_nexus_main
        integer i;
        if (!rst_n) begin
            a_rdata       <= {DATA_WIDTH{1'b0}};
            a_ack         <= 1'b0;
            a_hit         <= 1'b0;
            b_rdata       <= {DATA_WIDTH{1'b0}};
            b_ack         <= 1'b0;
            b_hit         <= 1'b0;
            hit_count     <= 16'd0;
            miss_count    <= 16'd0;
            evict_count   <= 16'd0;
            prefetch_fills<= 16'd0;
            lru_tick      <= 8'd0;
            occ_cnt       <= 8'd0;
            for (i = 0; i < TOTAL_ENTRIES; i = i + 1) begin
                mem_valid[i] <= 1'b0;
                mem_lru[i]   <= 8'd0;
            end
        end else begin
            
            a_ack <= 1'b0;
            b_ack <= 1'b0;

            
            lru_tick <= lru_tick + 8'd1;

            
            if (flush_valid) begin
                for (i = 0; i < TOTAL_ENTRIES; i = i + 1) begin
                    if (mem_bank[i] == flush_bank && mem_valid[i]) begin
                        mem_valid[i] <= 1'b0;
                        occ_cnt      <= (occ_cnt > 8'd0) ? occ_cnt - 8'd1 : 8'd0;
                    end
                end
            end

            
            if (pf_valid) begin
                begin : blk_nexus_pf
                    reg        pf_already;
                    reg [7:0]  pf_slot;
                    reg [7:0]  pf_evict_slot;
                    reg [7:0]  pf_lru_min;
                    integer pi;
                    pf_already   = 1'b0;
                    pf_slot      = 8'd0;
                    pf_evict_slot= 8'd0;
                    pf_lru_min   = 8'hFF;

                    
                    for (pi = 0; pi < TOTAL_ENTRIES; pi = pi + 1) begin
                        if (mem_valid[pi] && mem_tag[pi] == pf_addr &&
                            mem_bank[pi] == pf_bank)
                            pf_already = 1'b1;
                    end

                    if (!pf_already) begin
                        
                        pf_slot = 8'hFF;
                        for (pi = 0; pi < TOTAL_ENTRIES; pi = pi + 1) begin
                            if (!mem_valid[pi] && pf_slot == 8'hFF)
                                pf_slot = pi[7:0];
                        end
                        if (pf_slot == 8'hFF) begin
                            
                            for (pi = 0; pi < TOTAL_ENTRIES; pi = pi + 1) begin
                                if (mem_lru[pi] < pf_lru_min) begin
                                    pf_lru_min    = mem_lru[pi];
                                    pf_evict_slot = pi[7:0];
                                end
                            end
                            pf_slot = pf_evict_slot;
                            evict_count <= evict_count + 16'd1;
                        end else begin
                            occ_cnt <= occ_cnt + 8'd1;
                        end
                        mem_data [pf_slot] <= pf_data;
                        mem_tag  [pf_slot] <= pf_addr;
                        mem_bank [pf_slot] <= pf_bank;
                        mem_valid[pf_slot] <= 1'b1;
                        mem_lru  [pf_slot] <= lru_tick;
                        prefetch_fills     <= prefetch_fills + 16'd1;
                    end
                end
            end

            
            if (a_req) begin
                if (a_wen) begin
                    
                    begin : blk_nexus_wa
                        reg [7:0]  wa_slot;
                        reg [7:0]  wa_lru_min;
                        reg [7:0]  wa_evict;
                        integer wi;
                        wa_slot    = 8'hFF;
                        wa_lru_min = 8'hFF;
                        wa_evict   = 8'd0;

                        
                        for (wi = 0; wi < TOTAL_ENTRIES; wi = wi + 1) begin
                            if (mem_valid[wi] && mem_tag[wi] == a_addr &&
                                mem_bank[wi] == a_bank && wa_slot == 8'hFF)
                                wa_slot = wi[7:0];
                        end
                        if (wa_slot == 8'hFF) begin
                            for (wi = 0; wi < TOTAL_ENTRIES; wi = wi + 1) begin
                                if (!mem_valid[wi] && wa_slot == 8'hFF)
                                    wa_slot = wi[7:0];
                            end
                            if (wa_slot == 8'hFF) begin
                                for (wi = 0; wi < TOTAL_ENTRIES; wi = wi + 1) begin
                                    if (mem_lru[wi] < wa_lru_min) begin
                                        wa_lru_min = mem_lru[wi];
                                        wa_evict   = wi[7:0];
                                    end
                                end
                                wa_slot = wa_evict;
                                evict_count <= evict_count + 16'd1;
                            end else begin
                                occ_cnt <= occ_cnt + 8'd1;
                            end
                        end
                        mem_data [wa_slot] <= a_wdata;
                        mem_tag  [wa_slot] <= a_addr;
                        mem_bank [wa_slot] <= a_bank;
                        mem_valid[wa_slot] <= 1'b1;
                        mem_lru  [wa_slot] <= lru_tick;
                    end
                    a_hit <= 1'b1;  
                    a_ack <= 1'b1;
                end else begin
                    
                    begin : blk_nexus_ra
                        reg        ra_found;
                        reg [DATA_WIDTH-1:0] ra_data;
                        integer ri2;
                        ra_found = 1'b0;
                        ra_data  = {DATA_WIDTH{1'b0}};
                        for (ri2 = 0; ri2 < TOTAL_ENTRIES; ri2 = ri2 + 1) begin
                            if (!ra_found && mem_valid[ri2] &&
                                mem_tag[ri2] == a_addr &&
                                mem_bank[ri2] == a_bank) begin
                                ra_found = 1'b1;
                                ra_data  = mem_data[ri2];
                                mem_lru[ri2] <= lru_tick; 
                            end
                        end
                        a_rdata <= ra_data;
                        a_hit   <= ra_found;
                        a_ack   <= 1'b1;
                        if (ra_found)
                            hit_count  <= hit_count  + 16'd1;
                        else
                            miss_count <= miss_count + 16'd1;
                    end
                end
            end

            
            if (b_req) begin
                begin : blk_nexus_rb
                    reg        rb_found;
                    reg [DATA_WIDTH-1:0] rb_data;
                    integer ri3;
                    rb_found = 1'b0;
                    rb_data  = {DATA_WIDTH{1'b0}};
                    for (ri3 = 0; ri3 < TOTAL_ENTRIES; ri3 = ri3 + 1) begin
                        if (!rb_found && mem_valid[ri3] &&
                            mem_tag[ri3] == b_addr &&
                            mem_bank[ri3] == b_bank) begin
                            rb_found = 1'b1;
                            rb_data  = mem_data[ri3];
                            mem_lru[ri3] <= lru_tick;
                        end
                    end
                    b_rdata <= rb_data;
                    b_hit   <= rb_found;
                    b_ack   <= 1'b1;
                    if (rb_found)
                        hit_count  <= hit_count  + 16'd1;
                    else
                        miss_count <= miss_count + 16'd1;
                end
            end
        end
    end

endmodule
