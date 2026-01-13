`timescale 1ns / 1ps

module Inferred_BRAM_DualPort #(
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 3,  // 1024 / 128 = 8 posiciones -> 3 bits
    parameter DEPTH      = 8
)(
    input  logic                    clk,
    input  logic                    we_a,
    input  logic [ADDR_WIDTH-1:0]   addr_a,
    input  logic [DATA_WIDTH-1:0]   din_a,
    output logic [DATA_WIDTH-1:0]   dout_a, 
    input  logic                    en_b,
    input  logic [ADDR_WIDTH-1:0]   addr_b,
    output logic [DATA_WIDTH-1:0]   dout_b
);

    // LUTRAM (Distributed)
    (* ram_style = "distributed" *) logic [DATA_WIDTH-1:0] ram [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (we_a) ram[addr_a] <= din_a;
        dout_a <= ram[addr_a];
    end

    always_ff @(posedge clk) begin
        if (en_b) dout_b <= ram[addr_b];
    end

endmodule