`timescale 1ns / 1ps

module Inferred_BRAM_DualPort #(
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 10,
    parameter DEPTH      = 1024
)(
    input  logic                    clk,

    // Port A, UART
    input  logic                    we_a,
    input  logic [ADDR_WIDTH-1:0]   addr_a,
    input  logic [DATA_WIDTH-1:0]   din_a,
    output logic [DATA_WIDTH-1:0]   dout_a, 

    // Port B, HLS
    input  logic                    en_b,
    input  logic [ADDR_WIDTH-1:0]   addr_b,
    output logic [DATA_WIDTH-1:0]   dout_b
);

    // Declaración de la memoria
    // "block" fuerza el uso de Block RAM. 
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] ram [0:DEPTH-1];

    // PORT A (Escritura/Lectura) 
    always_ff @(posedge clk) begin
        if (we_a) begin
            ram[addr_a] <= din_a;
        end
        dout_a <= ram[addr_a];
    end

    // PORT B (Solo Lectura con Enable) 
    always_ff @(posedge clk) begin
        if (en_b) begin
            dout_b <= ram[addr_b];
        end
    end

endmodule