`timescale 1ns / 1ps

module BramWriteController #(
    parameter N = 1024
)(
    input  logic        clk,
    input  logic        rst,
    input  logic        en,             // Habilitador del módulo (State == WriteVecA/B)
    input  logic        rx_ready,       // Pulso de dato nuevo en UART
    input  logic [9:0]  addr,           // Dirección actual (viene del contador maestro)
    input  logic [7:0]  rx_data,        // Dato recibido por UART
    output logic        write_en,       // Enable de escritura para la BRAM
    output logic        addr_inc,       // Pulso para incrementar contador maestro
    output logic [15:0] bram_data_out,  // Dato ensamblado (16 bits) hacia la BRAM
    output logic        job_ok          // Indica que se terminó de escribir todo el vector
);

    typedef enum logic [2:0] {
        IDLE,
        WAIT_MSB,   // Esperando el byte alto
        WAIT_LSB,   // Esperando el byte bajo
        WRITE_MEM,  // Escribir en RAM
        INC_ADDR    // Incrementar dirección
    } state_t;

    state_t state, nx_state;
    logic [15:0] data_reg; // Registro temporal para armar los 2 bytes

    // Lógica Secuencial
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            data_reg <= 0;
        end else begin
            state <= nx_state;
            
            // Guardar MSB
            if (state == WAIT_MSB && rx_ready)
                data_reg[15:8] <= rx_data;
                
            // Guardar LSB
            if (state == WAIT_LSB && rx_ready)
                data_reg[7:0] <= rx_data;
        end
    end

    // Máquina de Estados
    always_comb begin
        nx_state = state;
        write_en = 0;
        addr_inc = 0;
        job_ok = 0;
        bram_data_out = data_reg; // El dato siempre está disponible en la salida

        case (state)
            IDLE: begin
                if (en) nx_state = WAIT_MSB;
            end

            WAIT_MSB: begin
                if (!en) nx_state = IDLE;
                else if (rx_ready) nx_state = WAIT_LSB;
            end

            WAIT_LSB: begin
                if (!en) nx_state = IDLE;
                else if (rx_ready) nx_state = WRITE_MEM;
            end

            WRITE_MEM: begin
                write_en = 1; 
                nx_state = INC_ADDR;
            end

            INC_ADDR: begin
                addr_inc = 1; // Incrementa dirección
                if (addr == N-1) job_ok = 1;
                else             nx_state = WAIT_MSB; 
            end
            
            default: nx_state = IDLE;
        endcase
    end

endmodule