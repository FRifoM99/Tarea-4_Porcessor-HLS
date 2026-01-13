#ifndef PROCESSING_CORE_64_HPP
#define PROCESSING_CORE_64_HPP

#include <ap_int.h>
#include <ap_fixed.h>

#define N_ELEMENTS 1024

typedef short data_t; 
typedef int res_t;

void processing_core_64(data_t vectorA[N_ELEMENTS], data_t vectorB[N_ELEMENTS], res_t &result, bool mode);

#endif