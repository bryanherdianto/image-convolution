# Entity: DECODER

- **File:** decoder.vhd
- **Brief:** Dynamic Combinational Instruction Decoder
- **Details:** Decodes a 6-bit instruction into kernel radius (bits 5:4), accelerator unit select (bit 3), and filter opcode (bits 2:0), generating 49 spatial filter weights and divisor.

## Diagram

![Diagram](DECODER.svg "Diagram")

## Ports

| Port name   | Direction | Type                         | Description                                               |
| ----------- | --------- | ---------------------------- | --------------------------------------------------------- |
| INSTRUCTION | in        | STD_LOGIC_VECTOR(5 DOWNTO 0) | 6-bit packed filter configuration instruction             |
| OPCODE      | out       | STD_LOGIC_VECTOR(2 DOWNTO 0) | 3-bit decoded filter operation opcode                     |
| RADIUS      | out       | INTEGER RANGE 0 TO 3         | Decoded kernel border radius (0=1x1, 1=3x3, 2=5x5, 3=7x7) |
| UNIT_SELECT | out       | STD_LOGIC                    | Target processing unit select ('0' = ALU, '1' = MMU)      |
| WEIGHTS     | out       | kernel_weights_t             | 49 signed 16-bit decoded convolution weights              |
| DIVISOR     | out       | INTEGER RANGE 1 TO 256       | Decoded normalization divisor factor                      |

## Signals

| Name      | Type                         | Description                                                         |
| --------- | ---------------------------- | ------------------------------------------------------------------- |
| size_code | STD_LOGIC_VECTOR(1 DOWNTO 0) | Upper 2 bits of instruction selecting kernel radius [5:4]           |
| op_code   | STD_LOGIC_VECTOR(2 DOWNTO 0) | Lower 3 bits of instruction selecting filter operation opcode [2:0] |

## Processes

- decode_proc
  - This process has a sensitivity list of size_code and op_code
  - This process decodes the 6-bit instruction into kernel radius, unit select, and filter opcode, generating the corresponding 49 spatial filter weights and divisor

> The 49 spatial filter weights are generated based on the decoded kernel radius and filter opcode, allowing for dynamic configuration of the convolution operation. The divisor is also determined based on the selected filter to ensure proper normalization of the output pixel values.
