LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE STD.TEXTIO.ALL;
USE WORK.conv_pkg.ALL;

ENTITY tb_image_convolution IS
    GENERIC (
        G_IMG_WIDTH    : INTEGER := 100;
        G_IMG_HEIGHT   : INTEGER := 100;
        G_IN_FILE      : STRING  := "src/input.bmp";
        G_OUT_FILE     : STRING  := "sim/output_sim.bmp";
        G_INSTRUCTION  : STD_LOGIC_VECTOR(5 DOWNTO 0) := "010000" -- Default is 3x3 Box Blur ALU
    );
END ENTITY tb_image_convolution;

ARCHITECTURE BEH OF tb_image_convolution IS

    CONSTANT CLK_PERIOD : TIME := 10 ns; -- 100 MHz

    -- DUT signals
    SIGNAL clk             : STD_LOGIC := '0';
    SIGNAL reset           : STD_LOGIC := '1';
    SIGNAL enable          : STD_LOGIC := '0';
    SIGNAL instruction_raw : STD_LOGIC_VECTOR(5 DOWNTO 0) := G_INSTRUCTION;
    SIGNAL pixel_in        : STD_LOGIC_VECTOR(23 DOWNTO 0) := (OTHERS => '0');
    SIGNAL pixel_valid_in  : STD_LOGIC := '0';
    SIGNAL pixel_out       : STD_LOGIC_VECTOR(23 DOWNTO 0);
    SIGNAL pixel_valid_out : STD_LOGIC;
    SIGNAL busy            : STD_LOGIC;
    SIGNAL done            : STD_LOGIC;
    SIGNAL cycle_count     : UNSIGNED(31 DOWNTO 0);

    -- Simulation status flags
    SIGNAL sim_done        : BOOLEAN := FALSE;

    TYPE char_file IS FILE OF CHARACTER;
    FILE in_bmp_file  : char_file;
    FILE out_bmp_file : char_file;

    TYPE header_type IS ARRAY (0 TO 53) OF CHARACTER;
    SIGNAL bmp_header : header_type;

BEGIN

    -- 100 MHz Clock Generator
    clk_process : PROCESS
    BEGIN
        WHILE NOT sim_done LOOP
            clk <= '0';
            WAIT FOR CLK_PERIOD / 2;
            clk <= '1';
            WAIT FOR CLK_PERIOD / 2;
        END LOOP;
        WAIT;
    END PROCESS;

    -- DUT Instance
    DUT : ENTITY WORK.CPU
        GENERIC MAP (
            IMG_WIDTH  => G_IMG_WIDTH,
            IMG_HEIGHT => G_IMG_HEIGHT
        )
        PORT MAP (
            CLK             => clk,
            RESET           => reset,
            ENABLE          => enable,
            INSTRUCTION_RAW => instruction_raw,
            PIXEL_IN        => pixel_in,
            PIXEL_VALID_IN  => pixel_valid_in,
            PIXEL_OUT       => pixel_out,
            PIXEL_VALID_OUT => pixel_valid_out,
            BUSY            => busy,
            DONE            => done,
            CYCLE_COUNT     => cycle_count
        );

    driver_process : PROCESS
        VARIABLE ch_b, ch_g, ch_r : CHARACTER;
        VARIABLE dummy_ch         : CHARACTER;
        VARIABLE in_hdr           : header_type;
        VARIABLE in_pad           : INTEGER;
    BEGIN
        -- Open input BMP
        file_open(in_bmp_file, G_IN_FILE, read_mode);

        -- Read 54-byte BMP header
        FOR i IN 0 TO 53 LOOP
            read(in_bmp_file, in_hdr(i));
        END LOOP;
        bmp_header <= in_hdr;

        in_pad := (4 - (G_IMG_WIDTH * 3 MOD 4)) MOD 4;

        -- Apply hardware Reset
        reset  <= '1';
        enable <= '0';
        WAIT FOR 50 ns;
        WAIT UNTIL RISING_EDGE(clk);
        WAIT UNTIL RISING_EDGE(clk);
        reset <= '0';

        -- Start hardware accelerator
        WAIT UNTIL RISING_EDGE(clk);
        instruction_raw <= G_INSTRUCTION;
        enable          <= '1';

        -- Wait 2 cycles for decode
        WAIT UNTIL RISING_EDGE(clk);
        WAIT UNTIL RISING_EDGE(clk);

        REPORT "Streaming input pixels into hardware accelerator...";

        -- Stream pixels row by row, 1 pixel per clock cycle!
        FOR r IN 0 TO G_IMG_HEIGHT - 1 LOOP
            FOR c IN 0 TO G_IMG_WIDTH - 1 LOOP
                read(in_bmp_file, ch_b);
                read(in_bmp_file, ch_g);
                read(in_bmp_file, ch_r);

                pixel_in(7 DOWNTO 0)   <= STD_LOGIC_VECTOR(to_unsigned(CHARACTER'pos(ch_b), 8));
                pixel_in(15 DOWNTO 8)  <= STD_LOGIC_VECTOR(to_unsigned(CHARACTER'pos(ch_g), 8));
                pixel_in(23 DOWNTO 16) <= STD_LOGIC_VECTOR(to_unsigned(CHARACTER'pos(ch_r), 8));
                pixel_valid_in         <= '1';

                WAIT UNTIL RISING_EDGE(clk);
            END LOOP;

            -- Discard padding bytes in input file
            FOR p IN 1 TO in_pad LOOP
                read(in_bmp_file, dummy_ch);
            END LOOP;
        END LOOP;

        -- Input stream finished
        pixel_valid_in <= '0';
        pixel_in       <= (OTHERS => '0');
        file_close(in_bmp_file);

        REPORT "Input stream finished. Awaiting hardware pipeline completion...";

        -- Wait for hardware DONE flag
        WAIT UNTIL done = '1';
        WAIT UNTIL RISING_EDGE(clk);
        WAIT FOR 100 ns;

        sim_done <= TRUE;
        WAIT;
    END PROCESS;

    -- Output Collector (Receives filtered pixels cycle-by-cycle and writes output BMP)
    collector_process : PROCESS
        VARIABLE out_hdr   : header_type;
        VARIABLE out_pad   : INTEGER;
        VARIABLE col_count : INTEGER := 0;
        VARIABLE px_count  : INTEGER := 0;
    BEGIN
        out_pad := (4 - (G_IMG_WIDTH * 3 MOD 4)) MOD 4;

        -- Wait for header to be read by driver
        WAIT UNTIL bmp_header(0) = 'B';
        file_open(out_bmp_file, G_OUT_FILE, write_mode);

        -- Write BMP header
        FOR i IN 0 TO 53 LOOP
            write(out_bmp_file, bmp_header(i));
        END LOOP;

        WHILE NOT sim_done LOOP
            WAIT UNTIL RISING_EDGE(clk);
            IF pixel_valid_out = '1' THEN
                -- Write Blue, Green, Red
                write(out_bmp_file, CHARACTER'val(to_integer(unsigned(pixel_out(7 DOWNTO 0)))));
                write(out_bmp_file, CHARACTER'val(to_integer(unsigned(pixel_out(15 DOWNTO 8)))));
                write(out_bmp_file, CHARACTER'val(to_integer(unsigned(pixel_out(23 DOWNTO 16)))));

                px_count  := px_count + 1;
                col_count := col_count + 1;

                IF col_count = G_IMG_WIDTH THEN
                    -- Write padding if necessary
                    FOR p IN 1 TO out_pad LOOP
                        write(out_bmp_file, CHARACTER'val(0));
                    END LOOP;
                    col_count := 0;
                END IF;
            END IF;
        END LOOP;

        file_close(out_bmp_file);

        REPORT "Hardware pipeline completed. Here are the results...";
        REPORT "Total Output Pixels Collected: " & INTEGER'image(px_count);
        REPORT "Total Hardware Execution Cycles: " & INTEGER'image(to_integer(cycle_count));

        WAIT;
    END PROCESS;

END ARCHITECTURE BEH;
