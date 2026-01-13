`timescale 1ns / 1ps

module Inferred_BRAM_DualPort #(
    parameter DATA_WIDTH = 16,  // Ancho de palabra (bits)
    parameter ADDR_WIDTH = 10,  // Bits de dirección 
    parameter DEPTH      = 1024 // Profundidad total
)(
    input  logic                  clk,
    
    // --- PUERTO A (Escritura) ---
    input  logic                  we_a,
    input  logic [ADDR_WIDTH-1:0] addr_a,
    input  logic [DATA_WIDTH-1:0] din_a,
    
    // --- PUERTO B (Lectura) ---
    input  logic                  en_b,
    input  logic [ADDR_WIDTH-1:0] addr_b,
    output logic [DATA_WIDTH-1:0] dout_b
);

    // Definición del Array de Memoria
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] ram [0:DEPTH-1];
    
    logic [DATA_WIDTH-1:0] ram_data_b = {DATA_WIDTH{1'b0}};

    // -------------------------------------------------------------------------
    // PUERTO A 
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (we_a) begin
            ram[addr_a] <= din_a;
        end
    end

    // -------------------------------------------------------------------------
    // pUERTO B
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (en_b) begin
            ram_data_b <= ram[addr_b];
        end
    end

    // Asignación de salida
    assign dout_b = ram_data_b;

endmodule