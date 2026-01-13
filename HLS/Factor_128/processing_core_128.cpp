#include "processing_core_128.hpp"
#include <hls_math.h>
#include <ap_fixed.h>

typedef ap_fixed<32, 16> fixed32_t;

void processing_core_128(data_t vectorA[N_ELEMENTS], data_t vectorB[N_ELEMENTS], res_t &result, bool mode) {
    #pragma HLS INTERFACE ap_none port=result
    #pragma HLS INTERFACE ap_none port=mode
    #pragma HLS INTERFACE ap_ctrl_hs port=return
    
    // --- FACTOR 128 ---
    #pragma HLS ARRAY_PARTITION variable=vectorA cyclic factor=128 dim=1
    #pragma HLS ARRAY_PARTITION variable=vectorB cyclic factor=128 dim=1

    int accumulator = 0;

    loop_128: for (int i = 0; i < N_ELEMENTS; i++) {
        #pragma HLS UNROLL factor=128
        #pragma HLS PIPELINE II=1

        int valA = (int)vectorA[i];
        int valB = (int)vectorB[i];

        int term_dot = valA * valB;
        int diff = valA - valB;
        int term_euc = diff * diff;

        int term_final = (mode == 0) ? term_dot : term_euc;
        accumulator += term_final;
    }

    if (mode == 1) {
        float acc_float = (float)accumulator;
        float sqrt_val = hls::sqrt(acc_float);
        fixed32_t res_fixed = (fixed32_t)sqrt_val;
        result = res_fixed.range(31, 0); 
    } else {
        result = accumulator;
    }
}