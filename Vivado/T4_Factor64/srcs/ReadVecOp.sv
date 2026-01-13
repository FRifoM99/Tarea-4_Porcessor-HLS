`timescale 1ns / 1ps

module ReadVecOp(
    input  logic        clk, 
    input  logic        rst, 
    input  logic        en,
    input  logic [9:0]  vec_data,     // Data desde BRAM (10 bits)
    input  logic        tx_busy,
    output logic        tx_start,
    output logic [7:0]  tx_data,
    output logic        element_done
);
    
    // Sintaxis robusta para FSM
    typedef enum logic [1:0] {
        IDLE, 
        WAIT_DATA, 
        SEND_MSB, 
        SEND_LSB
    } state_t;
    
    state_t state, nx_state;
    logic [9:0] data_reg; 

    // Captura de datos (Latencia BRAM)
    always_ff @(posedge clk)
        if (rst) 
            data_reg <= '0;
        else if (state == WAIT_DATA) 
            data_reg <= vec_data;

    // Secuencial FSM
    always_ff @(posedge clk)
        if (rst) state <= IDLE;
        else     state <= nx_state;

    // Combinacional FSM
    always_comb begin
        nx_state = state;
        tx_start = 1'b0;
        tx_data = 8'b0;
        element_done = 1'b0;

        case(state)
            IDLE:
                if (en) nx_state = WAIT_DATA; 
        
            WAIT_DATA:
                nx_state = SEND_MSB; 
                                            
            SEND_MSB: begin
                tx_start = ~tx_busy;
                tx_data = {6'b000000, data_reg[9:8]}; 
                if (tx_start) nx_state = SEND_LSB;
            end
            
            SEND_LSB: begin
                tx_start = ~tx_busy;
                tx_data = data_reg[7:0]; 
                if (tx_start) begin
                    element_done = 1'b1; 
                    nx_state = IDLE;     
                end
            end
            
            default: nx_state = IDLE;
        endcase
    end
endmodule