LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE WORK.conv_pkg.ALL;

-- =============================================================================
-- Dynamic Multi-Scale Line Buffer & Window Generator
-- Houses 6 on-chip Block RAM line buffers and a 7x7 window register array.
-- Dynamically supports:
--   Radius R = 0 (1x1 Identity / Passthrough)
--   Radius R = 1 (3x3 Kernel)
--   Radius R = 2 (5x5 Kernel)
--   Radius R = 3 (7x7 Kernel)
-- Center pixel latency is uniformly 3 * IMG_WIDTH + 3 for all modes,
-- guaranteeing glitch-free video streaming and identical phase alignment.
-- =============================================================================

ENTITY LINE_BUFFER IS
    GENERIC (
        IMG_WIDTH  : INTEGER := 1000;
        IMG_HEIGHT : INTEGER := 1000
    );
    PORT (
        CLK          : IN  STD_LOGIC;
        RST          : IN  STD_LOGIC;
        RADIUS       : IN  INTEGER RANGE 0 TO 3;
        VALID_IN     : IN  STD_LOGIC;
        PIXEL_IN     : IN  STD_LOGIC_VECTOR(23 DOWNTO 0);
        WINDOW_R     : OUT window_channel_t;
        WINDOW_G     : OUT window_channel_t;
        WINDOW_B     : OUT window_channel_t;
        WINDOW_VALID : OUT STD_LOGIC;
        FRAME_DONE   : OUT STD_LOGIC;
        BUSY         : OUT STD_LOGIC
    );
END ENTITY LINE_BUFFER;

ARCHITECTURE RTL OF LINE_BUFFER IS

    CONSTANT TOTAL_PIXELS   : INTEGER := IMG_WIDTH * IMG_HEIGHT;
    CONSTANT CENTER_LATENCY : INTEGER := 3 * IMG_WIDTH + 4;
    CONSTANT FLUSH_CYCLES   : INTEGER := 3 * IMG_WIDTH + 6;

    -- 6 Line Buffers implemented via BRAM / M10K blocks
    TYPE line_ram_t IS ARRAY (0 TO IMG_WIDTH - 1) OF rgb_pixel_t;
    SIGNAL line_ram_0 : line_ram_t := (OTHERS => (r => (OTHERS => '0'), g => (OTHERS => '0'), b => (OTHERS => '0')));
    SIGNAL line_ram_1 : line_ram_t := (OTHERS => (r => (OTHERS => '0'), g => (OTHERS => '0'), b => (OTHERS => '0')));
    SIGNAL line_ram_2 : line_ram_t := (OTHERS => (r => (OTHERS => '0'), g => (OTHERS => '0'), b => (OTHERS => '0')));
    SIGNAL line_ram_3 : line_ram_t := (OTHERS => (r => (OTHERS => '0'), g => (OTHERS => '0'), b => (OTHERS => '0')));
    SIGNAL line_ram_4 : line_ram_t := (OTHERS => (r => (OTHERS => '0'), g => (OTHERS => '0'), b => (OTHERS => '0')));
    SIGNAL line_ram_5 : line_ram_t := (OTHERS => (r => (OTHERS => '0'), g => (OTHERS => '0'), b => (OTHERS => '0')));

    -- Pointers and Counters
    SIGNAL ram_ptr     : INTEGER RANGE 0 TO IMG_WIDTH - 1 := 0;
    SIGNAL in_count    : INTEGER RANGE 0 TO TOTAL_PIXELS + FLUSH_CYCLES := 0;
    SIGNAL flush_count : INTEGER RANGE 0 TO FLUSH_CYCLES := 0;
    SIGNAL out_count   : INTEGER RANGE 0 TO TOTAL_PIXELS := 0;
    SIGNAL out_col     : INTEGER RANGE 0 TO IMG_WIDTH - 1 := 0;
    SIGNAL out_row     : INTEGER RANGE 0 TO IMG_HEIGHT - 1 := 0;

    -- State Machine
    TYPE state_t IS (ST_IDLE, ST_STREAM, ST_FLUSH, ST_DONE);
    SIGNAL state : state_t := ST_IDLE;

    -- 7x7 Window Shift Registers: win_reg(row, col)
    TYPE win_reg_t IS ARRAY (0 TO 6, 0 TO 6) OF rgb_pixel_t;
    SIGNAL win_reg : win_reg_t := (OTHERS => (OTHERS => (r => (OTHERS => '0'), g => (OTHERS => '0'), b => (OTHERS => '0'))));

BEGIN

    PROCESS (CLK)
        VARIABLE cur_px        : rgb_pixel_t;
        VARIABLE px_zero       : rgb_pixel_t;
        VARIABLE r_px          : win_reg_t; -- Row taps
        VARIABLE r0, r1, r2    : rgb_pixel_t;
        VARIABLE r3, r4, r5    : rgb_pixel_t;
        VARIABLE r6            : rgb_pixel_t;
        VARIABLE img_r, img_c  : INTEGER;
        VARIABLE w_r, w_g, w_b : window_channel_t;
    BEGIN
        IF RISING_EDGE(CLK) THEN
            IF RST = '1' THEN
                state        <= ST_IDLE;
                ram_ptr      <= 0;
                in_count     <= 0;
                flush_count  <= 0;
                out_count    <= 0;
                out_col      <= 0;
                out_row      <= 0;
                WINDOW_VALID <= '0';
                FRAME_DONE   <= '0';
                BUSY         <= '0';
                win_reg      <= (OTHERS => (OTHERS => (r => (OTHERS => '0'), g => (OTHERS => '0'), b => (OTHERS => '0'))));
            ELSE
                px_zero.r := (OTHERS => '0');
                px_zero.g := (OTHERS => '0');
                px_zero.b := (OTHERS => '0');

                CASE state IS
                    ------------------------------------------------------------
                    -- IDLE: Waiting for first pixel
                    ------------------------------------------------------------
                    WHEN ST_IDLE =>
                        WINDOW_VALID <= '0';
                        FRAME_DONE   <= '0';
                        BUSY         <= '0';
                        ram_ptr      <= 0;
                        in_count     <= 0;
                        flush_count  <= 0;
                        out_count    <= 0;
                        out_col      <= 0;
                        out_row      <= 0;

                        IF VALID_IN = '1' THEN
                            state  <= ST_STREAM;
                            BUSY   <= '1';
                            cur_px := slv_to_rgb(PIXEL_IN);

                            -- Read line buffers at ptr 0
                            r5 := line_ram_5(0);
                            r4 := line_ram_4(0);
                            r3 := line_ram_3(0);
                            r2 := line_ram_2(0);
                            r1 := line_ram_1(0);
                            r0 := line_ram_0(0);
                            r6 := cur_px;

                            -- Write line buffers cascaded
                            line_ram_5(0) <= line_ram_4(0);
                            line_ram_4(0) <= line_ram_3(0);
                            line_ram_3(0) <= line_ram_2(0);
                            line_ram_2(0) <= line_ram_1(0);
                            line_ram_1(0) <= line_ram_0(0);
                            line_ram_0(0) <= cur_px;

                            ram_ptr  <= 1;
                            in_count <= 1;

                            -- Shift into 7x7 window registers
                            FOR r IN 0 TO 6 LOOP
                                FOR c IN 0 TO 5 LOOP
                                    win_reg(r, c) <= win_reg(r, c + 1);
                                END LOOP;
                            END LOOP;
                            win_reg(0, 6) <= r5;
                            win_reg(1, 6) <= r4;
                            win_reg(2, 6) <= r3;
                            win_reg(3, 6) <= r2; -- Center Row
                            win_reg(4, 6) <= r1;
                            win_reg(5, 6) <= r0;
                            win_reg(6, 6) <= r6;
                        END IF;

                    ------------------------------------------------------------
                    -- STREAM: Streaming active image pixels
                    ------------------------------------------------------------
                    WHEN ST_STREAM =>
                        BUSY <= '1';
                        IF VALID_IN = '1' THEN
                            cur_px := slv_to_rgb(PIXEL_IN);

                            -- Read cascaded line buffers at current pointer
                            r5 := line_ram_5(ram_ptr);
                            r4 := line_ram_4(ram_ptr);
                            r3 := line_ram_3(ram_ptr);
                            r2 := line_ram_2(ram_ptr);
                            r1 := line_ram_1(ram_ptr);
                            r0 := line_ram_0(ram_ptr);
                            r6 := cur_px;

                            -- Write cascaded line buffers
                            line_ram_5(ram_ptr) <= line_ram_4(ram_ptr);
                            line_ram_4(ram_ptr) <= line_ram_3(ram_ptr);
                            line_ram_3(ram_ptr) <= line_ram_2(ram_ptr);
                            line_ram_2(ram_ptr) <= line_ram_1(ram_ptr);
                            line_ram_1(ram_ptr) <= line_ram_0(ram_ptr);
                            line_ram_0(ram_ptr) <= cur_px;

                            -- Advance RAM pointer
                            IF ram_ptr = IMG_WIDTH - 1 THEN
                                ram_ptr <= 0;
                            ELSE
                                ram_ptr <= ram_ptr + 1;
                            END IF;

                            -- Shift into 7x7 window registers
                            FOR r IN 0 TO 6 LOOP
                                FOR c IN 0 TO 5 LOOP
                                    win_reg(r, c) <= win_reg(r, c + 1);
                                END LOOP;
                            END LOOP;
                            win_reg(0, 6) <= r5;
                            win_reg(1, 6) <= r4;
                            win_reg(2, 6) <= r3;
                            win_reg(3, 6) <= r2;
                            win_reg(4, 6) <= r1;
                            win_reg(5, 6) <= r0;
                            win_reg(6, 6) <= r6;

                            -- Check if center pixel latency has been reached
                            IF in_count >= CENTER_LATENCY THEN
                                WINDOW_VALID <= '1';

                                -- Extract 7x7 window with boundary zero-padding & radius masking
                                FOR r IN 0 TO 6 LOOP
                                    FOR c IN 0 TO 6 LOOP
                                        img_r := out_row + (r - 3);
                                        img_c := out_col + (c - 3);

                                        IF (r - 3 < -RADIUS) OR (r - 3 > RADIUS) OR
                                           (c - 3 < -RADIUS) OR (c - 3 > RADIUS) THEN
                                            -- Outside active kernel radius: mask with zero
                                            w_r(r * 7 + c) := (OTHERS => '0');
                                            w_g(r * 7 + c) := (OTHERS => '0');
                                            w_b(r * 7 + c) := (OTHERS => '0');
                                        ELSIF (img_r < 0) OR (img_r >= IMG_HEIGHT) OR
                                              (img_c < 0) OR (img_c >= IMG_WIDTH) THEN
                                            -- Border padding: inside radius, but outside image bounds
                                            w_r(r * 7 + c) := (OTHERS => '0');
                                            w_g(r * 7 + c) := (OTHERS => '0');
                                            w_b(r * 7 + c) := (OTHERS => '0');
                                        ELSE
                                            w_r(r * 7 + c) := win_reg(r, c).r;
                                            w_g(r * 7 + c) := win_reg(r, c).g;
                                            w_b(r * 7 + c) := win_reg(r, c).b;
                                        END IF;
                                    END LOOP;
                                END LOOP;

                                WINDOW_R <= w_r;
                                WINDOW_G <= w_g;
                                WINDOW_B <= w_b;

                                -- Advance output coordinate tracker
                                IF out_col = IMG_WIDTH - 1 THEN
                                    out_col <= 0;
                                    IF out_row = IMG_HEIGHT - 1 THEN
                                        out_row <= 0;
                                    ELSE
                                        out_row <= out_row + 1;
                                    END IF;
                                ELSE
                                    out_col <= out_col + 1;
                                END IF;
                                out_count <= out_count + 1;
                            ELSE
                                WINDOW_VALID <= '0';
                            END IF;

                            IF in_count = TOTAL_PIXELS - 1 THEN
                                state <= ST_FLUSH;
                            ELSE
                                in_count <= in_count + 1;
                            END IF;

                        ELSE
                            WINDOW_VALID <= '0';
                        END IF;

                    ------------------------------------------------------------
                    -- FLUSH: Feeding zeros to flush remaining rows through center
                    ------------------------------------------------------------
                    WHEN ST_FLUSH =>
                        BUSY <= '1';
                        cur_px := px_zero;

                        r5 := line_ram_5(ram_ptr);
                        r4 := line_ram_4(ram_ptr);
                        r3 := line_ram_3(ram_ptr);
                        r2 := line_ram_2(ram_ptr);
                        r1 := line_ram_1(ram_ptr);
                        r0 := line_ram_0(ram_ptr);
                        r6 := cur_px;

                        line_ram_5(ram_ptr) <= line_ram_4(ram_ptr);
                        line_ram_4(ram_ptr) <= line_ram_3(ram_ptr);
                        line_ram_3(ram_ptr) <= line_ram_2(ram_ptr);
                        line_ram_2(ram_ptr) <= line_ram_1(ram_ptr);
                        line_ram_1(ram_ptr) <= line_ram_0(ram_ptr);
                        line_ram_0(ram_ptr) <= cur_px;

                        IF ram_ptr = IMG_WIDTH - 1 THEN
                            ram_ptr <= 0;
                        ELSE
                            ram_ptr <= ram_ptr + 1;
                        END IF;

                        FOR r IN 0 TO 6 LOOP
                            FOR c IN 0 TO 5 LOOP
                                win_reg(r, c) <= win_reg(r, c + 1);
                            END LOOP;
                        END LOOP;
                        win_reg(0, 6) <= r5;
                        win_reg(1, 6) <= r4;
                        win_reg(2, 6) <= r3;
                        win_reg(3, 6) <= r2;
                        win_reg(4, 6) <= r1;
                        win_reg(5, 6) <= r0;
                        win_reg(6, 6) <= r6;

                        WINDOW_VALID <= '1';

                        FOR r IN 0 TO 6 LOOP
                            FOR c IN 0 TO 6 LOOP
                                img_r := out_row + (r - 3);
                                img_c := out_col + (c - 3);

                                IF (r - 3 < -RADIUS) OR (r - 3 > RADIUS) OR
                                   (c - 3 < -RADIUS) OR (c - 3 > RADIUS) THEN
                                    w_r(r * 7 + c) := (OTHERS => '0');
                                    w_g(r * 7 + c) := (OTHERS => '0');
                                    w_b(r * 7 + c) := (OTHERS => '0');
                                ELSIF (img_r < 0) OR (img_r >= IMG_HEIGHT) OR
                                      (img_c < 0) OR (img_c >= IMG_WIDTH) THEN
                                    w_r(r * 7 + c) := (OTHERS => '0');
                                    w_g(r * 7 + c) := (OTHERS => '0');
                                    w_b(r * 7 + c) := (OTHERS => '0');
                                ELSE
                                    w_r(r * 7 + c) := win_reg(r, c).r;
                                    w_g(r * 7 + c) := win_reg(r, c).g;
                                    w_b(r * 7 + c) := win_reg(r, c).b;
                                END IF;
                            END LOOP;
                        END LOOP;

                        WINDOW_R <= w_r;
                        WINDOW_G <= w_g;
                        WINDOW_B <= w_b;

                        IF out_col = IMG_WIDTH - 1 THEN
                            out_col <= 0;
                            IF out_row = IMG_HEIGHT - 1 THEN
                                out_row <= 0;
                            ELSE
                                out_row <= out_row + 1;
                            END IF;
                        ELSE
                            out_col <= out_col + 1;
                        END IF;

                        IF out_count = TOTAL_PIXELS - 1 THEN
                            state      <= ST_DONE;
                            FRAME_DONE <= '1';
                        ELSE
                            out_count <= out_count + 1;
                        END IF;

                    ------------------------------------------------------------
                    -- DONE: Completed frame
                    ------------------------------------------------------------
                    WHEN ST_DONE =>
                        WINDOW_VALID <= '0';
                        FRAME_DONE   <= '1';
                        BUSY         <= '0';
                END CASE;
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE RTL;
