`timescale 1ns / 1ps

module HexDisplay(
    input  logic        clk,
    input  logic        rst,
    input  logic [31:0] data_in,
    input  logic        mode_in, 
    output logic [7:0]  seg,     
    output logic [7:0]  an       
);

    logic [19:0] refresh_counter;
    logic [2:0]  digit_select;
    logic [3:0]  hex_digit;
    logic        dot_on; 

    always_ff @(posedge clk) begin
        if (rst) refresh_counter <= 0;
        else     refresh_counter <= refresh_counter + 1;
    end

    assign digit_select = refresh_counter[19:17];

    // Selección de Ánodos y Datos
    always_comb begin
        dot_on = 0;
        
        case (digit_select)
            3'b000: begin an = 8'b11111110; hex_digit = data_in[3:0];   end
            3'b001: begin an = 8'b11111101; hex_digit = data_in[7:4];   end
            3'b010: begin an = 8'b11111011; hex_digit = data_in[11:8];  end
            3'b011: begin an = 8'b11110111; hex_digit = data_in[15:12]; end
            
            // Dígito 4 
            3'b100: begin 
                an = 8'b11101111; 
                hex_digit = data_in[19:16]; 
                

                if (mode_in == 1'b1) dot_on = 1; 
            end
            
            3'b101: begin an = 8'b11011111; hex_digit = data_in[23:20]; end
            3'b110: begin an = 8'b10111111; hex_digit = data_in[27:24]; end
            3'b111: begin an = 8'b01111111; hex_digit = data_in[31:28]; end
            default: begin an = 8'b11111111; hex_digit = 4'b0000; end
        endcase
    end

    logic [6:0] segments_raw;
    always_comb begin
        case (hex_digit)
            4'h0: segments_raw = 7'b1000000;
            4'h1: segments_raw = 7'b1111001;
            4'h2: segments_raw = 7'b0100100;
            4'h3: segments_raw = 7'b0110000;
            4'h4: segments_raw = 7'b0011001;
            4'h5: segments_raw = 7'b0010010;
            4'h6: segments_raw = 7'b0000010;
            4'h7: segments_raw = 7'b1111000;
            4'h8: segments_raw = 7'b0000000;
            4'h9: segments_raw = 7'b0010000;
            4'hA: segments_raw = 7'b0001000;
            4'hB: segments_raw = 7'b0000011;
            4'hC: segments_raw = 7'b1000110;
            4'hD: segments_raw = 7'b0100001;
            4'hE: segments_raw = 7'b0000110;
            4'hF: segments_raw = 7'b0001110;
            default: segments_raw = 7'b1111111; 
        endcase
        seg = {~dot_on, segments_raw}; 
    end
endmodule