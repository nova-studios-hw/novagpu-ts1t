`timescale 1ns/1ps
































module neon_sram_controller #(
  parameter NUM_BANKS       = 64,
  parameter BANK_SIZE       = 4194304,
  parameter DATA_WIDTH      = 128,
  parameter PREFETCH_DEPTH  = 8,
  parameter CONFLICT_THRESH = 100
)(
  input  wire                   clk,
  input  wire                   rst_n,

  input  wire  [31:0]           addr_i,
  input  wire  [DATA_WIDTH-1:0] wdata_i,
  input  wire                   req_i,
  input  wire                   wen_i,
  output reg   [DATA_WIDTH-1:0] rdata_o,
  output reg                    ack_o,
  output wire                   conflict_o
);

  localparam BANK_SEL_BITS = 6; 

  wire [5:0]  bank_sel  = addr_i[5:0];
  wire [25:0] bank_addr = addr_i[31:6];

  
  reg [DATA_WIDTH-1:0] pf_data  [0:PREFETCH_DEPTH-1];
  reg [31:0]           pf_addr  [0:PREFETCH_DEPTH-1];
  reg                  pf_valid [0:PREFETCH_DEPTH-1];
  reg [2:0]            pf_tail;

  
  reg                  prefetch_hit;
  reg [DATA_WIDTH-1:0] prefetch_hit_data;

  integer ci;
  
  always @(pf_valid[0], pf_valid[1], pf_valid[2], pf_valid[3],
           pf_valid[4], pf_valid[5], pf_valid[6], pf_valid[7],
           pf_addr[0],  pf_addr[1],  pf_addr[2],  pf_addr[3],
           pf_addr[4],  pf_addr[5],  pf_addr[6],  pf_addr[7],
           pf_data[0],  pf_data[1],  pf_data[2],  pf_data[3],
           pf_data[4],  pf_data[5],  pf_data[6],  pf_data[7],
           addr_i) begin
    prefetch_hit      <= 1'b0;
    prefetch_hit_data <= {DATA_WIDTH{1'b0}};
    for (ci = 0; ci < PREFETCH_DEPTH; ci = ci + 1) begin
      if (pf_valid[ci] && pf_addr[ci] == addr_i) begin
        prefetch_hit      <= 1'b1;
        prefetch_hit_data <= pf_data[ci];
      end
    end
  end

  
  reg [3:0] miss_counter;
  reg       miss_pending;

  
  
  

  function [DATA_WIDTH-1:0] procedural_data;
    input [31:0] addr;
    input [5:0] fn_bank_sel;
    reg [15:0] pattern_base;
    reg [7:0] checker_x, checker_y;
    reg [31:0] z_value;
    begin
      
      pattern_base = {fn_bank_sel, 10'b0};  

      
      checker_x = addr[7:0];
      checker_y = addr[15:8];

      if ((checker_x[4] ^ checker_y[4]) == 1'b0)
        pattern_base = pattern_base ^ 16'h00FF;
      else
        pattern_base = pattern_base ^ 16'h0000;

      
      z_value = addr[25:2] * 16'h0100;  

      
      procedural_data = {
        pattern_base,                    
        8'h80,                          
        addr[11:4],                     
        z_value,                        
        fn_bank_sel, fn_bank_sel,             
        addr[15:0],                     
        addr[31:16],                    
        addr[15:0]                      
      };
    end
  endfunction

  
  reg [DATA_WIDTH-1:0] miss_data_reg;

  integer ri;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      miss_pending   <= 1'b0;
      miss_counter   <= 4'd0;
      ack_o          <= 1'b0;
      rdata_o        <= {DATA_WIDTH{1'b0}};
      miss_data_reg  <= {DATA_WIDTH{1'b0}};
      pf_tail        <= 3'd0;
      for (ri = 0; ri < PREFETCH_DEPTH; ri = ri + 1)
        pf_valid[ri] <= 1'b0;
    end else begin
      if (req_i && !wen_i) begin
        if (prefetch_hit) begin
          rdata_o      <= prefetch_hit_data;
          ack_o        <= 1'b1;
          miss_pending <= 1'b0;
        end else if (!miss_pending) begin
          miss_pending <= 1'b1;
          miss_counter <= 4'd8;
          ack_o        <= 1'b0;
          
          miss_data_reg <= procedural_data(addr_i, bank_sel);
        end else if (miss_counter > 4'd0) begin
          if (miss_counter > 0) miss_counter <= miss_counter - 4'd1;
          ack_o        <= 1'b0;
        end else begin
          
          rdata_o              <= miss_data_reg;
          ack_o                <= 1'b1;
          miss_pending         <= 1'b0;
          
          pf_data[pf_tail]     <= miss_data_reg;
          pf_addr[pf_tail]     <= addr_i;
          pf_valid[pf_tail]    <= 1'b1;
          pf_tail              <= (pf_tail == PREFETCH_DEPTH-1) ? 3'd0 : pf_tail + 3'd1;
        end
      end else if (req_i && wen_i) begin
        ack_o <= 1'b1;
      end else begin
        ack_o <= 1'b0;
      end
    end
  end

  reg [15:0] conflict_count;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      conflict_count <= 16'd0;
    else if (miss_pending && req_i)
      conflict_count <= conflict_count + 16'd1;
  end

  assign conflict_o = (conflict_count > CONFLICT_THRESH[15:0]);

endmodule



module async_handshake #(
  parameter DATA_WIDTH = 128
)(
  input  wire                   clk_src,
  input  wire                   clk_dst,
  input  wire                   rst_n,

  input  wire                   req_i,
  output wire                   ack_o,
  input  wire  [DATA_WIDTH-1:0] data_i,

  output wire                   req_o,
  input  wire                   ack_i,
  output wire  [DATA_WIDTH-1:0] data_o
);

  reg req_sync_1, req_sync_2;

  always @(posedge clk_dst or negedge rst_n) begin
    if (!rst_n) begin
      req_sync_1 <= 1'b0;
      req_sync_2 <= 1'b0;
    end else begin
      req_sync_1 <= req_i;
      req_sync_2 <= req_sync_1;
    end
  end

  reg [DATA_WIDTH-1:0] data_reg;
  always @(posedge clk_dst or negedge rst_n) begin
    if (!rst_n)
      data_reg <= {DATA_WIDTH{1'b0}};
    else if (req_sync_2 && !ack_i)
      data_reg <= data_i;
  end

  assign req_o  = req_sync_2;
  assign data_o = data_reg;
  assign ack_o  = ack_i;

endmodule
