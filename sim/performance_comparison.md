# Hardware Accelerator Performance & Execution Time Comparison

**Image Size:** 100 x 100$ (10,000 pixels)
**Hardware Clock:** 100.0 MHz (10 ns cycle period)

| # | Kernel Filter | Size | ALU Sim Time | MMU Sim Time | HW Execution Cycles | HW Time (@ 100 MHz) | Verification Status |
| :-: | :--- | :-: | :-: | :-: | :-: | :-: | :---: |
| 01 | 1x1 Identity Passthrough | 1x1 | 6.96 s | 6.29 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact Raw) |
| 02 | 3x3 Box Blur | 3x3 | 7.91 s | 7.02 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 03 | 3x3 Horizontal Edge | 3x3 | 8.20 s | 11.92 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 04 | 3x3 Vertical Edge | 3x3 | 12.83 s | 9.54 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 05 | 3x3 Laplacian | 3x3 | 11.12 s | 7.89 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 06 | 3x3 Sharpening | 3x3 | 8.98 s | 8.37 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 07 | 3x3 Sobel Horizontal | 3x3 | 6.60 s | 6.43 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 08 | 3x3 Sobel Vertical | 3x3 | 6.66 s | 6.46 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 09 | 3x3 Custom | 3x3 | 6.64 s | 6.43 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 10 | 5x5 Box Blur | 5x5 | 6.73 s | 6.77 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 11 | 5x5 Horizontal Edge | 5x5 | 6.75 s | 6.13 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 12 | 5x5 Vertical Edge | 5x5 | 6.76 s | 6.49 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 13 | 5x5 Laplacian | 5x5 | 6.78 s | 6.10 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 14 | 5x5 Sharpening | 5x5 | 6.99 s | 6.58 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 15 | 5x5 Sobel Horizontal | 5x5 | 7.07 s | 6.27 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 16 | 5x5 Sobel Vertical | 5x5 | 6.97 s | 6.55 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 17 | 5x5 Gaussian Blur | 5x5 | 7.16 s | 6.32 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 18 | 7x7 Box Blur | 7x7 | 7.92 s | 6.74 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 19 | 7x7 Horizontal Edge | 7x7 | 7.26 s | 6.37 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 20 | 7x7 Vertical Edge | 7x7 | 7.72 s | 6.65 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 21 | 7x7 Laplacian | 7x7 | 7.27 s | 6.32 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 22 | 7x7 Sharpening | 7x7 | 6.80 s | 6.71 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 23 | 7x7 Sobel Horizontal | 7x7 | 7.04 s | 6.17 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 24 | 7x7 Sobel Vertical | 7x7 | 6.92 s | 6.56 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |
| 25 | 7x7 Custom/Gaussian | 7x7 | 7.37 s | 14.72 s | 10,311 cycles | 103.11 us | PASS (Bit-Exact) |

### Summary Statistics

* **Total ModelSim Simulation Time (ALU):** 189.41 s
* **Total ModelSim Simulation Time (MMU):** 181.80 s
* **Average Simulation Time per Kernel:** ALU = 7.58 s, MMU = 7.27 s
* **Hardware Execution Speed on FPGA (@ 100 MHz):** ~103.11 us per 100x100 frame (~9,700 FPS)
