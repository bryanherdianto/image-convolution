LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE WORK.conv_pkg.ALL;

--! @brief Dynamic Systolic Matrix Multiplier Unit (MMU) Hardware Accelerator
--! @details Implements 49-element im2col systolic matrix-vector multiplication across RGB channels with 5-stage pipelined accumulation matching ALU latency and throughput.
ENTITY MMU IS
    PORT (
        CLK             : IN  STD_LOGIC;                           --! Primary system clock input
        RST             : IN  STD_LOGIC;                           --! Synchronous active-high reset signal
        ENABLE_MMU      : IN  STD_LOGIC;                           --! MMU computation enable control
        WINDOW_R        : IN  window_channel_t;                    --! Flattened 1x49 red channel image patch vector
        WINDOW_G        : IN  window_channel_t;                    --! Flattened 1x49 green channel image patch vector
        WINDOW_B        : IN  window_channel_t;                    --! Flattened 1x49 blue channel image patch vector
        WINDOW_VALID    : IN  STD_LOGIC;                           --! Strobe indicating current window pixels are valid
        WEIGHTS         : IN  kernel_weights_t;                    --! Flattened 49x1 signed 16-bit weight vector
        DIVISOR         : IN  INTEGER RANGE 1 TO 256;              --! Normalization scaling divisor factor
        PIXEL_OUT       : OUT STD_LOGIC_VECTOR(23 DOWNTO 0);       --! 24-bit convolved RGB output pixel
        PIXEL_VALID_OUT : OUT STD_LOGIC                            --! Filtered output pixel valid strobe
    );
END ENTITY MMU;

ARCHITECTURE RTL OF MMU IS

    --! Stage 1 red channel systolic partial accumulation (PEs 0..11)
    SIGNAL acc_stage1_r : SIGNED(35 DOWNTO 0) := (OTHERS => '0');
    --! Stage 1 green channel systolic partial accumulation (PEs 0..11)
    SIGNAL acc_stage1_g : SIGNED(35 DOWNTO 0) := (OTHERS => '0');
    --! Stage 1 blue channel systolic partial accumulation (PEs 0..11)
    SIGNAL acc_stage1_b : SIGNED(35 DOWNTO 0) := (OTHERS => '0');

    --! Stage 2 red channel systolic partial accumulation (PEs 12..23)
    SIGNAL acc_stage2_r : SIGNED(35 DOWNTO 0) := (OTHERS => '0');
    --! Stage 2 green channel systolic partial accumulation (PEs 12..23)
    SIGNAL acc_stage2_g : SIGNED(35 DOWNTO 0) := (OTHERS => '0');
    --! Stage 2 blue channel systolic partial accumulation (PEs 12..23)
    SIGNAL acc_stage2_b : SIGNED(35 DOWNTO 0) := (OTHERS => '0');

    --! Stage 3 red channel systolic partial accumulation (PEs 24..35)
    SIGNAL acc_stage3_r : SIGNED(35 DOWNTO 0) := (OTHERS => '0');
    --! Stage 3 green channel systolic partial accumulation (PEs 24..35)
    SIGNAL acc_stage3_g : SIGNED(35 DOWNTO 0) := (OTHERS => '0');
    --! Stage 3 blue channel systolic partial accumulation (PEs 24..35)
    SIGNAL acc_stage3_b : SIGNED(35 DOWNTO 0) := (OTHERS => '0');

    --! Stage 4 red channel systolic final accumulation (PEs 36..48)
    SIGNAL acc_stage4_r : SIGNED(35 DOWNTO 0) := (OTHERS => '0');
    --! Stage 4 green channel systolic final accumulation (PEs 36..48)
    SIGNAL acc_stage4_g : SIGNED(35 DOWNTO 0) := (OTHERS => '0');
    --! Stage 4 blue channel systolic final accumulation (PEs 36..48)
    SIGNAL acc_stage4_b : SIGNED(35 DOWNTO 0) := (OTHERS => '0');

    --! Systolic Stage 1 valid flag
    SIGNAL valid_st1 : STD_LOGIC := '0';
    --! Systolic Stage 2 valid flag
    SIGNAL valid_st2 : STD_LOGIC := '0';
    --! Systolic Stage 3 valid flag
    SIGNAL valid_st3 : STD_LOGIC := '0';
    --! Systolic Stage 4 valid flag
    SIGNAL valid_st4 : STD_LOGIC := '0';

    --! Stage 1 divisor propagation register
    SIGNAL div_st1 : INTEGER RANGE 1 TO 256 := 1;
    --! Stage 2 divisor propagation register
    SIGNAL div_st2 : INTEGER RANGE 1 TO 256 := 1;
    --! Stage 3 divisor propagation register
    SIGNAL div_st3 : INTEGER RANGE 1 TO 256 := 1;
    --! Stage 4 divisor propagation register
    SIGNAL div_st4 : INTEGER RANGE 1 TO 256 := 1;

    --! Vector forwarding array type for Stage 2 (elements 12..48)
    TYPE vec_st2_t IS ARRAY (12 TO 48) OF SIGNED(15 DOWNTO 0);
    --! Forwarded red channel vector inputs for Stage 2 PEs
    SIGNAL vec_r_st2 : vec_st2_t := (OTHERS => (OTHERS => '0'));
    --! Forwarded green channel vector inputs for Stage 2 PEs
    SIGNAL vec_g_st2 : vec_st2_t := (OTHERS => (OTHERS => '0'));
    --! Forwarded blue channel vector inputs for Stage 2 PEs
    SIGNAL vec_b_st2 : vec_st2_t := (OTHERS => (OTHERS => '0'));

    --! Vector forwarding array type for Stage 3 (elements 24..48)
    TYPE vec_st3_t IS ARRAY (24 TO 48) OF SIGNED(15 DOWNTO 0);
    --! Forwarded red channel vector inputs for Stage 3 PEs
    SIGNAL vec_r_st3 : vec_st3_t := (OTHERS => (OTHERS => '0'));
    --! Forwarded green channel vector inputs for Stage 3 PEs
    SIGNAL vec_g_st3 : vec_st3_t := (OTHERS => (OTHERS => '0'));
    --! Forwarded blue channel vector inputs for Stage 3 PEs
    SIGNAL vec_b_st3 : vec_st3_t := (OTHERS => (OTHERS => '0'));

    --! Vector forwarding array type for Stage 4 (elements 36..48)
    TYPE vec_st4_t IS ARRAY (36 TO 48) OF SIGNED(15 DOWNTO 0);
    --! Forwarded red channel vector inputs for Stage 4 PEs
    SIGNAL vec_r_st4 : vec_st4_t := (OTHERS => (OTHERS => '0'));
    --! Forwarded green channel vector inputs for Stage 4 PEs
    SIGNAL vec_g_st4 : vec_st4_t := (OTHERS => (OTHERS => '0'));
    --! Forwarded blue channel vector inputs for Stage 4 PEs
    SIGNAL vec_b_st4 : vec_st4_t := (OTHERS => (OTHERS => '0'));

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

    --! 5-stage systolic matrix multiplier accumulation and saturation clamping process
    mmu_systolic_proc : PROCESS (CLK)
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

                -- Systolic PE Array Group 1 (PEs 0..11)
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

                -- Systolic PE Array Group 2 (PEs 12..23)
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

                -- Systolic PE Array Group 3 (PEs 24..35)
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

                -- Systolic PE Array Group 4 (PEs 36..48)
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

                -- Stage 5: Normalization (Divisor) and Clamping to [0, 255]
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
    END PROCESS mmu_systolic_proc;

END ARCHITECTURE RTL;
