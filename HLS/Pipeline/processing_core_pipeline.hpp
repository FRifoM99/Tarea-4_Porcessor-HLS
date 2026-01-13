#ifndef PROCESSING_CORE_PIPELINE_HPP
#define PROCESSING_CORE_PIPELINE_HPP

#include <ap_int.h>
#include <ap_fixed.h>

// Definiciones globales
#define N_ELEMENTS 1024

// Definición de tipos
typedef short data_t; 
typedef int res_t;

void processing_core_pipeline(volatile data_t vectorA[N_ELEMENTS], volatile data_t vectorB[N_ELEMENTS], res_t &result, bool mode);

#endif