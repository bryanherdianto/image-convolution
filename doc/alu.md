
# Entity: ALU 
- **File**: alu.vhd
- **Brief:**  Dynamic Spatial Convolution ALU Accelerator
- **Details:**  49-multiplier pipelined spatial reduction tree executing parallel 2D convolution across RGB color planes.

## Diagram
![Diagram](ALU.svg "Diagram")
## Description


## Ports

| Port name       | Direction | Type                          | Description                                       |
| --------------- | --------- | ----------------------------- | ------------------------------------------------- |
| CLK             | in        | STD_LOGIC                     | Primary system clock input                        |
| RST             | in        | STD_LOGIC                     | Synchronous active-high reset signal              |
| ENABLE_ALU      | in        | STD_LOGIC                     | ALU computation enable control                    |
| WINDOW_R        | in        | window_channel_t              | 49-element red channel pixel window               |
| WINDOW_G        | in        | window_channel_t              | 49-element green channel pixel window             |
| WINDOW_B        | in        | window_channel_t              | 49-element blue channel pixel window              |
| WINDOW_VALID    | in        | STD_LOGIC                     | Strobe indicating current window pixels are valid |
| WEIGHTS         | in        | kernel_weights_t              | 49 signed 16-bit filter kernel weights            |
| DIVISOR         | in        | INTEGER RANGE 1 TO 256        | Normalization scaling divisor factor              |
| PIXEL_OUT       | out       | STD_LOGIC_VECTOR(23 DOWNTO 0) | 24-bit convolved RGB output pixel                 |
| PIXEL_VALID_OUT | out       | STD_LOGIC                     | Filtered output pixel valid strobe                |

## Signals

| Name         | Type                   | Description                                     |
| ------------ | ---------------------- | ----------------------------------------------- |
| prod_r       | prod_array_t           | Stage 1 red channel multiplier products         |
| prod_g       | prod_array_t           | Stage 1 green channel multiplier products       |
| prod_b       | prod_array_t           | Stage 1 blue channel multiplier products        |
| valid_stage1 | STD_LOGIC              | Pipeline Stage 1 valid flag                     |
| div_stage1   | INTEGER RANGE 1 TO 256 | Pipeline Stage 1 divisor register               |
| sum_l1_r     | sum_l1_t               | Stage 2 red channel Level-1 adder sums          |
| sum_l1_g     | sum_l1_t               | Stage 2 green channel Level-1 adder sums        |
| sum_l1_b     | sum_l1_t               | Stage 2 blue channel Level-1 adder sums         |
| valid_stage2 | STD_LOGIC              | Pipeline Stage 2 valid flag                     |
| div_stage2   | INTEGER RANGE 1 TO 256 | Pipeline Stage 2 divisor register               |
| sum_l2_r     | sum_l2_t               | Stage 3 red channel Level-2 adder sums          |
| sum_l2_g     | sum_l2_t               | Stage 3 green channel Level-2 adder sums        |
| sum_l2_b     | sum_l2_t               | Stage 3 blue channel Level-2 adder sums         |
| valid_stage3 | STD_LOGIC              | Pipeline Stage 3 valid flag                     |
| div_stage3   | INTEGER RANGE 1 TO 256 | Pipeline Stage 3 divisor register               |
| total_sum_r  | SIGNED(35 DOWNTO 0)    | Stage 4 accumulated total sum for red channel   |
| total_sum_g  | SIGNED(35 DOWNTO 0)    | Stage 4 accumulated total sum for green channel |
| total_sum_b  | SIGNED(35 DOWNTO 0)    | Stage 4 accumulated total sum for blue channel  |
| valid_stage4 | STD_LOGIC              | Pipeline Stage 4 valid flag                     |
| div_stage4   | INTEGER RANGE 1 TO 256 | Pipeline Stage 4 divisor register               |

## Types

| Name         | Type | Description                                               |
| ------------ | ---- | --------------------------------------------------------- |
| prod_array_t |      | Product array type holding 49 signed 32-bit products      |
| sum_l1_t     |      | Level-1 pairwise reduction sum array type (49 to 25 sums) |
| sum_l2_t     |      | Level-2 pairwise reduction sum array type (25 to 13 sums) |

## Functions
- clamp_byte <font id="function_arguments">(val : SIGNED)</font> <font id="function_return">RETURN byte_t</font>
  -  Clamps signed 36-bit accumulator value to 8-bit range [0, 255]
## Processes
- alu_pipeline_proc: ( CLK )
  - **Description**
  5-stage pipelined spatial convolution reduction and saturation clamping process
