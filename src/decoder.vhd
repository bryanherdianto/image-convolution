LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE WORK.conv_pkg.ALL;

-- =============================================================================
-- Dynamic Combinational Instruction Decoder
-- Decodes 6-bit instruction into:
--   Bits [5:4]: Kernel Size / Border Radius R (00=1x1, 01=3x3, 10=5x5, 11=7x7)
--   Bit  [3]  : Unit Select ('0' = ALU, '1' = MMU)
--   Bits [2:0]: Filter Opcode (000 to 111)
-- Populates 49 kernel weights (zero-masked outside active radius) and divisor
-- =============================================================================

ENTITY DECODER IS
    PORT (
        INSTRUCTION  : IN  STD_LOGIC_VECTOR(5 DOWNTO 0);
        OPCODE       : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
        RADIUS       : OUT INTEGER RANGE 0 TO 3;
        UNIT_SELECT  : OUT STD_LOGIC; -- '0' = ALU, '1' = MMU
        WEIGHTS      : OUT kernel_weights_t;
        DIVISOR      : OUT INTEGER RANGE 1 TO 256
    );
END ENTITY DECODER;

ARCHITECTURE RTL OF DECODER IS

    SIGNAL size_code : STD_LOGIC_VECTOR(1 DOWNTO 0);
    SIGNAL op_code   : STD_LOGIC_VECTOR(2 DOWNTO 0);

BEGIN

    size_code   <= INSTRUCTION(5 DOWNTO 4);
    UNIT_SELECT <= INSTRUCTION(3);
    op_code     <= INSTRUCTION(2 DOWNTO 0);
    OPCODE      <= op_code;
    RADIUS      <= to_integer(unsigned(size_code));

    PROCESS (size_code, op_code)
        VARIABLE w : kernel_weights_t;
        VARIABLE d : INTEGER RANGE 1 TO 256;
    BEGIN
        -- Default: all weights 0, divisor 1
        FOR k IN 0 TO 48 LOOP
            w(k) := to_signed(0, 16);
        END LOOP;
        d := 1;

        CASE size_code IS

            --------------------------------------------------------------------
            -- 00: 1x1 Identity / Passthrough Mode (Radius R = 0)
            -- Only dead-center weight (3,3, index 24) is active!
            --------------------------------------------------------------------
            WHEN "00" =>
                w(CENTER_ELEM) := to_signed(1, 16);
                d := 1;

            --------------------------------------------------------------------
            -- 01: 3x3 Dynamic Mode (Radius R = 1)
            -- Active indices: row 2..4, col 2..4 centered at (3,3)
            --   Row 2: 16, 17, 18
            --   Row 3: 23, 24, 25 (center 24)
            --   Row 4: 30, 31, 32
            --------------------------------------------------------------------
            WHEN "01" =>
                CASE op_code IS
                    -- 000: Box Blur 3x3 (1/9 everywhere)
                    WHEN "000" =>
                        w(16) := to_signed(1, 16); w(17) := to_signed(1, 16); w(18) := to_signed(1, 16);
                        w(23) := to_signed(1, 16); w(24) := to_signed(1, 16); w(25) := to_signed(1, 16);
                        w(30) := to_signed(1, 16); w(31) := to_signed(1, 16); w(32) := to_signed(1, 16);
                        d := 9;

                    -- 001: Horizontal Edge
                    WHEN "001" =>
                        w(16) := to_signed(-1, 16); w(17) := to_signed(-1, 16); w(18) := to_signed(-1, 16);
                        w(23) := to_signed(0, 16);  w(24) := to_signed(0, 16);  w(25) := to_signed(0, 16);
                        w(30) := to_signed(1, 16);  w(31) := to_signed(1, 16);  w(32) := to_signed(1, 16);
                        d := 1;

                    -- 010: Vertical Edge
                    WHEN "010" =>
                        w(16) := to_signed(-1, 16); w(17) := to_signed(0, 16); w(18) := to_signed(1, 16);
                        w(23) := to_signed(-1, 16); w(24) := to_signed(0, 16); w(25) := to_signed(1, 16);
                        w(30) := to_signed(-1, 16); w(31) := to_signed(0, 16); w(32) := to_signed(1, 16);
                        d := 1;

                    -- 011: Laplacian
                    WHEN "011" =>
                        w(16) := to_signed(0, 16);  w(17) := to_signed(-1, 16); w(18) := to_signed(0, 16);
                        w(23) := to_signed(-1, 16); w(24) := to_signed(4, 16);  w(25) := to_signed(-1, 16);
                        w(30) := to_signed(0, 16);  w(31) := to_signed(-1, 16); w(32) := to_signed(0, 16);
                        d := 1;

                    -- 100: Sharpening
                    WHEN "100" =>
                        w(16) := to_signed(0, 16);  w(17) := to_signed(-1, 16); w(18) := to_signed(0, 16);
                        w(23) := to_signed(-1, 16); w(24) := to_signed(5, 16);  w(25) := to_signed(-1, 16);
                        w(30) := to_signed(0, 16);  w(31) := to_signed(-1, 16); w(32) := to_signed(0, 16);
                        d := 1;

                    -- 101: Sobel Horizontal
                    WHEN "101" =>
                        w(16) := to_signed(-1, 16); w(17) := to_signed(0, 16); w(18) := to_signed(1, 16);
                        w(23) := to_signed(-2, 16); w(24) := to_signed(0, 16); w(25) := to_signed(2, 16);
                        w(30) := to_signed(-1, 16); w(31) := to_signed(0, 16); w(32) := to_signed(1, 16);
                        d := 1;

                    -- 110: Sobel Vertical
                    WHEN "110" =>
                        w(16) := to_signed(-1, 16); w(17) := to_signed(-2, 16); w(18) := to_signed(-1, 16);
                        w(23) := to_signed(0, 16);  w(24) := to_signed(0, 16);  w(25) := to_signed(0, 16);
                        w(30) := to_signed(1, 16);  w(31) := to_signed(2, 16);  w(32) := to_signed(1, 16);
                        d := 1;

                    -- 111: Custom Kernel
                    WHEN OTHERS =>
                        w(16) := to_signed(100, 16);  w(17) := to_signed(400, 16);  w(18) := to_signed(100, 16);
                        w(23) := to_signed(0, 16);    w(24) := to_signed(-200, 16); w(25) := to_signed(100, 16);
                        w(30) := to_signed(33, 16);   w(31) := to_signed(50, 16);   w(32) := to_signed(-200, 16);
                        d := 100;
                END CASE;

            --------------------------------------------------------------------
            -- 10: 5x5 Dynamic Mode (Radius R = 2)
            -- Active indices: row 1..5, col 1..5 centered at (3,3)
            --------------------------------------------------------------------
            WHEN "10" =>
                CASE op_code IS
                    -- 000: Box Blur 5x5 (1/25)
                    WHEN "000" =>
                        FOR r IN 1 TO 5 LOOP
                            FOR c IN 1 TO 5 LOOP
                                w(r * 7 + c) := to_signed(1, 16);
                            END LOOP;
                        END LOOP;
                        d := 25;

                    -- 001: Horizontal Edge 5x5
                    WHEN "001" =>
                        FOR c IN 1 TO 5 LOOP
                            w(1 * 7 + c) := to_signed(-2, 16);
                            w(2 * 7 + c) := to_signed(-1, 16);
                            w(3 * 7 + c) := to_signed(0, 16);
                            w(4 * 7 + c) := to_signed(1, 16);
                            w(5 * 7 + c) := to_signed(2, 16);
                        END LOOP;
                        d := 1;

                    -- 010: Vertical Edge 5x5
                    WHEN "010" =>
                        FOR r IN 1 TO 5 LOOP
                            w(r * 7 + 1) := to_signed(-2, 16);
                            w(r * 7 + 2) := to_signed(-1, 16);
                            w(r * 7 + 3) := to_signed(0, 16);
                            w(r * 7 + 4) := to_signed(1, 16);
                            w(r * 7 + 5) := to_signed(2, 16);
                        END LOOP;
                        d := 1;

                    -- 011: Laplacian 5x5
                    WHEN "011" =>
                        FOR r IN 1 TO 5 LOOP
                            FOR c IN 1 TO 5 LOOP
                                w(r * 7 + c) := to_signed(-1, 16);
                            END LOOP;
                        END LOOP;
                        w(CENTER_ELEM) := to_signed(24, 16);
                        d := 1;

                    -- 100: Sharpening 5x5
                    WHEN "100" =>
                        FOR r IN 1 TO 5 LOOP
                            FOR c IN 1 TO 5 LOOP
                                w(r * 7 + c) := to_signed(-1, 16);
                            END LOOP;
                        END LOOP;
                        w(CENTER_ELEM) := to_signed(25, 16);
                        d := 1;

                    -- 101: Sobel Horizontal 5x5
                    WHEN "101" =>
                        w(1*7+1) := to_signed(-1, 16); w(1*7+2) := to_signed(-2, 16); w(1*7+3) := to_signed(0, 16); w(1*7+4) := to_signed(2, 16); w(1*7+5) := to_signed(1, 16);
                        w(2*7+1) := to_signed(-2, 16); w(2*7+2) := to_signed(-3, 16); w(2*7+3) := to_signed(0, 16); w(2*7+4) := to_signed(3, 16); w(2*7+5) := to_signed(2, 16);
                        w(3*7+1) := to_signed(-3, 16); w(3*7+2) := to_signed(-5, 16); w(3*7+3) := to_signed(0, 16); w(3*7+4) := to_signed(5, 16); w(3*7+5) := to_signed(3, 16);
                        w(4*7+1) := to_signed(-2, 16); w(4*7+2) := to_signed(-3, 16); w(4*7+3) := to_signed(0, 16); w(4*7+4) := to_signed(3, 16); w(4*7+5) := to_signed(2, 16);
                        w(5*7+1) := to_signed(-1, 16); w(5*7+2) := to_signed(-2, 16); w(5*7+3) := to_signed(0, 16); w(5*7+4) := to_signed(2, 16); w(5*7+5) := to_signed(1, 16);
                        d := 1;

                    -- 110: Sobel Vertical 5x5
                    WHEN "110" =>
                        w(1*7+1) := to_signed(-1, 16); w(1*7+2) := to_signed(-2, 16); w(1*7+3) := to_signed(-3, 16); w(1*7+4) := to_signed(-2, 16); w(1*7+5) := to_signed(-1, 16);
                        w(2*7+1) := to_signed(-2, 16); w(2*7+2) := to_signed(-3, 16); w(2*7+3) := to_signed(-5, 16); w(2*7+4) := to_signed(-3, 16); w(2*7+5) := to_signed(-2, 16);
                        w(3*7+1) := to_signed(0, 16);  w(3*7+2) := to_signed(0, 16);  w(3*7+3) := to_signed(0, 16);  w(3*7+4) := to_signed(0, 16);  w(3*7+5) := to_signed(0, 16);
                        w(4*7+1) := to_signed(2, 16);  w(4*7+2) := to_signed(3, 16);  w(4*7+3) := to_signed(5, 16);  w(4*7+4) := to_signed(3, 16);  w(4*7+5) := to_signed(2, 16);
                        w(5*7+1) := to_signed(1, 16);  w(5*7+2) := to_signed(2, 16);  w(5*7+3) := to_signed(3, 16);  w(5*7+4) := to_signed(2, 16);  w(5*7+5) := to_signed(1, 16);
                        d := 1;

                    -- 111: Gaussian Blur 5x5 (Binomial [1, 4, 6, 4, 1] / 256)
                    WHEN OTHERS =>
                        w(1*7+1) := to_signed(1, 16);  w(1*7+2) := to_signed(4, 16);  w(1*7+3) := to_signed(6, 16);  w(1*7+4) := to_signed(4, 16);  w(1*7+5) := to_signed(1, 16);
                        w(2*7+1) := to_signed(4, 16);  w(2*7+2) := to_signed(16, 16); w(2*7+3) := to_signed(24, 16); w(2*7+4) := to_signed(16, 16); w(2*7+5) := to_signed(4, 16);
                        w(3*7+1) := to_signed(6, 16);  w(3*7+2) := to_signed(24, 16); w(3*7+3) := to_signed(36, 16); w(3*7+4) := to_signed(24, 16); w(3*7+5) := to_signed(6, 16);
                        w(4*7+1) := to_signed(4, 16);  w(4*7+2) := to_signed(16, 16); w(4*7+3) := to_signed(24, 16); w(4*7+4) := to_signed(16, 16); w(4*7+5) := to_signed(4, 16);
                        w(5*7+1) := to_signed(1, 16);  w(5*7+2) := to_signed(4, 16);  w(5*7+3) := to_signed(6, 16);  w(5*7+4) := to_signed(4, 16);  w(5*7+5) := to_signed(1, 16);
                        d := 256;
                END CASE;

            --------------------------------------------------------------------
            -- 11: 7x7 Dynamic Mode (Radius R = 3)
            -- All 49 weights active (rows 0..6, cols 0..6)
            --------------------------------------------------------------------
            WHEN OTHERS =>
                CASE op_code IS
                    -- 000: Box Blur 7x7 (1/49)
                    WHEN "000" =>
                        FOR k IN 0 TO 48 LOOP
                            w(k) := to_signed(1, 16);
                        END LOOP;
                        d := 49;

                    -- 001: Horizontal Edge 7x7
                    WHEN "001" =>
                        FOR c IN 0 TO 6 LOOP
                            w(0 * 7 + c) := to_signed(-3, 16);
                            w(1 * 7 + c) := to_signed(-2, 16);
                            w(2 * 7 + c) := to_signed(-1, 16);
                            w(3 * 7 + c) := to_signed(0, 16);
                            w(4 * 7 + c) := to_signed(1, 16);
                            w(5 * 7 + c) := to_signed(2, 16);
                            w(6 * 7 + c) := to_signed(3, 16);
                        END LOOP;
                        d := 1;

                    -- 010: Vertical Edge 7x7
                    WHEN "010" =>
                        FOR r IN 0 TO 6 LOOP
                            w(r * 7 + 0) := to_signed(-3, 16);
                            w(r * 7 + 1) := to_signed(-2, 16);
                            w(r * 7 + 2) := to_signed(-1, 16);
                            w(r * 7 + 3) := to_signed(0, 16);
                            w(r * 7 + 4) := to_signed(1, 16);
                            w(r * 7 + 5) := to_signed(2, 16);
                            w(r * 7 + 6) := to_signed(3, 16);
                        END LOOP;
                        d := 1;

                    -- 011: Laplacian 7x7
                    WHEN "011" =>
                        FOR k IN 0 TO 48 LOOP
                            w(k) := to_signed(-1, 16);
                        END LOOP;
                        w(CENTER_ELEM) := to_signed(48, 16);
                        d := 1;

                    -- 100: Sharpening 7x7
                    WHEN "100" =>
                        FOR k IN 0 TO 48 LOOP
                            w(k) := to_signed(-1, 16);
                        END LOOP;
                        w(CENTER_ELEM) := to_signed(49, 16);
                        d := 1;

                    -- 101: Sobel Horizontal 7x7
                    WHEN "101" =>
                        FOR r IN 0 TO 6 LOOP
                            w(r * 7 + 0) := to_signed(-3, 16);
                            w(r * 7 + 1) := to_signed(-2, 16);
                            w(r * 7 + 2) := to_signed(-1, 16);
                            w(r * 7 + 3) := to_signed(0, 16);
                            w(r * 7 + 4) := to_signed(1, 16);
                            w(r * 7 + 5) := to_signed(2, 16);
                            w(r * 7 + 6) := to_signed(3, 16);
                        END LOOP;
                        -- Center row emphasis
                        w(3 * 7 + 0) := to_signed(-6, 16);
                        w(3 * 7 + 1) := to_signed(-4, 16);
                        w(3 * 7 + 2) := to_signed(-2, 16);
                        w(3 * 7 + 4) := to_signed(2, 16);
                        w(3 * 7 + 5) := to_signed(4, 16);
                        w(3 * 7 + 6) := to_signed(6, 16);
                        d := 1;

                    -- 110: Sobel Vertical 7x7
                    WHEN "110" =>
                        FOR c IN 0 TO 6 LOOP
                            w(0 * 7 + c) := to_signed(-3, 16);
                            w(1 * 7 + c) := to_signed(-2, 16);
                            w(2 * 7 + c) := to_signed(-1, 16);
                            w(3 * 7 + c) := to_signed(0, 16);
                            w(4 * 7 + c) := to_signed(1, 16);
                            w(5 * 7 + c) := to_signed(2, 16);
                            w(6 * 7 + c) := to_signed(3, 16);
                        END LOOP;
                        w(0 * 7 + 3) := to_signed(-6, 16);
                        w(1 * 7 + 3) := to_signed(-4, 16);
                        w(2 * 7 + 3) := to_signed(-2, 16);
                        w(4 * 7 + 3) := to_signed(2, 16);
                        w(5 * 7 + 3) := to_signed(4, 16);
                        w(6 * 7 + 3) := to_signed(6, 16);
                        d := 1;

                    -- 111: Custom / Gaussian 7x7
                    WHEN OTHERS =>
                        FOR k IN 0 TO 48 LOOP
                            w(k) := to_signed(2, 16);
                        END LOOP;
                        w(CENTER_ELEM) := to_signed(4, 16);
                        d := 100;
                END CASE;

        END CASE;

        WEIGHTS <= w;
        DIVISOR <= d;
    END PROCESS;

END ARCHITECTURE RTL;