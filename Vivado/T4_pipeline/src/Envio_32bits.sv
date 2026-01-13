`timescale 1ns / 1ps

module Envio_32bits(
    input  logic        clk,
    input  logic        rst,
    input  logic        en,          
    input  logic [31:0] data_in,
    input  logic        tx_busy,     
    output logic        tx_start,    
    output logic [7:0]  tx_data,     
    output logic        done         
);

    // CORRECCIÓN AQUÍ: [3:0] en lugar de [2:0]
    // 3 bits = max 8 estados. Necesitamos 10 estados, así que usamos 4 bits.
    typedef enum logic [3:0] {
        IDLE,
        SEND_B0, WAIT_B0,
        SEND_B1, WAIT_B1,
        SEND_B2, WAIT_B2,
        SEND_B3, WAIT_B3,
        FINISHED
    } state_t;

    state_t state, next_state;
    logic [31:0] data_reg;

    // Lógica secuencial
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            data_reg <= 0;
        end else begin
            state <= next_state;
            // Capturamos el dato al inicio para que no cambie mientras enviamos
            if (state == IDLE && en) begin
                data_reg <= data_in; 
            end
        end
    end

    // Máquina de Estados
    always_comb begin
        next_state = state;
        tx_start = 0;
        tx_data = 0;
        done = 0;

        case (state)
            IDLE: begin
                if (en) next_state = SEND_B0;
            end

            // --- Byte 0 (Menos significativo [7:0]) ---
            SEND_B0: begin
                tx_data = data_reg[7:0];
                tx_start = 1;
                // Si la UART no está ocupada, pasamos a esperar
                if (!tx_busy) next_state = WAIT_B0; 
            end
            WAIT_B0: begin
                if (tx_busy) next_state = WAIT_B0; 
                else         next_state = SEND_B1; 
            end

            // --- Byte 1 [15:8] ---
            SEND_B1: begin
                tx_data = data_reg[15:8];
                tx_start = 1;
                if (!tx_busy) next_state = WAIT_B1;
            end
            WAIT_B1: begin
                if (tx_busy) next_state = WAIT_B1;
                else         next_state = SEND_B2;
            end

            // --- Byte 2 [23:16] ---
            SEND_B2: begin
                tx_data = data_reg[23:16];
                tx_start = 1;
                if (!tx_busy) next_state = WAIT_B2;
            end
            WAIT_B2: begin
                if (tx_busy) next_state = WAIT_B2;
                else         next_state = SEND_B3;
            end

            // --- Byte 3 (Más significativo [31:24]) ---
            SEND_B3: begin
                tx_data = data_reg[31:24];
                tx_start = 1;
                if (!tx_busy) next_state = WAIT_B3;
            end
            WAIT_B3: begin
                if (tx_busy) next_state = WAIT_B3;
                else         next_state = FINISHED;
            end

            FINISHED: begin
                done = 1;
                // Volvemos a IDLE solo si 'en' ya bajó para evitar reinicio inmediato
                if (!en) next_state = IDLE; 
            end
            
            default: next_state = IDLE;
        endcase
    end
endmodule