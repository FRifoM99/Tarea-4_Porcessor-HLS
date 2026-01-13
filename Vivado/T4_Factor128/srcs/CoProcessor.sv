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
    // SETUP GENERAL
    // =========================================================================
    logic clk_sys; assign clk_sys = CLK100MHZ;
    logic reset;   assign reset   = ~CPU_RESETN;

    // FSM
    typedef enum logic [3:0] {
        Standby, WriteVecA, WriteVecB, ReadVecA, ReadVecB,
        TriggerHLS, WaitHLS, SendHLS
    } enum_state;
    enum_state state, nx_state;

    // UART
    logic [7:0] rx_data; logic [7:0] uart_tx_data_mux; 
    logic rx_ready, uart_tx_start_mux, tx_busy;
    
    uart_basic #(.CLK_FREQUENCY(CLK_FREQUENCY), .BAUD_RATE(BAUD_RATE)) uart_logic (
        .clk(clk_sys), .reset(reset), .rx(UART_TXD_IN), .tx(UART_RXD_OUT),
        .rx_data(rx_data), .tx_data(uart_tx_data_mux), .rx_ready(rx_ready), 
        .tx_start(uart_tx_start_mux), .tx_busy(tx_busy)
    );

    // =========================================================================
    // CONTROL DE MEMORIA Y ESCRITURA
    // =========================================================================
    logic [9:0] addr_counter; logic addr_inc;
    counter_with_inc #(10) master_count(.clk(clk_sys), .rst(reset || (state != nx_state)), .inc(addr_inc), .count(addr_counter));

    logic write_en_A, addr_inc_write_A, job_ok_write_A;
    logic write_en_B, addr_inc_write_B, job_ok_write_B;
    logic [15:0] bram_din_A, bram_din_B; 

    BramWriteController #(N) write_ctrl_A (.clk(clk_sys), .rst(reset), .en(state == WriteVecA), .rx_ready(rx_ready), .addr(addr_counter), .rx_data(rx_data), .write_en(write_en_A), .addr_inc(addr_inc_write_A), .bram_data_out(bram_din_A), .job_ok(job_ok_write_A));
    BramWriteController #(N) write_ctrl_B (.clk(clk_sys), .rst(reset), .en(state == WriteVecB), .rx_ready(rx_ready), .addr(addr_counter), .rx_data(rx_data), .write_en(write_en_B), .addr_inc(addr_inc_write_B), .bram_data_out(bram_din_B), .job_ok(job_ok_write_B));

    // =========================================================================
    //  MEMORIA (LUTRAM)
    // =========================================================================
    logic [6:0] bank_sel;       assign bank_sel = addr_counter[6:0];
    logic [2:0] bank_addr_uart; assign bank_addr_uart = addr_counter[9:7];

    // Arrays de conexión HLS
    logic [15:0] ram_A_dout [0:127];
    logic [15:0] ram_B_dout [0:127];
    logic [2:0]  hls_A_addr [0:127]; logic hls_A_ce [0:127];
    logic [2:0]  hls_B_addr [0:127]; logic hls_B_ce [0:127];

    logic hls_active;
    assign hls_active = (state == TriggerHLS || state == WaitHLS);

    genvar i;
    generate
        for (i = 0; i < 128; i++) begin : RAM_BANKS
            // Lógica Mux Escritura/Lectura
            logic we_bank_A; assign we_bank_A = write_en_A && (bank_sel == i);
            logic we_bank_B; assign we_bank_B = write_en_B && (bank_sel == i);
            
            // Instancias de Memoria (Distributed RAM, Depth 8)
            Inferred_BRAM_DualPort #(.DATA_WIDTH(16), .ADDR_WIDTH(3), .DEPTH(8)) RAM_A (
                .clk(clk_sys), .we_a(we_bank_A), .addr_a(bank_addr_uart), .din_a(bram_din_A),
                .en_b(hls_active ? hls_A_ce[i] : 1'b1), 
                .addr_b(hls_active ? hls_A_addr[i] : bank_addr_uart), 
                .dout_b(ram_A_dout[i])
            );

            Inferred_BRAM_DualPort #(.DATA_WIDTH(16), .ADDR_WIDTH(3), .DEPTH(8)) RAM_B (
                .clk(clk_sys), .we_a(we_bank_B), .addr_a(bank_addr_uart), .din_a(bram_din_B),
                .en_b(hls_active ? hls_B_ce[i] : 1'b1), 
                .addr_b(hls_active ? hls_B_addr[i] : bank_addr_uart), 
                .dout_b(ram_B_dout[i])
            );
        end
    endgenerate

    // =========================================================================
    //  INSTANCIA  HLS 
    // =========================================================================
    logic [31:0] hls_result_raw;
    logic hls_start, hls_done, hls_idle, hls_ready, hls_mode_reg;

    processing_core_128_0 u_hls_inst (
        .ap_clk(clk_sys),
        .ap_rst(reset),
        .ap_start(hls_start),
        .ap_done(hls_done),
        .ap_idle(hls_idle),
        .ap_ready(hls_ready),
        .result(hls_result_raw),
        .mode(hls_mode_reg),

        // --- VECTOR A (0 a 127) ---
        .vectorA_0_ce0(hls_A_ce[0]), .vectorA_0_address0(hls_A_addr[0]), .vectorA_0_q0(ram_A_dout[0]),
        .vectorA_1_ce0(hls_A_ce[1]), .vectorA_1_address0(hls_A_addr[1]), .vectorA_1_q0(ram_A_dout[1]),
        .vectorA_2_ce0(hls_A_ce[2]), .vectorA_2_address0(hls_A_addr[2]), .vectorA_2_q0(ram_A_dout[2]),
        .vectorA_3_ce0(hls_A_ce[3]), .vectorA_3_address0(hls_A_addr[3]), .vectorA_3_q0(ram_A_dout[3]),
        .vectorA_4_ce0(hls_A_ce[4]), .vectorA_4_address0(hls_A_addr[4]), .vectorA_4_q0(ram_A_dout[4]),
        .vectorA_5_ce0(hls_A_ce[5]), .vectorA_5_address0(hls_A_addr[5]), .vectorA_5_q0(ram_A_dout[5]),
        .vectorA_6_ce0(hls_A_ce[6]), .vectorA_6_address0(hls_A_addr[6]), .vectorA_6_q0(ram_A_dout[6]),
        .vectorA_7_ce0(hls_A_ce[7]), .vectorA_7_address0(hls_A_addr[7]), .vectorA_7_q0(ram_A_dout[7]),
        .vectorA_8_ce0(hls_A_ce[8]), .vectorA_8_address0(hls_A_addr[8]), .vectorA_8_q0(ram_A_dout[8]),
        .vectorA_9_ce0(hls_A_ce[9]), .vectorA_9_address0(hls_A_addr[9]), .vectorA_9_q0(ram_A_dout[9]),
        .vectorA_10_ce0(hls_A_ce[10]), .vectorA_10_address0(hls_A_addr[10]), .vectorA_10_q0(ram_A_dout[10]),
        .vectorA_11_ce0(hls_A_ce[11]), .vectorA_11_address0(hls_A_addr[11]), .vectorA_11_q0(ram_A_dout[11]),
        .vectorA_12_ce0(hls_A_ce[12]), .vectorA_12_address0(hls_A_addr[12]), .vectorA_12_q0(ram_A_dout[12]),
        .vectorA_13_ce0(hls_A_ce[13]), .vectorA_13_address0(hls_A_addr[13]), .vectorA_13_q0(ram_A_dout[13]),
        .vectorA_14_ce0(hls_A_ce[14]), .vectorA_14_address0(hls_A_addr[14]), .vectorA_14_q0(ram_A_dout[14]),
        .vectorA_15_ce0(hls_A_ce[15]), .vectorA_15_address0(hls_A_addr[15]), .vectorA_15_q0(ram_A_dout[15]),
        .vectorA_16_ce0(hls_A_ce[16]), .vectorA_16_address0(hls_A_addr[16]), .vectorA_16_q0(ram_A_dout[16]),
        .vectorA_17_ce0(hls_A_ce[17]), .vectorA_17_address0(hls_A_addr[17]), .vectorA_17_q0(ram_A_dout[17]),
        .vectorA_18_ce0(hls_A_ce[18]), .vectorA_18_address0(hls_A_addr[18]), .vectorA_18_q0(ram_A_dout[18]),
        .vectorA_19_ce0(hls_A_ce[19]), .vectorA_19_address0(hls_A_addr[19]), .vectorA_19_q0(ram_A_dout[19]),
        .vectorA_20_ce0(hls_A_ce[20]), .vectorA_20_address0(hls_A_addr[20]), .vectorA_20_q0(ram_A_dout[20]),
        .vectorA_21_ce0(hls_A_ce[21]), .vectorA_21_address0(hls_A_addr[21]), .vectorA_21_q0(ram_A_dout[21]),
        .vectorA_22_ce0(hls_A_ce[22]), .vectorA_22_address0(hls_A_addr[22]), .vectorA_22_q0(ram_A_dout[22]),
        .vectorA_23_ce0(hls_A_ce[23]), .vectorA_23_address0(hls_A_addr[23]), .vectorA_23_q0(ram_A_dout[23]),
        .vectorA_24_ce0(hls_A_ce[24]), .vectorA_24_address0(hls_A_addr[24]), .vectorA_24_q0(ram_A_dout[24]),
        .vectorA_25_ce0(hls_A_ce[25]), .vectorA_25_address0(hls_A_addr[25]), .vectorA_25_q0(ram_A_dout[25]),
        .vectorA_26_ce0(hls_A_ce[26]), .vectorA_26_address0(hls_A_addr[26]), .vectorA_26_q0(ram_A_dout[26]),
        .vectorA_27_ce0(hls_A_ce[27]), .vectorA_27_address0(hls_A_addr[27]), .vectorA_27_q0(ram_A_dout[27]),
        .vectorA_28_ce0(hls_A_ce[28]), .vectorA_28_address0(hls_A_addr[28]), .vectorA_28_q0(ram_A_dout[28]),
        .vectorA_29_ce0(hls_A_ce[29]), .vectorA_29_address0(hls_A_addr[29]), .vectorA_29_q0(ram_A_dout[29]),
        .vectorA_30_ce0(hls_A_ce[30]), .vectorA_30_address0(hls_A_addr[30]), .vectorA_30_q0(ram_A_dout[30]),
        .vectorA_31_ce0(hls_A_ce[31]), .vectorA_31_address0(hls_A_addr[31]), .vectorA_31_q0(ram_A_dout[31]),
        .vectorA_32_ce0(hls_A_ce[32]), .vectorA_32_address0(hls_A_addr[32]), .vectorA_32_q0(ram_A_dout[32]),
        .vectorA_33_ce0(hls_A_ce[33]), .vectorA_33_address0(hls_A_addr[33]), .vectorA_33_q0(ram_A_dout[33]),
        .vectorA_34_ce0(hls_A_ce[34]), .vectorA_34_address0(hls_A_addr[34]), .vectorA_34_q0(ram_A_dout[34]),
        .vectorA_35_ce0(hls_A_ce[35]), .vectorA_35_address0(hls_A_addr[35]), .vectorA_35_q0(ram_A_dout[35]),
        .vectorA_36_ce0(hls_A_ce[36]), .vectorA_36_address0(hls_A_addr[36]), .vectorA_36_q0(ram_A_dout[36]),
        .vectorA_37_ce0(hls_A_ce[37]), .vectorA_37_address0(hls_A_addr[37]), .vectorA_37_q0(ram_A_dout[37]),
        .vectorA_38_ce0(hls_A_ce[38]), .vectorA_38_address0(hls_A_addr[38]), .vectorA_38_q0(ram_A_dout[38]),
        .vectorA_39_ce0(hls_A_ce[39]), .vectorA_39_address0(hls_A_addr[39]), .vectorA_39_q0(ram_A_dout[39]),
        .vectorA_40_ce0(hls_A_ce[40]), .vectorA_40_address0(hls_A_addr[40]), .vectorA_40_q0(ram_A_dout[40]),
        .vectorA_41_ce0(hls_A_ce[41]), .vectorA_41_address0(hls_A_addr[41]), .vectorA_41_q0(ram_A_dout[41]),
        .vectorA_42_ce0(hls_A_ce[42]), .vectorA_42_address0(hls_A_addr[42]), .vectorA_42_q0(ram_A_dout[42]),
        .vectorA_43_ce0(hls_A_ce[43]), .vectorA_43_address0(hls_A_addr[43]), .vectorA_43_q0(ram_A_dout[43]),
        .vectorA_44_ce0(hls_A_ce[44]), .vectorA_44_address0(hls_A_addr[44]), .vectorA_44_q0(ram_A_dout[44]),
        .vectorA_45_ce0(hls_A_ce[45]), .vectorA_45_address0(hls_A_addr[45]), .vectorA_45_q0(ram_A_dout[45]),
        .vectorA_46_ce0(hls_A_ce[46]), .vectorA_46_address0(hls_A_addr[46]), .vectorA_46_q0(ram_A_dout[46]),
        .vectorA_47_ce0(hls_A_ce[47]), .vectorA_47_address0(hls_A_addr[47]), .vectorA_47_q0(ram_A_dout[47]),
        .vectorA_48_ce0(hls_A_ce[48]), .vectorA_48_address0(hls_A_addr[48]), .vectorA_48_q0(ram_A_dout[48]),
        .vectorA_49_ce0(hls_A_ce[49]), .vectorA_49_address0(hls_A_addr[49]), .vectorA_49_q0(ram_A_dout[49]),
        .vectorA_50_ce0(hls_A_ce[50]), .vectorA_50_address0(hls_A_addr[50]), .vectorA_50_q0(ram_A_dout[50]),
        .vectorA_51_ce0(hls_A_ce[51]), .vectorA_51_address0(hls_A_addr[51]), .vectorA_51_q0(ram_A_dout[51]),
        .vectorA_52_ce0(hls_A_ce[52]), .vectorA_52_address0(hls_A_addr[52]), .vectorA_52_q0(ram_A_dout[52]),
        .vectorA_53_ce0(hls_A_ce[53]), .vectorA_53_address0(hls_A_addr[53]), .vectorA_53_q0(ram_A_dout[53]),
        .vectorA_54_ce0(hls_A_ce[54]), .vectorA_54_address0(hls_A_addr[54]), .vectorA_54_q0(ram_A_dout[54]),
        .vectorA_55_ce0(hls_A_ce[55]), .vectorA_55_address0(hls_A_addr[55]), .vectorA_55_q0(ram_A_dout[55]),
        .vectorA_56_ce0(hls_A_ce[56]), .vectorA_56_address0(hls_A_addr[56]), .vectorA_56_q0(ram_A_dout[56]),
        .vectorA_57_ce0(hls_A_ce[57]), .vectorA_57_address0(hls_A_addr[57]), .vectorA_57_q0(ram_A_dout[57]),
        .vectorA_58_ce0(hls_A_ce[58]), .vectorA_58_address0(hls_A_addr[58]), .vectorA_58_q0(ram_A_dout[58]),
        .vectorA_59_ce0(hls_A_ce[59]), .vectorA_59_address0(hls_A_addr[59]), .vectorA_59_q0(ram_A_dout[59]),
        .vectorA_60_ce0(hls_A_ce[60]), .vectorA_60_address0(hls_A_addr[60]), .vectorA_60_q0(ram_A_dout[60]),
        .vectorA_61_ce0(hls_A_ce[61]), .vectorA_61_address0(hls_A_addr[61]), .vectorA_61_q0(ram_A_dout[61]),
        .vectorA_62_ce0(hls_A_ce[62]), .vectorA_62_address0(hls_A_addr[62]), .vectorA_62_q0(ram_A_dout[62]),
        .vectorA_63_ce0(hls_A_ce[63]), .vectorA_63_address0(hls_A_addr[63]), .vectorA_63_q0(ram_A_dout[63]),
        .vectorA_64_ce0(hls_A_ce[64]), .vectorA_64_address0(hls_A_addr[64]), .vectorA_64_q0(ram_A_dout[64]),
        .vectorA_65_ce0(hls_A_ce[65]), .vectorA_65_address0(hls_A_addr[65]), .vectorA_65_q0(ram_A_dout[65]),
        .vectorA_66_ce0(hls_A_ce[66]), .vectorA_66_address0(hls_A_addr[66]), .vectorA_66_q0(ram_A_dout[66]),
        .vectorA_67_ce0(hls_A_ce[67]), .vectorA_67_address0(hls_A_addr[67]), .vectorA_67_q0(ram_A_dout[67]),
        .vectorA_68_ce0(hls_A_ce[68]), .vectorA_68_address0(hls_A_addr[68]), .vectorA_68_q0(ram_A_dout[68]),
        .vectorA_69_ce0(hls_A_ce[69]), .vectorA_69_address0(hls_A_addr[69]), .vectorA_69_q0(ram_A_dout[69]),
        .vectorA_70_ce0(hls_A_ce[70]), .vectorA_70_address0(hls_A_addr[70]), .vectorA_70_q0(ram_A_dout[70]),
        .vectorA_71_ce0(hls_A_ce[71]), .vectorA_71_address0(hls_A_addr[71]), .vectorA_71_q0(ram_A_dout[71]),
        .vectorA_72_ce0(hls_A_ce[72]), .vectorA_72_address0(hls_A_addr[72]), .vectorA_72_q0(ram_A_dout[72]),
        .vectorA_73_ce0(hls_A_ce[73]), .vectorA_73_address0(hls_A_addr[73]), .vectorA_73_q0(ram_A_dout[73]),
        .vectorA_74_ce0(hls_A_ce[74]), .vectorA_74_address0(hls_A_addr[74]), .vectorA_74_q0(ram_A_dout[74]),
        .vectorA_75_ce0(hls_A_ce[75]), .vectorA_75_address0(hls_A_addr[75]), .vectorA_75_q0(ram_A_dout[75]),
        .vectorA_76_ce0(hls_A_ce[76]), .vectorA_76_address0(hls_A_addr[76]), .vectorA_76_q0(ram_A_dout[76]),
        .vectorA_77_ce0(hls_A_ce[77]), .vectorA_77_address0(hls_A_addr[77]), .vectorA_77_q0(ram_A_dout[77]),
        .vectorA_78_ce0(hls_A_ce[78]), .vectorA_78_address0(hls_A_addr[78]), .vectorA_78_q0(ram_A_dout[78]),
        .vectorA_79_ce0(hls_A_ce[79]), .vectorA_79_address0(hls_A_addr[79]), .vectorA_79_q0(ram_A_dout[79]),
        .vectorA_80_ce0(hls_A_ce[80]), .vectorA_80_address0(hls_A_addr[80]), .vectorA_80_q0(ram_A_dout[80]),
        .vectorA_81_ce0(hls_A_ce[81]), .vectorA_81_address0(hls_A_addr[81]), .vectorA_81_q0(ram_A_dout[81]),
        .vectorA_82_ce0(hls_A_ce[82]), .vectorA_82_address0(hls_A_addr[82]), .vectorA_82_q0(ram_A_dout[82]),
        .vectorA_83_ce0(hls_A_ce[83]), .vectorA_83_address0(hls_A_addr[83]), .vectorA_83_q0(ram_A_dout[83]),
        .vectorA_84_ce0(hls_A_ce[84]), .vectorA_84_address0(hls_A_addr[84]), .vectorA_84_q0(ram_A_dout[84]),
        .vectorA_85_ce0(hls_A_ce[85]), .vectorA_85_address0(hls_A_addr[85]), .vectorA_85_q0(ram_A_dout[85]),
        .vectorA_86_ce0(hls_A_ce[86]), .vectorA_86_address0(hls_A_addr[86]), .vectorA_86_q0(ram_A_dout[86]),
        .vectorA_87_ce0(hls_A_ce[87]), .vectorA_87_address0(hls_A_addr[87]), .vectorA_87_q0(ram_A_dout[87]),
        .vectorA_88_ce0(hls_A_ce[88]), .vectorA_88_address0(hls_A_addr[88]), .vectorA_88_q0(ram_A_dout[88]),
        .vectorA_89_ce0(hls_A_ce[89]), .vectorA_89_address0(hls_A_addr[89]), .vectorA_89_q0(ram_A_dout[89]),
        .vectorA_90_ce0(hls_A_ce[90]), .vectorA_90_address0(hls_A_addr[90]), .vectorA_90_q0(ram_A_dout[90]),
        .vectorA_91_ce0(hls_A_ce[91]), .vectorA_91_address0(hls_A_addr[91]), .vectorA_91_q0(ram_A_dout[91]),
        .vectorA_92_ce0(hls_A_ce[92]), .vectorA_92_address0(hls_A_addr[92]), .vectorA_92_q0(ram_A_dout[92]),
        .vectorA_93_ce0(hls_A_ce[93]), .vectorA_93_address0(hls_A_addr[93]), .vectorA_93_q0(ram_A_dout[93]),
        .vectorA_94_ce0(hls_A_ce[94]), .vectorA_94_address0(hls_A_addr[94]), .vectorA_94_q0(ram_A_dout[94]),
        .vectorA_95_ce0(hls_A_ce[95]), .vectorA_95_address0(hls_A_addr[95]), .vectorA_95_q0(ram_A_dout[95]),
        .vectorA_96_ce0(hls_A_ce[96]), .vectorA_96_address0(hls_A_addr[96]), .vectorA_96_q0(ram_A_dout[96]),
        .vectorA_97_ce0(hls_A_ce[97]), .vectorA_97_address0(hls_A_addr[97]), .vectorA_97_q0(ram_A_dout[97]),
        .vectorA_98_ce0(hls_A_ce[98]), .vectorA_98_address0(hls_A_addr[98]), .vectorA_98_q0(ram_A_dout[98]),
        .vectorA_99_ce0(hls_A_ce[99]), .vectorA_99_address0(hls_A_addr[99]), .vectorA_99_q0(ram_A_dout[99]),
        .vectorA_100_ce0(hls_A_ce[100]), .vectorA_100_address0(hls_A_addr[100]), .vectorA_100_q0(ram_A_dout[100]),
        .vectorA_101_ce0(hls_A_ce[101]), .vectorA_101_address0(hls_A_addr[101]), .vectorA_101_q0(ram_A_dout[101]),
        .vectorA_102_ce0(hls_A_ce[102]), .vectorA_102_address0(hls_A_addr[102]), .vectorA_102_q0(ram_A_dout[102]),
        .vectorA_103_ce0(hls_A_ce[103]), .vectorA_103_address0(hls_A_addr[103]), .vectorA_103_q0(ram_A_dout[103]),
        .vectorA_104_ce0(hls_A_ce[104]), .vectorA_104_address0(hls_A_addr[104]), .vectorA_104_q0(ram_A_dout[104]),
        .vectorA_105_ce0(hls_A_ce[105]), .vectorA_105_address0(hls_A_addr[105]), .vectorA_105_q0(ram_A_dout[105]),
        .vectorA_106_ce0(hls_A_ce[106]), .vectorA_106_address0(hls_A_addr[106]), .vectorA_106_q0(ram_A_dout[106]),
        .vectorA_107_ce0(hls_A_ce[107]), .vectorA_107_address0(hls_A_addr[107]), .vectorA_107_q0(ram_A_dout[107]),
        .vectorA_108_ce0(hls_A_ce[108]), .vectorA_108_address0(hls_A_addr[108]), .vectorA_108_q0(ram_A_dout[108]),
        .vectorA_109_ce0(hls_A_ce[109]), .vectorA_109_address0(hls_A_addr[109]), .vectorA_109_q0(ram_A_dout[109]),
        .vectorA_110_ce0(hls_A_ce[110]), .vectorA_110_address0(hls_A_addr[110]), .vectorA_110_q0(ram_A_dout[110]),
        .vectorA_111_ce0(hls_A_ce[111]), .vectorA_111_address0(hls_A_addr[111]), .vectorA_111_q0(ram_A_dout[111]),
        .vectorA_112_ce0(hls_A_ce[112]), .vectorA_112_address0(hls_A_addr[112]), .vectorA_112_q0(ram_A_dout[112]),
        .vectorA_113_ce0(hls_A_ce[113]), .vectorA_113_address0(hls_A_addr[113]), .vectorA_113_q0(ram_A_dout[113]),
        .vectorA_114_ce0(hls_A_ce[114]), .vectorA_114_address0(hls_A_addr[114]), .vectorA_114_q0(ram_A_dout[114]),
        .vectorA_115_ce0(hls_A_ce[115]), .vectorA_115_address0(hls_A_addr[115]), .vectorA_115_q0(ram_A_dout[115]),
        .vectorA_116_ce0(hls_A_ce[116]), .vectorA_116_address0(hls_A_addr[116]), .vectorA_116_q0(ram_A_dout[116]),
        .vectorA_117_ce0(hls_A_ce[117]), .vectorA_117_address0(hls_A_addr[117]), .vectorA_117_q0(ram_A_dout[117]),
        .vectorA_118_ce0(hls_A_ce[118]), .vectorA_118_address0(hls_A_addr[118]), .vectorA_118_q0(ram_A_dout[118]),
        .vectorA_119_ce0(hls_A_ce[119]), .vectorA_119_address0(hls_A_addr[119]), .vectorA_119_q0(ram_A_dout[119]),
        .vectorA_120_ce0(hls_A_ce[120]), .vectorA_120_address0(hls_A_addr[120]), .vectorA_120_q0(ram_A_dout[120]),
        .vectorA_121_ce0(hls_A_ce[121]), .vectorA_121_address0(hls_A_addr[121]), .vectorA_121_q0(ram_A_dout[121]),
        .vectorA_122_ce0(hls_A_ce[122]), .vectorA_122_address0(hls_A_addr[122]), .vectorA_122_q0(ram_A_dout[122]),
        .vectorA_123_ce0(hls_A_ce[123]), .vectorA_123_address0(hls_A_addr[123]), .vectorA_123_q0(ram_A_dout[123]),
        .vectorA_124_ce0(hls_A_ce[124]), .vectorA_124_address0(hls_A_addr[124]), .vectorA_124_q0(ram_A_dout[124]),
        .vectorA_125_ce0(hls_A_ce[125]), .vectorA_125_address0(hls_A_addr[125]), .vectorA_125_q0(ram_A_dout[125]),
        .vectorA_126_ce0(hls_A_ce[126]), .vectorA_126_address0(hls_A_addr[126]), .vectorA_126_q0(ram_A_dout[126]),
        .vectorA_127_ce0(hls_A_ce[127]), .vectorA_127_address0(hls_A_addr[127]), .vectorA_127_q0(ram_A_dout[127]),

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
        .vectorB_15_ce0(hls_B_ce[15]), .vectorB_15_address0(hls_B_addr[15]), .vectorB_15_q0(ram_B_dout[15]),
        .vectorB_16_ce0(hls_B_ce[16]), .vectorB_16_address0(hls_B_addr[16]), .vectorB_16_q0(ram_B_dout[16]),
        .vectorB_17_ce0(hls_B_ce[17]), .vectorB_17_address0(hls_B_addr[17]), .vectorB_17_q0(ram_B_dout[17]),
        .vectorB_18_ce0(hls_B_ce[18]), .vectorB_18_address0(hls_B_addr[18]), .vectorB_18_q0(ram_B_dout[18]),
        .vectorB_19_ce0(hls_B_ce[19]), .vectorB_19_address0(hls_B_addr[19]), .vectorB_19_q0(ram_B_dout[19]),
        .vectorB_20_ce0(hls_B_ce[20]), .vectorB_20_address0(hls_B_addr[20]), .vectorB_20_q0(ram_B_dout[20]),
        .vectorB_21_ce0(hls_B_ce[21]), .vectorB_21_address0(hls_B_addr[21]), .vectorB_21_q0(ram_B_dout[21]),
        .vectorB_22_ce0(hls_B_ce[22]), .vectorB_22_address0(hls_B_addr[22]), .vectorB_22_q0(ram_B_dout[22]),
        .vectorB_23_ce0(hls_B_ce[23]), .vectorB_23_address0(hls_B_addr[23]), .vectorB_23_q0(ram_B_dout[23]),
        .vectorB_24_ce0(hls_B_ce[24]), .vectorB_24_address0(hls_B_addr[24]), .vectorB_24_q0(ram_B_dout[24]),
        .vectorB_25_ce0(hls_B_ce[25]), .vectorB_25_address0(hls_B_addr[25]), .vectorB_25_q0(ram_B_dout[25]),
        .vectorB_26_ce0(hls_B_ce[26]), .vectorB_26_address0(hls_B_addr[26]), .vectorB_26_q0(ram_B_dout[26]),
        .vectorB_27_ce0(hls_B_ce[27]), .vectorB_27_address0(hls_B_addr[27]), .vectorB_27_q0(ram_B_dout[27]),
        .vectorB_28_ce0(hls_B_ce[28]), .vectorB_28_address0(hls_B_addr[28]), .vectorB_28_q0(ram_B_dout[28]),
        .vectorB_29_ce0(hls_B_ce[29]), .vectorB_29_address0(hls_B_addr[29]), .vectorB_29_q0(ram_B_dout[29]),
        .vectorB_30_ce0(hls_B_ce[30]), .vectorB_30_address0(hls_B_addr[30]), .vectorB_30_q0(ram_B_dout[30]),
        .vectorB_31_ce0(hls_B_ce[31]), .vectorB_31_address0(hls_B_addr[31]), .vectorB_31_q0(ram_B_dout[31]),
        .vectorB_32_ce0(hls_B_ce[32]), .vectorB_32_address0(hls_B_addr[32]), .vectorB_32_q0(ram_B_dout[32]),
        .vectorB_33_ce0(hls_B_ce[33]), .vectorB_33_address0(hls_B_addr[33]), .vectorB_33_q0(ram_B_dout[33]),
        .vectorB_34_ce0(hls_B_ce[34]), .vectorB_34_address0(hls_B_addr[34]), .vectorB_34_q0(ram_B_dout[34]),
        .vectorB_35_ce0(hls_B_ce[35]), .vectorB_35_address0(hls_B_addr[35]), .vectorB_35_q0(ram_B_dout[35]),
        .vectorB_36_ce0(hls_B_ce[36]), .vectorB_36_address0(hls_B_addr[36]), .vectorB_36_q0(ram_B_dout[36]),
        .vectorB_37_ce0(hls_B_ce[37]), .vectorB_37_address0(hls_B_addr[37]), .vectorB_37_q0(ram_B_dout[37]),
        .vectorB_38_ce0(hls_B_ce[38]), .vectorB_38_address0(hls_B_addr[38]), .vectorB_38_q0(ram_B_dout[38]),
        .vectorB_39_ce0(hls_B_ce[39]), .vectorB_39_address0(hls_B_addr[39]), .vectorB_39_q0(ram_B_dout[39]),
        .vectorB_40_ce0(hls_B_ce[40]), .vectorB_40_address0(hls_B_addr[40]), .vectorB_40_q0(ram_B_dout[40]),
        .vectorB_41_ce0(hls_B_ce[41]), .vectorB_41_address0(hls_B_addr[41]), .vectorB_41_q0(ram_B_dout[41]),
        .vectorB_42_ce0(hls_B_ce[42]), .vectorB_42_address0(hls_B_addr[42]), .vectorB_42_q0(ram_B_dout[42]),
        .vectorB_43_ce0(hls_B_ce[43]), .vectorB_43_address0(hls_B_addr[43]), .vectorB_43_q0(ram_B_dout[43]),
        .vectorB_44_ce0(hls_B_ce[44]), .vectorB_44_address0(hls_B_addr[44]), .vectorB_44_q0(ram_B_dout[44]),
        .vectorB_45_ce0(hls_B_ce[45]), .vectorB_45_address0(hls_B_addr[45]), .vectorB_45_q0(ram_B_dout[45]),
        .vectorB_46_ce0(hls_B_ce[46]), .vectorB_46_address0(hls_B_addr[46]), .vectorB_46_q0(ram_B_dout[46]),
        .vectorB_47_ce0(hls_B_ce[47]), .vectorB_47_address0(hls_B_addr[47]), .vectorB_47_q0(ram_B_dout[47]),
        .vectorB_48_ce0(hls_B_ce[48]), .vectorB_48_address0(hls_B_addr[48]), .vectorB_48_q0(ram_B_dout[48]),
        .vectorB_49_ce0(hls_B_ce[49]), .vectorB_49_address0(hls_B_addr[49]), .vectorB_49_q0(ram_B_dout[49]),
        .vectorB_50_ce0(hls_B_ce[50]), .vectorB_50_address0(hls_B_addr[50]), .vectorB_50_q0(ram_B_dout[50]),
        .vectorB_51_ce0(hls_B_ce[51]), .vectorB_51_address0(hls_B_addr[51]), .vectorB_51_q0(ram_B_dout[51]),
        .vectorB_52_ce0(hls_B_ce[52]), .vectorB_52_address0(hls_B_addr[52]), .vectorB_52_q0(ram_B_dout[52]),
        .vectorB_53_ce0(hls_B_ce[53]), .vectorB_53_address0(hls_B_addr[53]), .vectorB_53_q0(ram_B_dout[53]),
        .vectorB_54_ce0(hls_B_ce[54]), .vectorB_54_address0(hls_B_addr[54]), .vectorB_54_q0(ram_B_dout[54]),
        .vectorB_55_ce0(hls_B_ce[55]), .vectorB_55_address0(hls_B_addr[55]), .vectorB_55_q0(ram_B_dout[55]),
        .vectorB_56_ce0(hls_B_ce[56]), .vectorB_56_address0(hls_B_addr[56]), .vectorB_56_q0(ram_B_dout[56]),
        .vectorB_57_ce0(hls_B_ce[57]), .vectorB_57_address0(hls_B_addr[57]), .vectorB_57_q0(ram_B_dout[57]),
        .vectorB_58_ce0(hls_B_ce[58]), .vectorB_58_address0(hls_B_addr[58]), .vectorB_58_q0(ram_B_dout[58]),
        .vectorB_59_ce0(hls_B_ce[59]), .vectorB_59_address0(hls_B_addr[59]), .vectorB_59_q0(ram_B_dout[59]),
        .vectorB_60_ce0(hls_B_ce[60]), .vectorB_60_address0(hls_B_addr[60]), .vectorB_60_q0(ram_B_dout[60]),
        .vectorB_61_ce0(hls_B_ce[61]), .vectorB_61_address0(hls_B_addr[61]), .vectorB_61_q0(ram_B_dout[61]),
        .vectorB_62_ce0(hls_B_ce[62]), .vectorB_62_address0(hls_B_addr[62]), .vectorB_62_q0(ram_B_dout[62]),
        .vectorB_63_ce0(hls_B_ce[63]), .vectorB_63_address0(hls_B_addr[63]), .vectorB_63_q0(ram_B_dout[63]),
        .vectorB_64_ce0(hls_B_ce[64]), .vectorB_64_address0(hls_B_addr[64]), .vectorB_64_q0(ram_B_dout[64]),
        .vectorB_65_ce0(hls_B_ce[65]), .vectorB_65_address0(hls_B_addr[65]), .vectorB_65_q0(ram_B_dout[65]),
        .vectorB_66_ce0(hls_B_ce[66]), .vectorB_66_address0(hls_B_addr[66]), .vectorB_66_q0(ram_B_dout[66]),
        .vectorB_67_ce0(hls_B_ce[67]), .vectorB_67_address0(hls_B_addr[67]), .vectorB_67_q0(ram_B_dout[67]),
        .vectorB_68_ce0(hls_B_ce[68]), .vectorB_68_address0(hls_B_addr[68]), .vectorB_68_q0(ram_B_dout[68]),
        .vectorB_69_ce0(hls_B_ce[69]), .vectorB_69_address0(hls_B_addr[69]), .vectorB_69_q0(ram_B_dout[69]),
        .vectorB_70_ce0(hls_B_ce[70]), .vectorB_70_address0(hls_B_addr[70]), .vectorB_70_q0(ram_B_dout[70]),
        .vectorB_71_ce0(hls_B_ce[71]), .vectorB_71_address0(hls_B_addr[71]), .vectorB_71_q0(ram_B_dout[71]),
        .vectorB_72_ce0(hls_B_ce[72]), .vectorB_72_address0(hls_B_addr[72]), .vectorB_72_q0(ram_B_dout[72]),
        .vectorB_73_ce0(hls_B_ce[73]), .vectorB_73_address0(hls_B_addr[73]), .vectorB_73_q0(ram_B_dout[73]),
        .vectorB_74_ce0(hls_B_ce[74]), .vectorB_74_address0(hls_B_addr[74]), .vectorB_74_q0(ram_B_dout[74]),
        .vectorB_75_ce0(hls_B_ce[75]), .vectorB_75_address0(hls_B_addr[75]), .vectorB_75_q0(ram_B_dout[75]),
        .vectorB_76_ce0(hls_B_ce[76]), .vectorB_76_address0(hls_B_addr[76]), .vectorB_76_q0(ram_B_dout[76]),
        .vectorB_77_ce0(hls_B_ce[77]), .vectorB_77_address0(hls_B_addr[77]), .vectorB_77_q0(ram_B_dout[77]),
        .vectorB_78_ce0(hls_B_ce[78]), .vectorB_78_address0(hls_B_addr[78]), .vectorB_78_q0(ram_B_dout[78]),
        .vectorB_79_ce0(hls_B_ce[79]), .vectorB_79_address0(hls_B_addr[79]), .vectorB_79_q0(ram_B_dout[79]),
        .vectorB_80_ce0(hls_B_ce[80]), .vectorB_80_address0(hls_B_addr[80]), .vectorB_80_q0(ram_B_dout[80]),
        .vectorB_81_ce0(hls_B_ce[81]), .vectorB_81_address0(hls_B_addr[81]), .vectorB_81_q0(ram_B_dout[81]),
        .vectorB_82_ce0(hls_B_ce[82]), .vectorB_82_address0(hls_B_addr[82]), .vectorB_82_q0(ram_B_dout[82]),
        .vectorB_83_ce0(hls_B_ce[83]), .vectorB_83_address0(hls_B_addr[83]), .vectorB_83_q0(ram_B_dout[83]),
        .vectorB_84_ce0(hls_B_ce[84]), .vectorB_84_address0(hls_B_addr[84]), .vectorB_84_q0(ram_B_dout[84]),
        .vectorB_85_ce0(hls_B_ce[85]), .vectorB_85_address0(hls_B_addr[85]), .vectorB_85_q0(ram_B_dout[85]),
        .vectorB_86_ce0(hls_B_ce[86]), .vectorB_86_address0(hls_B_addr[86]), .vectorB_86_q0(ram_B_dout[86]),
        .vectorB_87_ce0(hls_B_ce[87]), .vectorB_87_address0(hls_B_addr[87]), .vectorB_87_q0(ram_B_dout[87]),
        .vectorB_88_ce0(hls_B_ce[88]), .vectorB_88_address0(hls_B_addr[88]), .vectorB_88_q0(ram_B_dout[88]),
        .vectorB_89_ce0(hls_B_ce[89]), .vectorB_89_address0(hls_B_addr[89]), .vectorB_89_q0(ram_B_dout[89]),
        .vectorB_90_ce0(hls_B_ce[90]), .vectorB_90_address0(hls_B_addr[90]), .vectorB_90_q0(ram_B_dout[90]),
        .vectorB_91_ce0(hls_B_ce[91]), .vectorB_91_address0(hls_B_addr[91]), .vectorB_91_q0(ram_B_dout[91]),
        .vectorB_92_ce0(hls_B_ce[92]), .vectorB_92_address0(hls_B_addr[92]), .vectorB_92_q0(ram_B_dout[92]),
        .vectorB_93_ce0(hls_B_ce[93]), .vectorB_93_address0(hls_B_addr[93]), .vectorB_93_q0(ram_B_dout[93]),
        .vectorB_94_ce0(hls_B_ce[94]), .vectorB_94_address0(hls_B_addr[94]), .vectorB_94_q0(ram_B_dout[94]),
        .vectorB_95_ce0(hls_B_ce[95]), .vectorB_95_address0(hls_B_addr[95]), .vectorB_95_q0(ram_B_dout[95]),
        .vectorB_96_ce0(hls_B_ce[96]), .vectorB_96_address0(hls_B_addr[96]), .vectorB_96_q0(ram_B_dout[96]),
        .vectorB_97_ce0(hls_B_ce[97]), .vectorB_97_address0(hls_B_addr[97]), .vectorB_97_q0(ram_B_dout[97]),
        .vectorB_98_ce0(hls_B_ce[98]), .vectorB_98_address0(hls_B_addr[98]), .vectorB_98_q0(ram_B_dout[98]),
        .vectorB_99_ce0(hls_B_ce[99]), .vectorB_99_address0(hls_B_addr[99]), .vectorB_99_q0(ram_B_dout[99]),
        .vectorB_100_ce0(hls_B_ce[100]), .vectorB_100_address0(hls_B_addr[100]), .vectorB_100_q0(ram_B_dout[100]),
        .vectorB_101_ce0(hls_B_ce[101]), .vectorB_101_address0(hls_B_addr[101]), .vectorB_101_q0(ram_B_dout[101]),
        .vectorB_102_ce0(hls_B_ce[102]), .vectorB_102_address0(hls_B_addr[102]), .vectorB_102_q0(ram_B_dout[102]),
        .vectorB_103_ce0(hls_B_ce[103]), .vectorB_103_address0(hls_B_addr[103]), .vectorB_103_q0(ram_B_dout[103]),
        .vectorB_104_ce0(hls_B_ce[104]), .vectorB_104_address0(hls_B_addr[104]), .vectorB_104_q0(ram_B_dout[104]),
        .vectorB_105_ce0(hls_B_ce[105]), .vectorB_105_address0(hls_B_addr[105]), .vectorB_105_q0(ram_B_dout[105]),
        .vectorB_106_ce0(hls_B_ce[106]), .vectorB_106_address0(hls_B_addr[106]), .vectorB_106_q0(ram_B_dout[106]),
        .vectorB_107_ce0(hls_B_ce[107]), .vectorB_107_address0(hls_B_addr[107]), .vectorB_107_q0(ram_B_dout[107]),
        .vectorB_108_ce0(hls_B_ce[108]), .vectorB_108_address0(hls_B_addr[108]), .vectorB_108_q0(ram_B_dout[108]),
        .vectorB_109_ce0(hls_B_ce[109]), .vectorB_109_address0(hls_B_addr[109]), .vectorB_109_q0(ram_B_dout[109]),
        .vectorB_110_ce0(hls_B_ce[110]), .vectorB_110_address0(hls_B_addr[110]), .vectorB_110_q0(ram_B_dout[110]),
        .vectorB_111_ce0(hls_B_ce[111]), .vectorB_111_address0(hls_B_addr[111]), .vectorB_111_q0(ram_B_dout[111]),
        .vectorB_112_ce0(hls_B_ce[112]), .vectorB_112_address0(hls_B_addr[112]), .vectorB_112_q0(ram_B_dout[112]),
        .vectorB_113_ce0(hls_B_ce[113]), .vectorB_113_address0(hls_B_addr[113]), .vectorB_113_q0(ram_B_dout[113]),
        .vectorB_114_ce0(hls_B_ce[114]), .vectorB_114_address0(hls_B_addr[114]), .vectorB_114_q0(ram_B_dout[114]),
        .vectorB_115_ce0(hls_B_ce[115]), .vectorB_115_address0(hls_B_addr[115]), .vectorB_115_q0(ram_B_dout[115]),
        .vectorB_116_ce0(hls_B_ce[116]), .vectorB_116_address0(hls_B_addr[116]), .vectorB_116_q0(ram_B_dout[116]),
        .vectorB_117_ce0(hls_B_ce[117]), .vectorB_117_address0(hls_B_addr[117]), .vectorB_117_q0(ram_B_dout[117]),
        .vectorB_118_ce0(hls_B_ce[118]), .vectorB_118_address0(hls_B_addr[118]), .vectorB_118_q0(ram_B_dout[118]),
        .vectorB_119_ce0(hls_B_ce[119]), .vectorB_119_address0(hls_B_addr[119]), .vectorB_119_q0(ram_B_dout[119]),
        .vectorB_120_ce0(hls_B_ce[120]), .vectorB_120_address0(hls_B_addr[120]), .vectorB_120_q0(ram_B_dout[120]),
        .vectorB_121_ce0(hls_B_ce[121]), .vectorB_121_address0(hls_B_addr[121]), .vectorB_121_q0(ram_B_dout[121]),
        .vectorB_122_ce0(hls_B_ce[122]), .vectorB_122_address0(hls_B_addr[122]), .vectorB_122_q0(ram_B_dout[122]),
        .vectorB_123_ce0(hls_B_ce[123]), .vectorB_123_address0(hls_B_addr[123]), .vectorB_123_q0(ram_B_dout[123]),
        .vectorB_124_ce0(hls_B_ce[124]), .vectorB_124_address0(hls_B_addr[124]), .vectorB_124_q0(ram_B_dout[124]),
        .vectorB_125_ce0(hls_B_ce[125]), .vectorB_125_address0(hls_B_addr[125]), .vectorB_125_q0(ram_B_dout[125]),
        .vectorB_126_ce0(hls_B_ce[126]), .vectorB_126_address0(hls_B_addr[126]), .vectorB_126_q0(ram_B_dout[126]),
        .vectorB_127_ce0(hls_B_ce[127]), .vectorB_127_address0(hls_B_addr[127]), .vectorB_127_q0(ram_B_dout[127])
    );
    
    assign hls_start = (state == TriggerHLS);

    // =========================================================================
    // LECTURA DEBUG (Mux Masivo 128-a-1)
    // =========================================================================
    logic [15:0] vecA_debug_mux, vecB_debug_mux;
    
    assign vecA_debug_mux = ram_A_dout[bank_sel];
    assign vecB_debug_mux = ram_B_dout[bank_sel];

    logic readA_tx, readB_tx, readA_elem_done, readB_elem_done;
    logic [7:0] readA_data_uart, readB_data_uart;

    ReadVecOp Read_Vect_A_inst(.clk(clk_sys), .rst(reset), .en(state == ReadVecA), .vec_data(vecA_debug_mux[9:0]), .tx_busy(tx_busy), .tx_start(readA_tx), .tx_data(readA_data_uart), .element_done(readA_elem_done));
    ReadVecOp Read_Vect_B_inst(.clk(clk_sys), .rst(reset), .en(state == ReadVecB), .vec_data(vecB_debug_mux[9:0]), .tx_busy(tx_busy), .tx_start(readB_tx), .tx_data(readB_data_uart), .element_done(readB_elem_done));

    // =========================================================================
    //  SALIDAS
    // =========================================================================
    always_ff @(posedge clk_sys) begin
        if (reset) hls_mode_reg <= 0;
        else if (state == Standby && rx_ready) begin
            if (rx_data == 'd6) hls_mode_reg <= 0;      
            else if (rx_data == 'd7) hls_mode_reg <= 1; 
        end
    end
    
    logic sender_tx_start, sender_done; logic [7:0] sender_tx_data;
    Envio_32bits sender_inst (.clk(clk_sys), .rst(reset), .en(state == SendHLS), .data_in(hls_result_raw), .tx_busy(tx_busy), .tx_start(sender_tx_start), .tx_data(sender_tx_data), .done(sender_done));

    assign LED[0] = (hls_mode_reg == 1'b1); 
    assign LED[1] = (hls_mode_reg == 1'b0); 
    HexDisplay hex_disp_inst(.clk(clk_sys), .rst(reset), .data_in(hls_result_raw), .mode_in(hls_mode_reg), .seg(SEG), .an(AN));

    // FSM Update Logic
    logic job_ok; 
    always_ff @(posedge clk_sys) begin if (reset) state <= Standby; else state <= nx_state; end
    always_comb begin
        nx_state = state;
        if (state == Standby && rx_ready) begin
            case (rx_data) 'd1: nx_state = WriteVecA; 'd2: nx_state = WriteVecB; 'd3: nx_state = ReadVecA; 'd4: nx_state = ReadVecB; 'd6: nx_state = TriggerHLS; 'd7: nx_state = TriggerHLS; default: nx_state = Standby; endcase
        end else begin
            case (state)
                WriteVecA: if (job_ok) nx_state = Standby; WriteVecB: if (job_ok) nx_state = Standby;
                ReadVecA:  if (job_ok) nx_state = Standby; ReadVecB:  if (job_ok) nx_state = Standby;
                TriggerHLS: nx_state = WaitHLS; WaitHLS: if (hls_done) nx_state = SendHLS; SendHLS: if (sender_done) nx_state = Standby;
                default: nx_state = Standby;
            endcase
        end
    end
    // Mux Outputs
    always_comb begin
        job_ok = 0; addr_inc = 0; uart_tx_start_mux = 0; uart_tx_data_mux = 0;
        case (state)
            Standby: addr_inc = 0;
            WriteVecA: begin addr_inc = addr_inc_write_A; job_ok = job_ok_write_A; end
            WriteVecB: begin addr_inc = addr_inc_write_B; job_ok = job_ok_write_B; end      
            ReadVecA: begin uart_tx_start_mux = readA_tx; uart_tx_data_mux = readA_data_uart; addr_inc = readA_elem_done; job_ok = (addr_counter == N-1 && addr_inc) ? 1 : 0; end   
            ReadVecB: begin uart_tx_start_mux = readB_tx; uart_tx_data_mux = readB_data_uart; addr_inc = readB_elem_done; job_ok = (addr_counter == N-1 && addr_inc) ? 1 : 0; end   
            SendHLS: begin uart_tx_start_mux = sender_tx_start; uart_tx_data_mux = sender_tx_data; end
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