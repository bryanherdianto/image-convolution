# Entity: MMU

- **File:** mmu.vhd
- **Brief:** Dynamic Systolic Matrix Multiplier Unit (MMU) Hardware Accelerator
- **Details:** Implements 49-element im2col systolic matrix-vector multiplication across RGB channels with 5-stage pipelined accumulation matching ALU latency and throughput.

## Diagram

![Diagram](MMU.svg "Diagram")

## Ports

| Port name       | Direction | Type                          | Description                                       |
| --------------- | --------- | ----------------------------- | ------------------------------------------------- |
| CLK             | in        | STD_LOGIC                     | Primary system clock input                        |
| RST             | in        | STD_LOGIC                     | Synchronous active-high reset signal              |
| ENABLE_MMU      | in        | STD_LOGIC                     | MMU computation enable control                    |
| WINDOW_R        | in        | window_channel_t              | Flattened 1x49 red channel image patch vector     |
| WINDOW_G        | in        | window_channel_t              | Flattened 1x49 green channel image patch vector   |
| WINDOW_B        | in        | window_channel_t              | Flattened 1x49 blue channel image patch vector    |
| WINDOW_VALID    | in        | STD_LOGIC                     | Strobe indicating current window pixels are valid |
| WEIGHTS         | in        | kernel_weights_t              | Flattened 49x1 signed 16-bit weight vector        |
| DIVISOR         | in        | INTEGER RANGE 1 TO 256        | Normalization scaling divisor factor              |
| PIXEL_OUT       | out       | STD_LOGIC_VECTOR(23 DOWNTO 0) | 24-bit convolved RGB output pixel                 |
| PIXEL_VALID_OUT | out       | STD_LOGIC                     | Filtered output pixel valid strobe                |

## Signals

| Name         | Type                   | Description                                                      |
| ------------ | ---------------------- | ---------------------------------------------------------------- |
| acc_stage1_r | SIGNED(35 DOWNTO 0)    | Stage 1 red channel systolic partial accumulation (PEs 0..11)    |
| acc_stage1_g | SIGNED(35 DOWNTO 0)    | Stage 1 green channel systolic partial accumulation (PEs 0..11)  |
| acc_stage1_b | SIGNED(35 DOWNTO 0)    | Stage 1 blue channel systolic partial accumulation (PEs 0..11)   |
| acc_stage2_r | SIGNED(35 DOWNTO 0)    | Stage 2 red channel systolic partial accumulation (PEs 12..23)   |
| acc_stage2_g | SIGNED(35 DOWNTO 0)    | Stage 2 green channel systolic partial accumulation (PEs 12..23) |
| acc_stage2_b | SIGNED(35 DOWNTO 0)    | Stage 2 blue channel systolic partial accumulation (PEs 12..23)  |
| acc_stage3_r | SIGNED(35 DOWNTO 0)    | Stage 3 red channel systolic partial accumulation (PEs 24..35)   |
| acc_stage3_g | SIGNED(35 DOWNTO 0)    | Stage 3 green channel systolic partial accumulation (PEs 24..35) |
| acc_stage3_b | SIGNED(35 DOWNTO 0)    | Stage 3 blue channel systolic partial accumulation (PEs 24..35)  |
| acc_stage4_r | SIGNED(35 DOWNTO 0)    | Stage 4 red channel systolic final accumulation (PEs 36..48)     |
| acc_stage4_g | SIGNED(35 DOWNTO 0)    | Stage 4 green channel systolic final accumulation (PEs 36..48)   |
| acc_stage4_b | SIGNED(35 DOWNTO 0)    | Stage 4 blue channel systolic final accumulation (PEs 36..48)    |
| valid_st1    | STD_LOGIC              | Systolic Stage 1 valid flag                                      |
| valid_st2    | STD_LOGIC              | Systolic Stage 2 valid flag                                      |
| valid_st3    | STD_LOGIC              | Systolic Stage 3 valid flag                                      |
| valid_st4    | STD_LOGIC              | Systolic Stage 4 valid flag                                      |
| div_st1      | INTEGER RANGE 1 TO 256 | Stage 1 divisor propagation register                             |
| div_st2      | INTEGER RANGE 1 TO 256 | Stage 2 divisor propagation register                             |
| div_st3      | INTEGER RANGE 1 TO 256 | Stage 3 divisor propagation register                             |
| div_st4      | INTEGER RANGE 1 TO 256 | Stage 4 divisor propagation register                             |
| vec_r_st2    | vec_st2_t              | Forwarded red channel vector inputs for Stage 2 PEs              |
| vec_g_st2    | vec_st2_t              | Forwarded green channel vector inputs for Stage 2 PEs            |
| vec_b_st2    | vec_st2_t              | Forwarded blue channel vector inputs for Stage 2 PEs             |
| vec_r_st3    | vec_st3_t              | Forwarded red channel vector inputs for Stage 3 PEs              |
| vec_g_st3    | vec_st3_t              | Forwarded green channel vector inputs for Stage 3 PEs            |
| vec_b_st3    | vec_st3_t              | Forwarded blue channel vector inputs for Stage 3 PEs             |
| vec_r_st4    | vec_st4_t              | Forwarded red channel vector inputs for Stage 4 PEs              |
| vec_g_st4    | vec_st4_t              | Forwarded green channel vector inputs for Stage 4 PEs            |
| vec_b_st4    | vec_st4_t              | Forwarded blue channel vector inputs for Stage 4 PEs             |

## Types

| Name      | Description                                                |
| --------- | ---------------------------------------------------------- |
| vec_st2_t | Vector forwarding array type for Stage 2 (elements 12..48) |
| vec_st3_t | Vector forwarding array type for Stage 3 (elements 24..48) |
| vec_st4_t | Vector forwarding array type for Stage 4 (elements 36..48) |

## Functions

- clamp_byte
  - Accepts a signed 36-bit integer value (val)
  - Returns an 8-bit unsigned integer (byte_t)
  - Clamps signed 36-bit accumulator value to 8-bit range [0, 255]

## Processes

- mmu_systolic_proc
  - This process has a sensitivity list of CLK
  - This process implements a 5-stage systolic matrix-vector multiplication across RGB channels, with pipelined accumulation and divisor propagation, producing a convolved RGB output pixel and valid strobe
