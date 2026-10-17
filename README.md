# Real-Time Image Convolution Hardware Accelerator in VHDL

This repository contains a **synthesizable, high-throughput, dynamically reconfigurable hardware accelerator** for 2D image convolution implemented in VHDL.

Unlike high-level behavioral simulation models that rely on host file I/O and dynamic pointers, this architecture is **100% synthesizable RTL**, delivering **real hardware acceleration** with a sustained throughput of **1 output pixel per clock cycle** across dynamic $1 \times 1$, $3 \times 3$, $5 \times 5$, and $7 \times 7$ kernel sizes.

---

## Hardware Architecture

```
                       +---------------------------------------+
                       |    INSTRUCTION (6-bit Dynamic Opcode) |
                       |  [5:4] Radius | [3] Unit | [2:0] Code |
                       +-------------------+-------------------+
                                           |
                                           v
                               +-----------------------+
                               |    DECODER (Comb.)    |
                               +---+-------+-------+---+
                Kernel Weights (49)|       |       | Unit Select
                                   |       |       v
                                   |       |   +--------------+
                                   |       |   | Control FSM  |
                                   |       |   +--------------+
                                   |       | Radius R (0..3)
                                   v       v
+---------------+      +---------------------------------------+
|  PIXEL_IN     | ---> |          LINE_BUFFER (BRAM)           | ---> 7x7 Window Registers (R, G, B)
| (Stream 24b)  |      |   6-Row Cascaded Shift RAM (M10K)     |      + Dynamic Border Zero-Padding
+---------------+      +---------------------------------------+
                                           |
                        +------------------+------------------+
                        |                                     |
                        v                                     v
             +--------------------+                +--------------------+
             |    ALU Engine      |                |    MMU Engine      |
             | Direct Spatial     |                | Systolic PE Array  |
             | 147 Parallel Multi-|                | Vector Matrix Dot- |
             | pliers + Adder Tree|                | Product Engine     |
             +----------+---------+                +----------+---------+
                        |                                     |
                        +------------------+------------------+
                                           |
                                           v
                                  +-----------------+
                                  |   Mux & Clamp   |
                                  +--------+--------+
                                           |
                                           v
                                  +-----------------+
                                  |    PIXEL_OUT    | (1 pixel / cycle)
                                  +-----------------+
```

### Components

1. **[conv_pkg.vhd](file:///c:/Users/victo/Documents/image-convolution/src/conv_pkg.vhd)**  
   Core package defining hardware types: 24-bit RGB pixel records, 49-element ($7 \times 7$) window channel arrays, 16-bit signed fixed-point kernel weights, and conversion utilities.

2. **[decoder.vhd](file:///c:/Users/victo/Documents/image-convolution/src/decoder.vhd)**  
   Dynamic 6-bit combinational instruction decoder that translates opcode bits into kernel weights, divisor factors, border padding radius, and unit selection signals without introducing clock delay races. Automatically zero-masks inactive weights outside the active kernel radius.

3. **[line_buffer.vhd](file:///c:/Users/victo/Documents/image-convolution/src/line_buffer.vhd)**  
   Synthesizable 6-Line Buffer implemented via on-chip Block RAM (BRAM / M10K) and a $7 \times 7$ shift register array. Maintains a uniform center pixel latency ($3 \times \text{IMG\_WIDTH} + 3$) across all kernel sizes, ensuring glitch-free video streaming when toggling modes on the fly.

4. **[alu.vhd](file:///c:/Users/victo/Documents/image-convolution/src/alu.vhd) (Direct 2D Convolution Accelerator)**  
   Spatial convolution accelerator featuring:
   - **147 Parallel Multipliers** computing all 49 spatial coefficients for Red, Green, and Blue concurrently.
   - **Pipelined Adder Trees** for each color channel (Stage 2: 49 $\rightarrow$ 25, Stage 3: 25 $\rightarrow$ 13, Stage 4: 13 $\rightarrow$ 1).
   - Stage 5: Pipelined division/scaling and hardware saturation clamping to $[0, 255]$.
   - **Throughput:** 1 RGB pixel per clock cycle (5-stage latency).

5. **[mmu.vhd](file:///c:/Users/victo/Documents/image-convolution/src/mmu.vhd) (Matrix Multiplier Unit / Systolic Array)**  
   Matrix convolution accelerator implementing `im2col` systolic matrix-vector multiplication:
   - 4-stage systolic processing element pipeline accumulating partial dot-products across 49 vector elements.
   - Stage 5: Pipelined normalization and clamping to $[0, 255]$.
   - **Throughput:** 1 RGB pixel per clock cycle (5-stage latency, bit-for-bit and cycle-for-cycle match with ALU).

6. **[cpu.vhd](file:///c:/Users/victo/Documents/image-convolution/src/cpu.vhd) (Top-Level Accelerator Core)**  
   Synthesizable top-level integrating the Line Buffer, Decoder, ALU, MMU, performance cycle counter, and master control FSM.

7. **[tb_image_convolution.vhd](file:///c:/Users/victo/Documents/image-convolution/sim/tb_image_convolution.vhd)**  
   Hardware simulation testbench that streams BMP image pixels cycle-by-cycle into the hardware accelerator, collects filtered output pixels, and verifies execution metrics.

---

## Dynamic Instruction Mapping (6-Bit Opcode)

### Encoding Structure:
* **Bits [5:4] (Radius $R$)**: Directly encodes the kernel border radius $R$, where kernel dimension $K = 2R + 1$:
  * `00` ($R = 0$) $\rightarrow$ **$1 \times 1$ Identity Passthrough**
  * `01` ($R = 1$) $\rightarrow$ **$3 \times 3$ Kernel**
  * `10` ($R = 2$) $\rightarrow$ **$5 \times 5$ Kernel**
  * `11` ($R = 3$) $\rightarrow$ **$7 \times 7$ Kernel**
* **Bit [3] (Unit Select)**:
  * `0` $\rightarrow$ **ALU** (Direct Spatial Adder Tree)
  * `1` $\rightarrow$ **MMU** (Systolic Matrix Multiplier Array)
* **Bits [2:0] (Filter Opcode)**: Selects filter profile.

### Instruction Table

| Size | Instruction (ALU) | Instruction (MMU) | Filter Name | Divisor | Description |
| :---: | :---: | :---: | :--- | :---: | :--- |
| **$1 \times 1$** | `000000` | `001000` | Identity / Passthrough | 1 | Bit-for-bit raw original pixel bypass with zero latency skew |
| **$3 \times 3$** | `010000` | `011000` | Box Blur | 9 | $3 \times 3$ spatial box average ($1/9$) |
| **$3 \times 3$** | `010001` | `011001` | Horizontal Edge | 1 | Horizontal gradient edge detector |
| **$3 \times 3$** | `010010` | `011010` | Vertical Edge | 1 | Vertical gradient edge detector |
| **$3 \times 3$** | `010011` | `011011` | Laplacian | 1 | Discrete 2D Laplacian operator |
| **$3 \times 3$** | `010100` | `011100` | Sharpening | 1 | High-pass image sharpening |
| **$3 \times 3$** | `010101` | `011101` | Sobel Horizontal | 1 | Standard $3 \times 3$ horizontal Sobel gradient |
| **$3 \times 3$** | `010110` | `011110` | Sobel Vertical | 1 | Standard $3 \times 3$ vertical Sobel gradient |
| **$3 \times 3$** | `010111` | `011111` | Custom Kernel | 100 | Custom user-defined filter |
| **$5 \times 5$** | `100000` | `101000` | Box Blur 5x5 | 25 | $5 \times 5$ spatial box average ($1/25$) |
| **$5 \times 5$** | `100001` | `101001` | Horizontal Edge 5x5 | 1 | 5-tap horizontal edge detector |
| **$5 \times 5$** | `100010` | `101010` | Vertical Edge 5x5 | 1 | 5-tap vertical edge detector |
| **$5 \times 5$** | `100011` | `101011` | Laplacian 5x5 | 1 | Wide-aperture $5 \times 5$ Laplacian |
| **$5 \times 5$** | `100100` | `101100` | Sharpening 5x5 | 1 | $5 \times 5$ high-pass sharpening |
| **$5 \times 5$** | `100101` | `101101` | Sobel Horizontal 5x5 | 1 | $5 \times 5$ horizontal Sobel gradient |
| **$5 \times 5$** | `100110` | `101110` | Sobel Vertical 5x5 | 1 | $5 \times 5$ vertical Sobel gradient |
| **$5 \times 5$** | `100111` | `101111` | Gaussian Blur 5x5 | 256 | Binomial Gaussian blur $[1, 4, 6, 4, 1]$ |
| **$7 \times 7$** | `110000` | `111000` | Box Blur 7x7 | 49 | $7 \times 7$ wide spatial box average ($1/49$) |
| **$7 \times 7$** | `110001` | `111001` | Horizontal Edge 7x7 | 1 | 7-tap horizontal edge detector |
| **$7 \times 7$** | `110010` | `111010` | Vertical Edge 7x7 | 1 | 7-tap vertical edge detector |
| **$7 \times 7$** | `110011` | `111011` | Laplacian 7x7 | 1 | Deep $7 \times 7$ Laplacian operator |
| **$7 \times 7$** | `110100` | `111100` | Sharpening 7x7 | 1 | $7 \times 7$ wide-aperture sharpening |
| **$7 \times 7$** | `110101` | `111101` | Sobel Horizontal 7x7 | 1 | $7 \times 7$ horizontal Sobel gradient |
| **$7 \times 7$** | `110110` | `111110` | Sobel Vertical 7x7 | 1 | $7 \times 7$ vertical Sobel gradient |
| **$7 \times 7$** | `110111` | `111111` | Custom/Gaussian 7x7 | 100 | Wide-area custom kernel |

---

## Verification & Automated Test Suite

To compile all synthesizable RTL files:

```powershell
& "D:\intelFPGA_lite\20.1\modelsim_ase\win32aloem\vcom.exe" -work work src/conv_pkg.vhd src/decoder.vhd src/line_buffer.vhd src/alu.vhd src/mmu.vhd src/cpu.vhd sim/tb_image_convolution.vhd
```

To run the complete automated test suite across all kernel sizes and units:

```powershell
python sim/run_all_tests.py
```