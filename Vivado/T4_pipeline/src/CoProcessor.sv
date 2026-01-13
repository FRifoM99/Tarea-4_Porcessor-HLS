`timescale 1ns / 1ps

module CoProcessor #(
    parameter CLK_FREQUENCY = 100_000_000,
    parameter BAUD_RATE     = 115_200,
    parameter N             = 1024
)(
    input  logic CLK100MHZ, 
    input  logic CPU_RESETN,
    input  logic UART_TXD_IN,
    output logic UART_RXD_OUT,
    output logic [7:0] SEG, 
    output logic [7:0] AN,
    output logic [1:0] LED
);

    // =========================================================================
    // SETUP DE RELOJ Y RESET
    // =========================================================================
    logic clk_sys;
    logic reset;
    assign clk_sys = CLK100MHZ; 
    assign reset   = ~CPU_RESETN;

    // =========================================================================
    //  MÁQUINA DE ESTADOS (FSM)
    // =========================================================================
    typedef enum logic [3:0] {
        Standby, 
        WriteVecA, 
        WriteVecB, 
        ReadVecA, 
        ReadVecB,
        TriggerHLS, // Iniciar cálculo
        WaitHLS,    // Esperar ap_done
        SendHLS     // Enviar resultado 32 bits
    } enum_state;

    enum_state state, nx_state;

    // =========================================================================
    // MÓDULO UART
    // =========================================================================
    logic [7:0] rx_data;
    logic [7:0] uart_tx_data_mux; 
    logic rx_ready, uart_tx_start_mux, tx_busy;
    
    uart_basic #(
        .CLK_FREQUENCY(CLK_FREQUENCY),
        .BAUD_RATE(BAUD_RATE)
    ) uart_logic (
        .clk(clk_sys),
        .reset(reset),
        .rx(UART_TXD_IN),
        .tx(UART_RXD_OUT),
        .rx_data(rx_data),
        .tx_data(uart_tx_data_mux),   
        .rx_ready(rx_ready),
        .tx_start(uart_tx_start_mux), 
        .tx_busy(tx_busy)
    );

    // =========================================================================
    // CONTADORES Y CONTROL DE ESCRITURA
    // =========================================================================
    logic [9:0] addr_counter;
    logic addr_inc;
    
    counter_with_inc #(10) master_count(
        .clk(clk_sys),
        .rst(reset || (state != nx_state)), 
        .inc(addr_inc),
        .count(addr_counter)
    );

    logic write_en_A, addr_inc_write_A, job_ok_write_A;
    logic write_en_B, addr_inc_write_B, job_ok_write_B;
    logic [15:0] bram_din_A, bram_din_B; 

    // Controlador Escritura A 
    BramWriteController #(N) write_ctrl_A (
        .clk(clk_sys), .rst(reset), .en(state == WriteVecA),
        .rx_ready(rx_ready), .addr(addr_counter), .rx_data(rx_data),
        .write_en(write_en_A), .addr_inc(addr_inc_write_A), 
        .bram_data_out(bram_din_A), .job_ok(job_ok_write_A)
    );

    // Controlador Escritura B
    BramWriteController #(N) write_ctrl_B (
        .clk(clk_sys), .rst(reset), .en(state == WriteVecB),
        .rx_ready(rx_ready), .addr(addr_counter), .rx_data(rx_data),
        .write_en(write_en_B), .addr_inc(addr_inc_write_B), 
        .bram_data_out(bram_din_B), .job_ok(job_ok_write_B)
    );

    // =========================================================================
    // SEÑALES INTERMEDIAS HLS & MEMORIA
    // =========================================================================
    logic hls_start, hls_done, hls_idle, hls_ready;
    logic hls_mode_reg; 
    logic [31:0] hls_result_raw; 
    
    // OUTPUT del HLS
    logic [31:0] hls_addrA_32, hls_addrB_32; 
    logic hls_enA, hls_enB;
    
    // Señal de control MUX
    logic hls_active;
    assign hls_active = (state == TriggerHLS || state == WaitHLS);

    logic [9:0] final_addrB_A, final_addrB_B;
    logic final_enB_A, final_enB_B;

 
    assign final_addrB_A = hls_active ? hls_addrA_32[10:1] : addr_counter;
    assign final_addrB_B = hls_active ? hls_addrB_32[10:1] : addr_counter;
    
    // Habilitar lectura para ReadVec
    assign final_enB_A   = hls_active ? hls_enA           : 1'b1;
    assign final_enB_B   = hls_active ? hls_enB           : 1'b1;

    // Salidas de datos de las RAMs
    logic [15:0] vecA_dout, vecB_dout;

    // =========================================================================
    // INSTANCIAS DE MEMORIA BRAM
    // =========================================================================
    
    Inferred_BRAM_DualPort #(.DATA_WIDTH(16), .ADDR_WIDTH(10), .DEPTH(N)) RAM_A (
        .clk(clk_sys),
        .we_a(write_en_A), .addr_a(addr_counter), .din_a(bram_din_A), // Port A: Escritura UART
        .en_b(final_enB_A), .addr_b(final_addrB_A), .dout_b(vecA_dout) // Port B: Lectura HLS
    );

    Inferred_BRAM_DualPort #(.DATA_WIDTH(16), .ADDR_WIDTH(10), .DEPTH(N)) RAM_B (
        .clk(clk_sys),
        .we_a(write_en_B), .addr_a(addr_counter), .din_a(bram_din_B),
        .en_b(final_enB_B), .addr_b(final_addrB_B), .dout_b(vecB_dout)
    );

    // =========================================================================
    // INSTANCIA HLS 
    // =========================================================================
    
    core_0 u_hls_inst (
        .ap_clk(clk_sys),               
        .ap_rst(reset),                 
        .ap_done(hls_done),
        .ap_idle(hls_idle),
        .ap_ready(hls_ready),
        .ap_start(hls_start),           
        
        // --- Interfaz Vector A ---
        .vectorA_Addr_A(hls_addrA_32),  // Salida Dir (32 bits) 
        .vectorA_Clk_A(),              //clk global en la RAM)
        .vectorA_Din_A(),               //HLS no escribe
        .vectorA_Dout_A(vecA_dout),     // Entrada Dato 
        .vectorA_EN_A(hls_enA),         // Enable lectura
        .vectorA_Rst_A(),               // No conectado
        .vectorA_WEN_A(),               // No conectado
        
        // --- Interfaz Vector B ---
        .vectorB_Addr_A(hls_addrB_32),  
        .vectorB_Clk_A(),               
        .vectorB_Din_A(),               
        .vectorB_Dout_A(vecB_dout),     // Entrada Dato 
        .vectorB_EN_A(hls_enB),         
        .vectorB_Rst_A(),               
        .vectorB_WEN_A(),               
        
        // --- Escalares ---
        .result(hls_result_raw),        // Resultado 32 bits
        .mode(hls_mode_reg)             // Modo 0 (Dot) o 1 (Euc)
    );

    assign hls_start = (state == TriggerHLS);

    always_ff @(posedge clk_sys) begin
        if (reset) hls_mode_reg <= 0;
        else if (state == Standby && rx_ready) begin
            if (rx_data == 'd6) hls_mode_reg <= 0;      
            else if (rx_data == 'd7) hls_mode_reg <= 1; 
        end
    end

    // =========================================================================
    //  LECTURA DEBUG 
    // =========================================================================
    logic readA_tx, readB_tx;
    logic [7:0] readA_data_uart, readB_data_uart;
    logic readA_elem_done, readB_elem_done;

    ReadVecOp Read_Vect_A_inst(
        .clk(clk_sys), .rst(reset), .en(state == ReadVecA),
        .vec_data(vecA_dout[9:0]),  
        .tx_busy(tx_busy), .tx_start(readA_tx),
        .tx_data(readA_data_uart), .element_done(readA_elem_done)
    );

    ReadVecOp Read_Vect_B_inst(
        .clk(clk_sys), .rst(reset), .en(state == ReadVecB),
        .vec_data(vecB_dout[9:0]),  
        .tx_busy(tx_busy), .tx_start(readB_tx),
        .tx_data(readB_data_uart), .element_done(readB_elem_done)
    );

    // =========================================================================
    // ENVÍO DE RESULTADOS 
    // =========================================================================
    logic sender_tx_start, sender_done;
    logic [7:0] sender_tx_data;

    Envio_32bits sender_inst (
        .clk(clk_sys), .rst(reset), .en(state == SendHLS),      
        .data_in(hls_result_raw),   
        .tx_busy(tx_busy),          
        .tx_start(sender_tx_start), 
        .tx_data(sender_tx_data),   
        .done(sender_done)          
    );

    // =========================================================================
    // VISUALIZACIÓN 
    // =========================================================================
    
    // LEDs indicadores de modo
    assign LED[0] = (hls_mode_reg == 1'b1); // ON si es Euc Dist
    assign LED[1] = (hls_mode_reg == 1'b0); // ON si es Dot Prod

    // Display Hex
    HexDisplay hex_disp_inst(
        .clk(clk_sys),
        .rst(reset),
        .data_in(hls_result_raw), 
        .mode_in(hls_mode_reg),   
        .seg(SEG),
        .an(AN)
    );

    // =========================================================================
    //  FSM 
    // =========================================================================
    logic job_ok; 


    always_ff @(posedge clk_sys) begin
        if (reset) state <= Standby;
        else       state <= nx_state;
    end

 
    always_comb begin
        nx_state = state;
        
        if (state == Standby && rx_ready) begin
            case (rx_data)
                'd1: nx_state = WriteVecA;
                'd2: nx_state = WriteVecB;
                'd3: nx_state = ReadVecA;
                'd4: nx_state = ReadVecB;
                'd6: nx_state = TriggerHLS; 
                'd7: nx_state = TriggerHLS; 
                default: nx_state = Standby;
            endcase
        end else begin
            case (state)
                WriteVecA: if (job_ok) nx_state = Standby;
                WriteVecB: if (job_ok) nx_state = Standby;
                ReadVecA:  if (job_ok) nx_state = Standby;
                ReadVecB:  if (job_ok) nx_state = Standby;
                
                TriggerHLS: nx_state = WaitHLS; 
                WaitHLS:    if (hls_done) nx_state = SendHLS;
                SendHLS:    if (sender_done) nx_state = Standby;
                
                default: nx_state = Standby;
            endcase
        end
    end

    always_comb begin
        job_ok = 0;
        addr_inc = 0;
        uart_tx_start_mux = 0;
        uart_tx_data_mux = 0;
        
        case (state)
            Standby: addr_inc = 0;
            
            WriteVecA: begin 
                addr_inc = addr_inc_write_A; 
                job_ok   = job_ok_write_A; 
            end
            WriteVecB: begin 
                addr_inc = addr_inc_write_B; 
                job_ok   = job_ok_write_B; 
            end      
            
            ReadVecA: begin
                uart_tx_start_mux = readA_tx;
                uart_tx_data_mux  = readA_data_uart;
                addr_inc          = readA_elem_done;
                job_ok            = (addr_counter == N-1 && addr_inc) ? 1 : 0;
            end   
            ReadVecB: begin
                uart_tx_start_mux = readB_tx;
                uart_tx_data_mux  = readB_data_uart;
                addr_inc          = readB_elem_done;
                job_ok            = (addr_counter == N-1 && addr_inc) ? 1 : 0;
            end   

            SendHLS: begin
                uart_tx_start_mux = sender_tx_start;
                uart_tx_data_mux  = sender_tx_data;
            end
            
            default: begin end
        endcase  
    end

    ila_0 your_instance_name (
	.clk(clk_sys), // input wire clk


	.probe0(hls_start), // input wire [0:0]  probe0  
	.probe1(hls_done), // input wire [0:0]  probe1 
	.probe2(hls_ready), // input wire [0:0]  probe2 
	.probe3(hls_mode_reg) // input wire [0:0]  probe3
);
endmodule