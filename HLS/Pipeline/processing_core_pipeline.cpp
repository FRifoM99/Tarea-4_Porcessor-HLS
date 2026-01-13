#include "processing_core_pipeline.hpp"
#include <hls_math.h>
#include <ap_fixed.h>

typedef ap_fixed<32, 16> fixed32_t;

void processing_core_pipeline(volatile data_t vectorA[N_ELEMENTS], volatile data_t vectorB[N_ELEMENTS], res_t &result, bool mode) {
    #pragma HLS INTERFACE bram port=vectorA
    #pragma HLS INTERFACE bram port=vectorB
    #pragma HLS INTERFACE ap_none port=result
    #pragma HLS INTERFACE ap_none port=mode
    #pragma HLS INTERFACE ap_ctrl_hs port=return

    int accumulator = 0;

    if (mode == 0) {
        // --- MODO 0: PRODUCTO PUNTO ---
        dot_loop: for (int i = 0; i < N_ELEMENTS; i++) {
            // Pipeline II=1: Procesa 1 elemento por ciclo
            #pragma HLS PIPELINE II=1
            
            int term = (int)vectorA[i] * (int)vectorB[i];
            accumulator += term;
        }
        result = accumulator; 
        
    } else {
        // --- MODO 1: DISTANCIA EUCLIDIANA ---
        euc_loop: for (int i = 0; i < N_ELEMENTS; i++) {
            #pragma HLS PIPELINE II=1
            
            int valA = (int)vectorA[i];
            int valB = (int)vectorB[i];
            int diff = valA - valB;
            accumulator += (diff * diff);
        }
        
        float acc_float = (float)accumulator;
        float sqrt_val = hls::sqrt(acc_float);
        fixed32_t res_fixed = (fixed32_t)sqrt_val;
        
        result = res_fixed.range(31, 0); 
    }
}