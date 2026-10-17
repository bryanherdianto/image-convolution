LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE WORK.conv_pkg.ALL;

-- =============================================================================
-- Dynamic Systolic Matrix Multiplier Unit (MMU) Hardware Accelerator
-- Implements im2col matrix-vector multiplication using a 49-element Systolic
-- Processing Element (PE) pipeline architecture:
--   Stage 1: PEs  0..11 (Accumulates partial dot-product of elements 0..11)
--   Stage 2: PEs 12..23 (Accumulates partial dot-product of elements 12..23)
--   Stage 3: PEs 24..35 (Accumulates partial dot-product of elements 24..35)
--   Stage 4: PEs 36..48 (Accumulates partial dot-product of elements 36..48)
--   Stage 5: Normalization (Divisor) and Saturation Clamping to [0, 255]
-- Throughput: 1 RGB pixel per clock cycle
-- Pipeline Latency: 5 clock cycles (matching ALU bit-for-bit and cycle-for-cycle)
-- =============================================================================

ENTITY MMU IS
    PORT (
        CLK             : IN  STD_LOGIC;
        RST             : IN  STD_LOGIC;
        ENABLE_MMU      : IN  STD_LOGIC;
        WINDOW_R        : IN  window_channel_t; -- Flattened 1x49 patch vector
        WINDOW_G        : IN  window_channel_t;
        WINDOW_B        : IN  window_channel_t;
        WINDOW_VALID    : IN  STD_LOGIC;
        WEIGHTS         : IN  kernel_weights_t; -- Flattened 49x1 weight vector
        DIVISOR         : IN  INTEGER RANGE 1 TO 256;
        PIXEL_OUT       : OUT STD_LOGIC_VECTOR(23 DOWNTO 0);
        PIXEL_VALID_OUT : OUT STD_LOGIC
    );
END ENTITY MMU;

ARCHITECTURE RTL OF MMU IS

    -- Systolic Accumulator Stage Types (signed 36-bit)
    SIGNAL acc_stage1_r, acc_stage1_g, acc_stage1_b : SIGNED(35 DOWNTO 0) := (OTHERS => '0');
    SIGNAL acc_stage2_r, acc_stage2_g, acc_stage2_b : SIGNED(35 DOWNTO 0) := (OTHERS => '0');
    SIGNAL acc_stage3_r, acc_stage3_g, acc_stage3_b : SIGNED(35 DOWNTO 0) := (OTHERS => '0');
    SIGNAL acc_stage4_r, acc_stage4_g, acc_stage4_b : SIGNED(35 DOWNTO 0) := (OTHERS => '0');

    -- Pipeline control and divisor propagation
    SIGNAL valid_st1, valid_st2, valid_st3, valid_st4 : STD_LOGIC := '0';
    SIGNAL div_st1, div_st2, div_st3, div_st4         : INTEGER RANGE 1 TO 256 := 1;

    -- Systolic vector pipeline registers to forward remaining inputs to downstream PEs
    TYPE vec_st2_t IS ARRAY (12 TO 48) OF SIGNED(15 DOWNTO 0);
    SIGNAL vec_r_st2, vec_g_st2, vec_b_st2 : vec_st2_t := (OTHERS => (OTHERS => '0'));

    TYPE vec_st3_t IS ARRAY (24 TO 48) OF SIGNED(15 DOWNTO 0);
    SIGNAL vec_r_st3, vec_g_st3, vec_b_st3 : vec_st3_t := (OTHERS => (OTHERS => '0'));

    TYPE vec_st4_t IS ARRAY (36 TO 48) OF SIGNED(15 DOWNTO 0);
    SIGNAL vec_r_st4, vec_g_st4, vec_b_st4 : vec_st4_t := (OTHERS => (OTHERS => '0'));

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

    PROCESS (CLK)
        VARIABLE s1_r, s1_g, s1_b : SIGNED(35 DOWNTO 0);
        VARIABLE s2_r, s2_g, s2_b : SIGNED(35 DOWNTO 0);
        VARIABLE s3_r, s3_g, s3_b : SIGNED(35 DOWNTO 0);
        VARIABLE s4_r, s4_g, s4_b : SIGNED(35 DOWNTO 0);
        VARIABLE sc_r, sc_g, sc_b : SIGNED(35 DOWNTO 0);
        VARIABLE out_px           : rgb_pixel_t;
    BEGIN
        IF RISING_EDGE(CLK) THEN
            IF RST = '1' THEN
                valid_st1       <= '0';
                valid_st2       <= '0';
                valid_st3       <= '0';
                valid_st4       <= '0';
                PIXEL_VALID_OUT <= '0';
                PIXEL_OUT       <= (OTHERS => '0');
            ELSE

                ----------------------------------------------------------------
                -- Systolic PE Array Group 1 (PEs 0..11)
                ----------------------------------------------------------------
                IF ENABLE_MMU = '1' AND WINDOW_VALID = '1' THEN
                    s1_r := (OTHERS => '0');
                    s1_g := (OTHERS => '0');
                    s1_b := (OTHERS => '0');

                    FOR k IN 0 TO 11 LOOP
                        s1_r := s1_r + resize(SIGNED(resize(WINDOW_R(k), 16)) * WEIGHTS(k), 36);
                        s1_g := s1_g + resize(SIGNED(resize(WINDOW_G(k), 16)) * WEIGHTS(k), 36);
                        s1_b := s1_b + resize(SIGNED(resize(WINDOW_B(k), 16)) * WEIGHTS(k), 36);
                    END LOOP;

                    acc_stage1_r <= s1_r;
                    acc_stage1_g <= s1_g;
                    acc_stage1_b <= s1_b;

                    -- Forward vector elements 12..48 into stage 2 registers
                    FOR k IN 12 TO 48 LOOP
                        vec_r_st2(k) <= SIGNED(resize(WINDOW_R(k), 16));
                        vec_g_st2(k) <= SIGNED(resize(WINDOW_G(k), 16));
                        vec_b_st2(k) <= SIGNED(resize(WINDOW_B(k), 16));
                    END LOOP;

                    valid_st1 <= '1';
                    div_st1   <= DIVISOR;
                ELSE
                    valid_st1 <= '0';
                END IF;

                ----------------------------------------------------------------
                -- Systolic PE Array Group 2 (PEs 12..23)
                ----------------------------------------------------------------
                IF valid_st1 = '1' THEN
                    s2_r := acc_stage1_r;
                    s2_g := acc_stage1_g;
                    s2_b := acc_stage1_b;

                    FOR k IN 12 TO 23 LOOP
                        s2_r := s2_r + resize(vec_r_st2(k) * WEIGHTS(k), 36);
                        s2_g := s2_g + resize(vec_g_st2(k) * WEIGHTS(k), 36);
                        s2_b := s2_b + resize(vec_b_st2(k) * WEIGHTS(k), 36);
                    END LOOP;

                    acc_stage2_r <= s2_r;
                    acc_stage2_g <= s2_g;
                    acc_stage2_b <= s2_b;

                    -- Forward vector elements 24..48 into stage 3 registers
                    FOR k IN 24 TO 48 LOOP
                        vec_r_st3(k) <= vec_r_st2(k);
                        vec_g_st3(k) <= vec_g_st2(k);
                        vec_b_st3(k) <= vec_b_st2(k);
                    END LOOP;

                    valid_st2 <= '1';
                    div_st2   <= div_st1;
                ELSE
                    valid_st2 <= '0';
                END IF;

                ----------------------------------------------------------------
                -- Systolic PE Array Group 3 (PEs 24..35)
                ----------------------------------------------------------------
                IF valid_st2 = '1' THEN
                    s3_r := acc_stage2_r;
                    s3_g := acc_stage2_g;
                    s3_b := acc_stage2_b;

                    FOR k IN 24 TO 35 LOOP
                        s3_r := s3_r + resize(vec_r_st3(k) * WEIGHTS(k), 36);
                        s3_g := s3_g + resize(vec_g_st3(k) * WEIGHTS(k), 36);
                        s3_b := s3_b + resize(vec_b_st3(k) * WEIGHTS(k), 36);
                    END LOOP;

                    acc_stage3_r <= s3_r;
                    acc_stage3_g <= s3_g;
                    acc_stage3_b <= s3_b;

                    -- Forward vector elements 36..48 into stage 4 registers
                    FOR k IN 36 TO 48 LOOP
                        vec_r_st4(k) <= vec_r_st3(k);
                        vec_g_st4(k) <= vec_g_st3(k);
                        vec_b_st4(k) <= vec_b_st3(k);
                    END LOOP;

                    valid_st3 <= '1';
                    div_st3   <= div_st2;
                ELSE
                    valid_st3 <= '0';
                END IF;

                ----------------------------------------------------------------
                -- Systolic PE Array Group 4 (PEs 36..48)
                ----------------------------------------------------------------
                IF valid_st3 = '1' THEN
                    s4_r := acc_stage3_r;
                    s4_g := acc_stage3_g;
                    s4_b := acc_stage3_b;

                    FOR k IN 36 TO 48 LOOP
                        s4_r := s4_r + resize(vec_r_st4(k) * WEIGHTS(k), 36);
                        s4_g := s4_g + resize(vec_g_st4(k) * WEIGHTS(k), 36);
                        s4_b := s4_b + resize(vec_b_st4(k) * WEIGHTS(k), 36);
                    END LOOP;

                    acc_stage4_r <= s4_r;
                    acc_stage4_g <= s4_g;
                    acc_stage4_b <= s4_b;

                    valid_st4 <= '1';
                    div_st4   <= div_st3;
                ELSE
                    valid_st4 <= '0';
                END IF;

                ----------------------------------------------------------------
                -- Stage 5: Normalization (Divisor) and Clamping to [0, 255]
                ----------------------------------------------------------------
                IF valid_st4 = '1' THEN
                    IF div_st4 = 1 THEN
                        sc_r := acc_stage4_r;
                        sc_g := acc_stage4_g;
                        sc_b := acc_stage4_b;
                    ELSE
                        sc_r := acc_stage4_r / div_st4;
                        sc_g := acc_stage4_g / div_st4;
                        sc_b := acc_stage4_b / div_st4;
                    END IF;

                    out_px.r := clamp_byte(sc_r);
                    out_px.g := clamp_byte(sc_g);
                    out_px.b := clamp_byte(sc_b);

                    PIXEL_OUT       <= rgb_to_slv(out_px);
                    PIXEL_VALID_OUT <= '1';
                ELSE
                    PIXEL_VALID_OUT <= '0';
                END IF;

            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE RTL;