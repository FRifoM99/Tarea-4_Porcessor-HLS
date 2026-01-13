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
        WriteVecA, WriteVecB, 
        ReadVecA,  ReadVecB,
        TriggerHLS, WaitHLS, SendHLS
    } enum_state;

    enum_state state, nx_state;

    // =========================================================================
    // UART
    // =========================================================================
    logic [7:0] rx_data;
    logic [7:0] uart_tx_data_mux; 
    logic rx_ready, uart_tx_start_mux, tx_busy;
    
    uart_basic #(
        .CLK_FREQUENCY(CLK_FREQUENCY),
        .BAUD_RATE(BAUD_RATE)
    ) uart_logic (
        .clk(clk_sys), .reset(reset),
        .rx(UART_TXD_IN), .tx(UART_RXD_OUT),
        .rx_data(rx_data), .tx_data(uart_tx_data_mux),   
        .rx_ready(rx_ready), .tx_start(uart_tx_start_mux), .tx_busy(tx_busy)
    );

    // =========================================================================
    // CONTROL DE ESCRITURA Y DIRECCIONAMIENTO GLOBAL
    // =========================================================================
    logic [9:0] addr_counter; // 0 a 1023
    logic addr_inc;
    
    counter_with_inc #(10) master_count(
        .clk(clk_sys), .rst(reset || (state != nx_state)), 
        .inc(addr_inc), .count(addr_counter)
    );

    logic write_en_A, addr_inc_write_A, job_ok_write_A;
    logic write_en_B, addr_inc_write_B, job_ok_write_B;
    logic [15:0] bram_din_A, bram_din_B; 

    // Controlado UART
    BramWriteController #(N) write_ctrl_A (
        .clk(clk_sys), .rst(reset), .en(state == WriteVecA),
        .rx_ready(rx_ready), .addr(addr_counter), .rx_data(rx_data),
        .write_en(write_en_A), .addr_inc(addr_inc_write_A), 
        .bram_data_out(bram_din_A), .job_ok(job_ok_write_A)
    );

    BramWriteController #(N) write_ctrl_B (
        .clk(clk_sys), .rst(reset), .en(state == WriteVecB),
        .rx_ready(rx_ready), .addr(addr_counter), .rx_data(rx_data),
        .write_en(write_en_B), .addr_inc(addr_inc_write_B), 
        .bram_data_out(bram_din_B), .job_ok(job_ok_write_B)
    );

    // =========================================================================
    // BANCOS DE MEMORIA (PARTITION FACTOR 16)
    // =========================================================================
    // Total: 16 bancos para A, 16 bancos para B.

    
    logic [15:0] ram_A_dout [0:15];
    logic [15:0] ram_B_dout [0:15];
    
    // Señales que vienen del HLS 
    logic [5:0]  hls_A_addr [0:15];
    logic        hls_A_ce   [0:15];
    logic [5:0]  hls_B_addr [0:15];
    logic        hls_B_ce   [0:15];

    logic [3:0] bank_sel;       // 0-15
    logic [5:0] bank_addr_uart; // 0-63
    
    assign bank_sel       = addr_counter[3:0]; // 4 bits bajos eligen banco
    assign bank_addr_uart = addr_counter[9:4]; // 6 bits altos direccionan dentro

    logic hls_active;
    assign hls_active = (state == TriggerHLS || state == WaitHLS);

    // GENERACIÓN DE LOS 32 BANCOS DE MEMORIA
    genvar i;
    generate
        for (i = 0; i < 16; i++) begin : RAM_BANKS
            
            logic        we_bank_A;
            logic        en_bank_A;
            logic [5:0]  addr_bank_A;

            assign we_bank_A = write_en_A && (bank_sel == i);
            
            // Mux de Enable: HLS o (Debug/Write)
            assign en_bank_A = hls_active ? hls_A_ce[i] : 1'b1;
            
            // Mux de Dirección: HLS o UART
            assign addr_bank_A = hls_active ? hls_A_addr[i] : bank_addr_uart;

            // Instancia RAM A[i]
            Inferred_BRAM_DualPort #(.DATA_WIDTH(16), .ADDR_WIDTH(6), .DEPTH(64)) RAM_A_INST (
                .clk(clk_sys),
                .we_a(we_bank_A), .addr_a(bank_addr_uart), .din_a(bram_din_A), // Port A (Escritura) usa direccionamiento UART
                .en_b(en_bank_A), .addr_b(addr_bank_A), .dout_b(ram_A_dout[i]) // Port B (Lectura) Muxed
            );


            //  Lógica Mux para Banco 'i' del Vector B 
            logic        we_bank_B;
            logic        en_bank_B;
            logic [5:0]  addr_bank_B;

            assign we_bank_B = write_en_B && (bank_sel == i);
            assign en_bank_B = hls_active ? hls_B_ce[i] : 1'b1;
            assign addr_bank_B = hls_active ? hls_B_addr[i] : bank_addr_uart;

            // Instancia RAM B[i]
            Inferred_BRAM_DualPort #(.DATA_WIDTH(16), .ADDR_WIDTH(6), .DEPTH(64)) RAM_B_INST (
                .clk(clk_sys),
                .we_a(we_bank_B), .addr_a(bank_addr_uart), .din_a(bram_din_B),
                .en_b(en_bank_B), .addr_b(addr_bank_B), .dout_b(ram_B_dout[i])
            );
        end
    endgenerate

    // =========================================================================
    // NSTANCIA CORE HLS
    // =========================================================================
    
    logic [31:0] hls_result_raw;
    logic hls_start, hls_done, hls_idle, hls_ready, hls_mode_reg;

    processing_core_16_0 u_hls_inst (
        // Control
        .ap_clk(clk_sys), .ap_rst(reset),
        .ap_start(hls_start), .ap_done(hls_done), .ap_idle(hls_idle), .ap_ready(hls_ready),
        .result(hls_result_raw), .mode(hls_mode_reg),

        // --- VECTOR A (16 Puertos) ---
        // Banco 0
        .vectorA_0_ce0(hls_A_ce[0]), .vectorA_0_address0(hls_A_addr[0]), .vectorA_0_q0(ram_A_dout[0]),
        // Banco 1
        .vectorA_1_ce0(hls_A_ce[1]), .vectorA_1_address0(hls_A_addr[1]), .vectorA_1_q0(ram_A_dout[1]),
        // Banco 2
        .vectorA_2_ce0(hls_A_ce[2]), .vectorA_2_address0(hls_A_addr[2]), .vectorA_2_q0(ram_A_dout[2]),
        // Banco 3
        .vectorA_3_ce0(hls_A_ce[3]), .vectorA_3_address0(hls_A_addr[3]), .vectorA_3_q0(ram_A_dout[3]),
        // Banco 4
        .vectorA_4_ce0(hls_A_ce[4]), .vectorA_4_address0(hls_A_addr[4]), .vectorA_4_q0(ram_A_dout[4]),
        // Banco 5
        .vectorA_5_ce0(hls_A_ce[5]), .vectorA_5_address0(hls_A_addr[5]), .vectorA_5_q0(ram_A_dout[5]),
        // Banco 6
        .vectorA_6_ce0(hls_A_ce[6]), .vectorA_6_address0(hls_A_addr[6]), .vectorA_6_q0(ram_A_dout[6]),
        // Banco 7
        .vectorA_7_ce0(hls_A_ce[7]), .vectorA_7_address0(hls_A_addr[7]), .vectorA_7_q0(ram_A_dout[7]),
        // Banco 8
        .vectorA_8_ce0(hls_A_ce[8]), .vectorA_8_address0(hls_A_addr[8]), .vectorA_8_q0(ram_A_dout[8]),
        // Banco 9
        .vectorA_9_ce0(hls_A_ce[9]), .vectorA_9_address0(hls_A_addr[9]), .vectorA_9_q0(ram_A_dout[9]),
        // Banco 10
        .vectorA_10_ce0(hls_A_ce[10]), .vectorA_10_address0(hls_A_addr[10]), .vectorA_10_q0(ram_A_dout[10]),
        // Banco 11
        .vectorA_11_ce0(hls_A_ce[11]), .vectorA_11_address0(hls_A_addr[11]), .vectorA_11_q0(ram_A_dout[11]),
        // Banco 12
        .vectorA_12_ce0(hls_A_ce[12]), .vectorA_12_address0(hls_A_addr[12]), .vectorA_12_q0(ram_A_dout[12]),
        // Banco 13
        .vectorA_13_ce0(hls_A_ce[13]), .vectorA_13_address0(hls_A_addr[13]), .vectorA_13_q0(ram_A_dout[13]),
        // Banco 14
        .vectorA_14_ce0(hls_A_ce[14]), .vectorA_14_address0(hls_A_addr[14]), .vectorA_14_q0(ram_A_dout[14]),
        // Banco 15
        .vectorA_15_ce0(hls_A_ce[15]), .vectorA_15_address0(hls_A_addr[15]), .vectorA_15_q0(ram_A_dout[15]),

        // --- VECTOR B (16 Puertos) ---
        .vectorB_0_ce0(hls_B_ce[0]), .vectorB_0_address0(hls_B_addr[0]), .vectorB_0_q0(ram_B_dout[0]),
        .vectorB_1_ce0(hls_B_ce[1]), .vectorB_1_address0(hls_B_addr[1]), .vectorB_1_q0(ram_B_dout[1]),
        .vectorB_2_ce0(hls_B_ce[2]), .vectorB_2_address0(hls_B_addr[2]), .vectorB_2_q0(ram_B_dout[2]),
        .vectorB_3_ce0(hls_B_ce[3]), .vectorB_3_address0(hls_B_addr[3]), .vectorB_3_q0(ram_B_dout[3]),
        .vectorB_4_ce0(hls_B_ce[4]), .vectorB_4_address0(hls_B_addr[4]), .vectorB_4_q0(ram_B_dout[4]),
        .vectorB_5_ce0(hls_B_ce[5]), .vectorB_5_address0(hls_B_addr[5]), .vectorB_5_q0(ram_B_dout[5]),
        .vectorB_6_ce0(hls_B_ce[6]), .vectorB_6_address0(hls_B_addr[6]), .vectorB_6_q0(ram_B_dout[6]),
        .vectorB_7_ce0(hls_B_ce[7]), .vectorB_7_address0(hls_B_addr[7]), .vectorB_7_q0(ram_B_dout[7]),
        .vectorB_8_ce0(hls_B_ce[8]), .vectorB_8_address0(hls_B_addr[8]), .vectorB_8_q0(ram_B_dout[8]),
        .vectorB_9_ce0(hls_B_ce[9]), .vectorB_9_address0(hls_B_addr[9]), .vectorB_9_q0(ram_B_dout[9]),
        .vectorB_10_ce0(hls_B_ce[10]), .vectorB_10_address0(hls_B_addr[10]), .vectorB_10_q0(ram_B_dout[10]),
        .vectorB_11_ce0(hls_B_ce[11]), .vectorB_11_address0(hls_B_addr[11]), .vectorB_11_q0(ram_B_dout[11]),
        .vectorB_12_ce0(hls_B_ce[12]), .vectorB_12_address0(hls_B_addr[12]), .vectorB_12_q0(ram_B_dout[12]),
        .vectorB_13_ce0(hls_B_ce[13]), .vectorB_13_address0(hls_B_addr[13]), .vectorB_13_q0(ram_B_dout[13]),
        .vectorB_14_ce0(hls_B_ce[14]), .vectorB_14_address0(hls_B_addr[14]), .vectorB_14_q0(ram_B_dout[14]),
        .vectorB_15_ce0(hls_B_ce[15]), .vectorB_15_address0(hls_B_addr[15]), .vectorB_15_q0(ram_B_dout[15])
    );
    
    assign hls_start = (state == TriggerHLS);

    // =========================================================================
    // LECTURA (ReadVecOp) 
    // =========================================================================

    
    logic [15:0] vecA_debug_mux;
    logic [15:0] vecB_debug_mux;
    
    assign vecA_debug_mux = ram_A_dout[bank_sel];
    assign vecB_debug_mux = ram_B_dout[bank_sel];

    logic readA_tx, readB_tx; 
    logic [7:0] readA_data_uart, readB_data_uart;
    logic readA_elem_done, readB_elem_done;
    
    ReadVecOp Read_Vect_A_inst(
        .clk(clk_sys), .rst(reset), .en(state == ReadVecA),
        .vec_data(vecA_debug_mux[9:0]), 
        .tx_busy(tx_busy), .tx_start(readA_tx),
        .tx_data(readA_data_uart), .element_done(readA_elem_done)
    );
    ReadVecOp Read_Vect_B_inst(
        .clk(clk_sys), .rst(reset), .en(state == ReadVecB),
        .vec_data(vecB_debug_mux[9:0]), 
        .tx_busy(tx_busy), .tx_start(readB_tx),
        .tx_data(readB_data_uart), .element_done(readB_elem_done)
    );

    // =========================================================================
    // Envio Resultado, LEDs, FSM
        // =========================================================================
    
    // Registro de Modo (6 = Dot, 7 = Euc)
    always_ff @(posedge clk_sys) begin
        if (reset) hls_mode_reg <= 0;
        else if (state == Standby && rx_ready) begin
            if (rx_data == 'd6) hls_mode_reg <= 0;      
            else if (rx_data == 'd7) hls_mode_reg <= 1; 
        end
    end

    logic sender_tx_start, sender_done;
    logic [7:0] sender_tx_data;

    Envio_32bits sender_inst (
        .clk(clk_sys), .rst(reset), .en(state == SendHLS),      
        .data_in(hls_result_raw), .tx_busy(tx_busy),          
        .tx_start(sender_tx_start), .tx_data(sender_tx_data), .done(sender_done)          
    );

    // LEDs
    assign LED[0] = (hls_mode_reg == 1'b1); 
    assign LED[1] = (hls_mode_reg == 1'b0); 

    // Display
    HexDisplay hex_disp_inst(
        .clk(clk_sys), .rst(reset), .data_in(hls_result_raw), 
        .mode_in(hls_mode_reg), .seg(SEG), .an(AN)
    );

    // FSM
    logic job_ok; 
    always_ff @(posedge clk_sys) begin
        if (reset) state <= Standby; else state <= nx_state;
    end
    
    always_comb begin
        nx_state = state;
        if (state == Standby && rx_ready) begin
            case (rx_data)
                'd1: nx_state = WriteVecA; 'd2: nx_state = WriteVecB;
                'd3: nx_state = ReadVecA;  'd4: nx_state = ReadVecB;
                'd6: nx_state = TriggerHLS; 'd7: nx_state = TriggerHLS; 
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

    // MUX Salidas UART
    always_comb begin
        job_ok = 0; addr_inc = 0; uart_tx_start_mux = 0; uart_tx_data_mux = 0;
        case (state)
            Standby: addr_inc = 0;
            WriteVecA: begin addr_inc = addr_inc_write_A; job_ok = job_ok_write_A; end
            WriteVecB: begin addr_inc = addr_inc_write_B; job_ok = job_ok_write_B; end      
            ReadVecA: begin
                uart_tx_start_mux = readA_tx; uart_tx_data_mux = readA_data_uart;
                addr_inc = readA_elem_done; job_ok = (addr_counter == N-1 && addr_inc) ? 1 : 0;
            end   
            ReadVecB: begin
                uart_tx_start_mux = readB_tx; uart_tx_data_mux = readB_data_uart;
                addr_inc = readB_elem_done; job_ok = (addr_counter == N-1 && addr_inc) ? 1 : 0;
            end   
            SendHLS: begin
                uart_tx_start_mux = sender_tx_start; uart_tx_data_mux = sender_tx_data;
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