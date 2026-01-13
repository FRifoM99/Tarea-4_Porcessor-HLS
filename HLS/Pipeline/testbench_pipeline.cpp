#include "processing_core_pipeline.hpp"
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <sstream>
#include <cstdlib>
#include <cmath>

// Configuración de tolerancia para Q16.16
#define EUC_TOLERANCE 60 

// --- FUNCIÓN DE LECTURA CSV ---
std::vector<std::vector<int>> read_csv(std::string filename, bool skip_header) {
    std::vector<std::vector<int>> data;
    std::ifstream file(filename);
    
    if (!file.is_open()) {
        std::cerr << "ERROR: No se pudo abrir " << filename << std::endl;
        exit(1);
    }

    std::string line;
    if (skip_header) std::getline(file, line); 

    while (std::getline(file, line)) {
        std::vector<int> row;
        std::stringstream ss(line);
        std::string cell;
        while (std::getline(ss, cell, ',')) {
            try {
                row.push_back(std::stoi(cell));
            } catch (...) { continue; }
        }
        if (!row.empty()) data.push_back(row);
    }
    file.close();
    return data;
}

// --- MAIN ---
int main() {
    std::cout << "========================================" << std::endl;
    std::cout << "   TESTBENCH: PIPELINE VERSION (II=1)   " << std::endl;
    std::cout << "========================================" << std::endl;

    std::vector<std::vector<int>> inputs = read_csv("golden_inputs.csv", true);
    std::vector<std::vector<int>> refs = read_csv("golden_references.csv", true);

    if (inputs.size() != refs.size()) {
        std::cerr << "Error: Tamaño de CSVs no coincide." << std::endl;
        return 1;
    }

    int errors = 0;

    for (size_t i = 0; i < inputs.size(); i++) {
        // En el testbench NO usamos volatile
        data_t vecA[N_ELEMENTS];
        data_t vecB[N_ELEMENTS];

        // Mapeo de datos
        for (int j = 0; j < N_ELEMENTS; j++) {
            vecA[j] = (data_t)inputs[i][j];
            vecB[j] = (data_t)inputs[i][j + N_ELEMENTS];
        }

        int ref_dot = refs[i][0];
        int ref_euc = refs[i][1];

        // --- PRUEBA DOT ---
        res_t hw_dot;
        // La función espera volatile, hacemos cast explícito o confiamos en el compilador
        // Para simulación C estándar, pasar arrays normales suele funcionar
        processing_core_pipeline((volatile data_t*)vecA, (volatile data_t*)vecB, hw_dot, 0);

        if (hw_dot != (res_t)ref_dot) {
            std::cout << "[FAIL Pipe] Sample " << i << " DOT. Exp: " << ref_dot << " Got: " << hw_dot << std::endl;
            errors++;
        }

        // --- PRUEBA EUC ---
        res_t hw_euc;
        processing_core_pipeline((volatile data_t*)vecA, (volatile data_t*)vecB, hw_euc, 1);

        long long diff = std::abs((long long)hw_euc - (long long)ref_euc);
        if (diff > EUC_TOLERANCE) {
            std::cout << "[FAIL Pipe] Sample " << i << " EUC. Exp: " << ref_euc << " Got: " << hw_euc << " Diff: " << diff << std::endl;
            errors++;
        }
    }

    if (errors == 0) {
        std::cout << "\n*** TEST PASSED (Pipeline Version) ***" << std::endl;
        return 0;
    } else {
        std::cout << "\n*** TEST FAILED: " << errors << " errors found. ***" << std::endl;
        return 1;
    }
}