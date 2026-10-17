LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE WORK.conv_pkg.ALL;

--! @brief Dynamic Spatial Convolution ALU Accelerator
--! @details 49-multiplier pipelined spatial reduction tree executing parallel 2D convolution across RGB color planes.
ENTITY ALU IS
    PORT (
        CLK             : IN  STD_LOGIC;                           --! Primary system clock input
        RST             : IN  STD_LOGIC;                           --! Synchronous active-high reset signal
        ENABLE_ALU      : IN  STD_LOGIC;                           --! ALU computation enable control
        WINDOW_R        : IN  window_channel_t;                    --! 49-element red channel pixel window
        WINDOW_G        : IN  window_channel_t;                    --! 49-element green channel pixel window
        WINDOW_B        : IN  window_channel_t;                    --! 49-element blue channel pixel window
        WINDOW_VALID    : IN  STD_LOGIC;                           --! Strobe indicating current window pixels are valid
        WEIGHTS         : IN  kernel_weights_t;                    --! 49 signed 16-bit filter kernel weights
        DIVISOR         : IN  INTEGER RANGE 1 TO 256;              --! Normalization scaling divisor factor
        PIXEL_OUT       : OUT STD_LOGIC_VECTOR(23 DOWNTO 0);       --! 24-bit convolved RGB output pixel
        PIXEL_VALID_OUT : OUT STD_LOGIC                            --! Filtered output pixel valid strobe
    );
END ENTITY ALU;

ARCHITECTURE RTL OF ALU IS

    --! Product array type holding 49 signed 32-bit products
    TYPE prod_array_t IS ARRAY (0 TO 48) OF SIGNED(31 DOWNTO 0);

    --! Stage 1 red channel multiplier products
    SIGNAL prod_r : prod_array_t := (OTHERS => (OTHERS => '0'));
    --! Stage 1 green channel multiplier products
    SIGNAL prod_g : prod_array_t := (OTHERS => (OTHERS => '0'));
    --! Stage 1 blue channel multiplier products
    SIGNAL prod_b : prod_array_t := (OTHERS => (OTHERS => '0'));
    --! Pipeline Stage 1 valid flag
    SIGNAL valid_stage1 : STD_LOGIC := '0';
    --! Pipeline Stage 1 divisor register
    SIGNAL div_stage1   : INTEGER RANGE 1 TO 256 := 1;

    --! Level-1 pairwise reduction sum array type (49 to 25 sums)
    TYPE sum_l1_t IS ARRAY (0 TO 24) OF SIGNED(33 DOWNTO 0);
    --! Stage 2 red channel Level-1 adder sums
    SIGNAL sum_l1_r : sum_l1_t := (OTHERS => (OTHERS => '0'));
    --! Stage 2 green channel Level-1 adder sums
    SIGNAL sum_l1_g : sum_l1_t := (OTHERS => (OTHERS => '0'));
    --! Stage 2 blue channel Level-1 adder sums
    SIGNAL sum_l1_b : sum_l1_t := (OTHERS => (OTHERS => '0'));
    --! Pipeline Stage 2 valid flag
    SIGNAL valid_stage2 : STD_LOGIC := '0';
    --! Pipeline Stage 2 divisor register
    SIGNAL div_stage2   : INTEGER RANGE 1 TO 256 := 1;

    --! Level-2 pairwise reduction sum array type (25 to 13 sums)
    TYPE sum_l2_t IS ARRAY (0 TO 12) OF SIGNED(34 DOWNTO 0);
    --! Stage 3 red channel Level-2 adder sums
    SIGNAL sum_l2_r : sum_l2_t := (OTHERS => (OTHERS => '0'));
    --! Stage 3 green channel Level-2 adder sums
    SIGNAL sum_l2_g : sum_l2_t := (OTHERS => (OTHERS => '0'));
    --! Stage 3 blue channel Level-2 adder sums
    SIGNAL sum_l2_b : sum_l2_t := (OTHERS => (OTHERS => '0'));
    --! Pipeline Stage 3 valid flag
    SIGNAL valid_stage3 : STD_LOGIC := '0';
    --! Pipeline Stage 3 divisor register
    SIGNAL div_stage3   : INTEGER RANGE 1 TO 256 := 1;

    --! Stage 4 accumulated total sum for red channel
    SIGNAL total_sum_r  : SIGNED(35 DOWNTO 0) := (OTHERS => '0');
    --! Stage 4 accumulated total sum for green channel
    SIGNAL total_sum_g  : SIGNED(35 DOWNTO 0) := (OTHERS => '0');
    --! Stage 4 accumulated total sum for blue channel
    SIGNAL total_sum_b  : SIGNED(35 DOWNTO 0) := (OTHERS => '0');
    --! Pipeline Stage 4 valid flag
    SIGNAL valid_stage4 : STD_LOGIC := '0';
    --! Pipeline Stage 4 divisor register
    SIGNAL div_stage4   : INTEGER RANGE 1 TO 256 := 1;

    --! Clamps signed 36-bit accumulator value to 8-bit range [0, 255]
    FUNCTION clamp_byte(val : SIGNED) RETURN byte_t IS
    BEGIN
        IF val < 0 THEN
            RETURN to_unsigned(0, 8);
        ELSIF val > 255 THEN
            RETURN to_unsigned(255, 8);
        ELSE
            RETURN resize(unsigned(val), 8);
        END IF;
    END FUNCTION;

BEGIN

    --! 5-stage pipelined spatial convolution reduction and saturation clamping process
    alu_pipeline_proc : PROCESS (CLK)
        VARIABLE px_s_r, px_s_g, px_s_b       : SIGNED(15 DOWNTO 0);
        VARIABLE scaled_r, scaled_g, scaled_b : SIGNED(35 DOWNTO 0);
        VARIABLE out_px                       : rgb_pixel_t;
    BEGIN
        IF RISING_EDGE(CLK) THEN
            IF RST = '1' THEN
                valid_stage1    <= '0';
                valid_stage2    <= '0';
                valid_stage3    <= '0';
                valid_stage4    <= '0';
                PIXEL_VALID_OUT <= '0';
                PIXEL_OUT       <= (OTHERS => '0');
            ELSE

                -- Stage 1: 147 Parallel Multipliers (49 R, 49 G, 49 B)
                IF ENABLE_ALU = '1' AND WINDOW_VALID = '1' THEN
                    FOR k IN 0 TO 48 LOOP
                        px_s_r := SIGNED(resize(WINDOW_R(k), 16));
                        px_s_g := SIGNED(resize(WINDOW_G(k), 16));
                        px_s_b := SIGNED(resize(WINDOW_B(k), 16));

                        prod_r(k) <= px_s_r * WEIGHTS(k);
                        prod_g(k) <= px_s_g * WEIGHTS(k);
                        prod_b(k) <= px_s_b * WEIGHTS(k);
                    END LOOP;
                    valid_stage1 <= '1';
                    div_stage1   <= DIVISOR;
                ELSE
                    valid_stage1 <= '0';
                END IF;

                -- Stage 2: Adder Tree Level 1 (Pairwise reduction: 49 -> 25)
                IF valid_stage1 = '1' THEN
                    FOR i IN 0 TO 23 LOOP
                        sum_l1_r(i) <= resize(prod_r(2 * i), 34) + resize(prod_r(2 * i + 1), 34);
                        sum_l1_g(i) <= resize(prod_g(2 * i), 34) + resize(prod_g(2 * i + 1), 34);
                        sum_l1_b(i) <= resize(prod_b(2 * i), 34) + resize(prod_b(2 * i + 1), 34);
                    END LOOP;
                    sum_l1_r(24) <= resize(prod_r(48), 34);
                    sum_l1_g(24) <= resize(prod_g(48), 34);
                    sum_l1_b(24) <= resize(prod_b(48), 34);

                    valid_stage2 <= '1';
                    div_stage2   <= div_stage1;
                ELSE
                    valid_stage2 <= '0';
                END IF;

                -- Stage 3: Adder Tree Level 2 (Pairwise reduction: 25 -> 13)
                IF valid_stage2 = '1' THEN
                    FOR i IN 0 TO 11 LOOP
                        sum_l2_r(i) <= resize(sum_l1_r(2 * i), 35) + resize(sum_l1_r(2 * i + 1), 35);
                        sum_l2_g(i) <= resize(sum_l1_g(2 * i), 35) + resize(sum_l1_g(2 * i + 1), 35);
                        sum_l2_b(i) <= resize(sum_l1_b(2 * i), 35) + resize(sum_l1_b(2 * i + 1), 35);
                    END LOOP;
                    sum_l2_r(12) <= resize(sum_l1_r(24), 35);
                    sum_l2_g(12) <= resize(sum_l1_g(24), 35);
                    sum_l2_b(12) <= resize(sum_l1_b(24), 35);

                    valid_stage3 <= '1';
                    div_stage3   <= div_stage2;
                ELSE
                    valid_stage3 <= '0';
                END IF;

                -- Stage 4: Adder Tree Level 3 (Reduction: 13 -> 1 Total Sum)
                IF valid_stage3 = '1' THEN
                    total_sum_r <= resize(sum_l2_r(0), 36)  + resize(sum_l2_r(1), 36)  +
                                   resize(sum_l2_r(2), 36)  + resize(sum_l2_r(3), 36)  +
                                   resize(sum_l2_r(4), 36)  + resize(sum_l2_r(5), 36)  +
                                   resize(sum_l2_r(6), 36)  + resize(sum_l2_r(7), 36)  +
                                   resize(sum_l2_r(8), 36)  + resize(sum_l2_r(9), 36)  +
                                   resize(sum_l2_r(10), 36) + resize(sum_l2_r(11), 36) +
                                   resize(sum_l2_r(12), 36);

                    total_sum_g <= resize(sum_l2_g(0), 36)  + resize(sum_l2_g(1), 36)  +
                                   resize(sum_l2_g(2), 36)  + resize(sum_l2_g(3), 36)  +
                                   resize(sum_l2_g(4), 36)  + resize(sum_l2_g(5), 36)  +
                                   resize(sum_l2_g(6), 36)  + resize(sum_l2_g(7), 36)  +
                                   resize(sum_l2_g(8), 36)  + resize(sum_l2_g(9), 36)  +
                                   resize(sum_l2_g(10), 36) + resize(sum_l2_g(11), 36) +
                                   resize(sum_l2_g(12), 36);

                    total_sum_b <= resize(sum_l2_b(0), 36)  + resize(sum_l2_b(1), 36)  +
                                   resize(sum_l2_b(2), 36)  + resize(sum_l2_b(3), 36)  +
                                   resize(sum_l2_b(4), 36)  + resize(sum_l2_b(5), 36)  +
                                   resize(sum_l2_b(6), 36)  + resize(sum_l2_b(7), 36)  +
                                   resize(sum_l2_b(8), 36)  + resize(sum_l2_b(9), 36)  +
                                   resize(sum_l2_b(10), 36) + resize(sum_l2_b(11), 36) +
                                   resize(sum_l2_b(12), 36);

                    valid_stage4 <= '1';
                    div_stage4   <= div_stage3;
                ELSE
                    valid_stage4 <= '0';
                END IF;

                -- Stage 5: Normalization (Divisor) and Clamping to [0, 255]
                IF valid_stage4 = '1' THEN
                    IF div_stage4 = 1 THEN
                        scaled_r := total_sum_r;
                        scaled_g := total_sum_g;
                        scaled_b := total_sum_b;
                    ELSE
                        scaled_r := total_sum_r / div_stage4;
                        scaled_g := total_sum_g / div_stage4;
                        scaled_b := total_sum_b / div_stage4;
                    END IF;

                    out_px.r := clamp_byte(scaled_r);
                    out_px.g := clamp_byte(scaled_g);
                    out_px.b := clamp_byte(scaled_b);

                    PIXEL_OUT       <= rgb_to_slv(out_px);
                    PIXEL_VALID_OUT <= '1';
                ELSE
                    PIXEL_VALID_OUT <= '0';
                END IF;

            END IF;
        END IF;
    END PROCESS alu_pipeline_proc;

END ARCHITECTURE RTL;
