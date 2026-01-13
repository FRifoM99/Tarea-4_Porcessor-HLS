# IPD432 - Tarea 4: Exploración de Espacio de Diseño con HLS

Este repositorio contiene los archivos fuente y recursos desarrollados para la solución de la **Tarea 4** de la asignatura **IPD432: Diseño Avanzado de Sistemas Digitales**. El proyecto consiste en el co-diseño de un coprocesador vectorial implementado en una FPGA, utilizando Síntesis de Alto Nivel (HLS) para el núcleo de procesamiento y RTL para la infraestructura de control.

## 📂 Organización del Repositorio

Los archivos se encuentran organizados en las siguientes carpetas principales:

### `HLS/`
Contiene los códigos fuente C++ para la generación de los núcleos IP mediante Vitis HLS. Se incluyen las distintas configuraciones exploradas durante el diseño:
* **pipeline/**: Diseño base con optimización de pipeline.
* **factor_16/**: Configuración con desenrollado y partición de factor 16.
* **factor_64/**: Configuración con desenrollado y partición de factor 64.
* **factor_128/**: Configuración con desenrollado y partición de factor 128 (Diseño Final).
* *Golden References*: Archivos de referencia para la verificación de los algoritmos.

> Estos códigos permiten generar los IPs necesarios para ser instanciados en los proyectos de RTL.

### `Matlab/`
Contiene los scripts de MATLAB utilizados para la verificación y pruebas funcionales del procesador en hardware real:
* **`test_processing.m`**: Script principal. Implementa las funciones de escritura y lectura de vectores vía UART, lectura de resultados (Distancia Euclidiana y Producto Punto) y comparación automática con referencias de software para verificar la funcionalidad.
* Validación del formato esperado en los **displays de 7 segmentos** de la tarjeta Nexys A7 (formato Hexadecimal).

### `Vivado/`
Contiene los archivos necesarios para la implementación física del sistema en la FPGA:
* **Constraints/**: Archivos `.xdc` con las restricciones físicas y de tiempo para el diseño.
* **Subcarpetas de Implementación**: Códigos fuente RTL (SystemVerilog) e IPs específicos para integrar cada una de las configuraciones probadas (`pipeline`, `Factor16`, `Factor64`, `Factor128`).
* * **Schematics/**: Esquemas del *Elaborated Design* obtenidos durante la **Actividad 1**, documentando los cambios en la microarquitectura al variar el periodo de reloj (5ns, 15ns y 30ns).

---

## 🏆 Métricas del Diseño Final (Factor 128)

Tras la exploración del espacio de diseño, se determinó que la configuración con **Factor 128** ofrece el mejor rendimiento. A continuación se presentan las métricas obtenidas en hardware real:

| Métrica | Valor | Observación |
| :--- | :--- | :--- |
| **Frecuencia de Reloj** | 100 MHz | Periodo de 10ns |
| **Latencia de Cómputo** | **42 Ciclos** | Medida en hardware mediante **ILA** |
| **Throughput** | 1 dato/ciclo | Procesamiento continuo (II=1) tras latencia inicial |
| **Tiempo de Implementación**| ~8 min | Síntesis + Implementación + Generación de Bitstream |

> **Nota:** La latencia de 42 ciclos considera desde la activación de la señal `ap_start` hasta la validación de `ap_done` en el núcleo HLS.

## ⚙️ Instrucciones de Reproducción

Para reproducir los resultados reportados:

1.  **Generación de IP:** Abra la carpeta `HLS/factor_128` en Vitis HLS, sintetice el diseño y exporte el RTL como IP (una vez agregarda la ruta al repositorio de IPs sólo es necesario actualizar el IP disponible en los archivos de este repositorio).
2.  **Síntesis y Bitstream:** Cree un proyecto en Vivado, importe los archivos de `Vivado/Factor128` y el IP generado. Agregue los *constraints* y genere el *bitstream*.
3.  **Prueba Funcional:** * Programe la FPGA Nexys A7/Nexys4 DDR.
    * Abra MATLAB y asegúrese de configurar el puerto COM correcto (Cambiar si es necesario en la línea 2 del script "test_processing.m").
    * Ejecute el script **`test_processing.m`** ubicado en la carpeta `Matlab/` para enviar vectores de prueba y verificar la respuesta en la consola y en los displays de la tarjeta.

---
**Curso:** IPD432 - Diseño Avanzado de Sistemas Digitales
**Semestre:** 2025-2
