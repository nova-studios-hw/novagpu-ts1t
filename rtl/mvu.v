`timescale 1ns/1ps








































module mvu #(
    parameter REAL_FRAMES = 2,
    parameter GEN_FRAMES  = 4,
    parameter DATA_WIDTH  = 128,
    parameter BUF_DEPTH   = 256
)(
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire [DATA_WIDTH-1:0]  frame_in,
    input  wire                   in_valid,

    input  wire [15:0]            mv_x,
    input  wire [15:0]            mv_y,
    input  wire                   mv_valid,

    output reg  [DATA_WIDTH-1:0]  frame_out,
    output reg                    frame_valid,
    output reg  [2:0]             frame_count,
    output reg                    mvu_ready,

    output reg  [15:0]            frames_real,
    output reg  [15:0]            frames_generated,
    output reg  [15:0]            mv_applied
);

    localparam BUF_BITS = $clog2(BUF_DEPTH);

    reg [DATA_WIDTH-1:0] fbuf [0:BUF_DEPTH-1];
    reg [BUF_BITS-1:0]   wr_ptr, rd_ptr;
    reg [BUF_BITS:0]     fill_count;

    reg signed [15:0] mv_x_r, mv_y_r;
    reg               mv_loaded;

    reg [2:0] gen_phase;

    
    reg [DATA_WIDTH-1:0] frame_in_latch;

    wire [DATA_WIDTH-1:0] buf_tok = fbuf[rd_ptr];

    wire signed [15:0] px_off = mv_loaded ?
        ($signed(mv_x_r) * $signed({13'd0, gen_phase})) >>> 2 : 16'sd0;
    wire signed [15:0] py_off = mv_loaded ?
        ($signed(mv_y_r) * $signed({13'd0, gen_phase})) >>> 2 : 16'sd0;

    wire signed [15:0] px_shifted = $signed(buf_tok[63:48]) + px_off;
    wire signed [15:0] py_shifted = $signed(buf_tok[47:32]) + py_off;

    wire [DATA_WIDTH-1:0] mv_token =
        {buf_tok[127:64], px_shifted, py_shifted, buf_tok[31:0]};

    localparam ST_IDLE   = 2'd0;
    localparam ST_STORE  = 2'd1;
    localparam ST_GENOUT = 2'd2;

    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_IDLE;
            mvu_ready        <= 1'b1;
            frame_valid      <= 1'b0;
            frame_count      <= 3'd0;
            wr_ptr           <= {BUF_BITS{1'b0}};
            rd_ptr           <= {BUF_BITS{1'b0}};
            fill_count       <= {(BUF_BITS+1){1'b0}};
            gen_phase        <= 3'd0;
            mv_x_r           <= 16'sd0;
            mv_y_r           <= 16'sd0;
            mv_loaded        <= 1'b0;
            frames_real      <= 16'd0;
            frames_generated <= 16'd0;
            mv_applied       <= 16'd0;
            frame_in_latch   <= {DATA_WIDTH{1'b0}};
        end else begin
            
            

            if (mv_valid) begin
                mv_x_r    <= $signed(mv_x);
                mv_y_r    <= $signed(mv_y);
                mv_loaded <= 1'b1;
            end

            case (state)
                ST_IDLE: begin
                    mvu_ready <= 1'b1;
                    if (in_valid) begin
                        
                        frame_in_latch <= frame_in;
                        mvu_ready      <= 1'b0;
                        state          <= ST_STORE;
                    end
                end

                ST_STORE: begin
                    
                    
                    fbuf[wr_ptr] <= frame_in_latch;
                    wr_ptr <= (wr_ptr == BUF_DEPTH - 1) ?
                              {BUF_BITS{1'b0}} : wr_ptr + {{(BUF_BITS-1){1'b0}}, 1'b1};

                    if (fill_count < BUF_DEPTH)
                        fill_count <= fill_count + {{BUF_BITS{1'b0}}, 1'b1};

                    
                    frame_out   <= frame_in_latch;
                    frame_valid <= 1'b1;   
                    frame_count <= 3'd0;
                    frames_real <= frames_real + 16'd1;

                    if (mv_loaded && fill_count > {(BUF_BITS+1){1'b0}}) begin
                        gen_phase <= 3'd1;
                        rd_ptr    <= {BUF_BITS{1'b0}};
                        state     <= ST_GENOUT;
                    end else begin
                        mvu_ready <= 1'b1;
                        state     <= ST_IDLE;
                    end
                end

                ST_GENOUT: begin
                    if (fill_count > {(BUF_BITS+1){1'b0}}) begin
                        frame_out   <= mv_token;
                        frame_valid <= 1'b1;
                        frame_count <= {1'b0, gen_phase};
                        mv_applied  <= mv_applied + 16'd1;

                        rd_ptr <= (rd_ptr == BUF_DEPTH - 1) ?
                                  {BUF_BITS{1'b0}} : rd_ptr + {{(BUF_BITS-1){1'b0}}, 1'b1};
                    end

                    if (gen_phase >= GEN_FRAMES - 1) begin
                        frames_generated <= frames_generated + 16'd1;
                        mvu_ready        <= 1'b1;
                        state            <= ST_IDLE;
                    end else begin
                        gen_phase <= gen_phase + 3'd1;
                    end
                end

                default: begin
                    mvu_ready <= 1'b1;
                    state     <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
