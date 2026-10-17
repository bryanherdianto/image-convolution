LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE WORK.conv_pkg.ALL;

-- =============================================================================
-- Top-Level Synthesizable Image Convolution Hardware Accelerator (CPU)
-- Integrates:
--   - 6-Bit Dynamic Instruction Decoder (Radius R=0..3, Unit Select, Filter Opcode)
--   - Dynamic Multi-Scale Dual/Multi-Row Line Buffer & Window Generator
--   - 49-Multiplier Direct Spatial Convolution ALU
--   - 49-Element Systolic Matrix Multiplier MMU
--   - Hardware Performance Cycle Counter & Master FSM
-- =============================================================================

ENTITY CPU IS
    GENERIC (
        IMG_WIDTH  : INTEGER := 1000;
        IMG_HEIGHT : INTEGER := 1000
    );
    PORT (
        CLK             : IN  STD_LOGIC;
        RESET           : IN  STD_LOGIC;
        ENABLE          : IN  STD_LOGIC;
        INSTRUCTION_RAW : IN  STD_LOGIC_VECTOR(5 DOWNTO 0);
        -- Streaming pixel interface
        PIXEL_IN        : IN  STD_LOGIC_VECTOR(23 DOWNTO 0);
        PIXEL_VALID_IN  : IN  STD_LOGIC;
        PIXEL_OUT       : OUT STD_LOGIC_VECTOR(23 DOWNTO 0);
        PIXEL_VALID_OUT : OUT STD_LOGIC;
        BUSY            : OUT STD_LOGIC;
        DONE            : OUT STD_LOGIC;
        CYCLE_COUNT     : OUT UNSIGNED(31 DOWNTO 0)
    );
END ENTITY CPU;

ARCHITECTURE RTL OF CPU IS

    CONSTANT TOTAL_PIXELS : INTEGER := IMG_WIDTH * IMG_HEIGHT;

    -- Subcomponents
    COMPONENT DECODER IS
        PORT (
            INSTRUCTION  : IN  STD_LOGIC_VECTOR(5 DOWNTO 0);
            OPCODE       : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
            RADIUS       : OUT INTEGER RANGE 0 TO 3;
            UNIT_SELECT  : OUT STD_LOGIC;
            WEIGHTS      : OUT kernel_weights_t;
            DIVISOR      : OUT INTEGER RANGE 1 TO 256
        );
    END COMPONENT DECODER;

    COMPONENT LINE_BUFFER IS
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
    END COMPONENT LINE_BUFFER;

    COMPONENT ALU IS
        PORT (
            CLK             : IN  STD_LOGIC;
            RST             : IN  STD_LOGIC;
            ENABLE_ALU      : IN  STD_LOGIC;
            WINDOW_R        : IN  window_channel_t;
            WINDOW_G        : IN  window_channel_t;
            WINDOW_B        : IN  window_channel_t;
            WINDOW_VALID    : IN  STD_LOGIC;
            WEIGHTS         : IN  kernel_weights_t;
            DIVISOR         : IN  INTEGER RANGE 1 TO 256;
            PIXEL_OUT       : OUT STD_LOGIC_VECTOR(23 DOWNTO 0);
            PIXEL_VALID_OUT : OUT STD_LOGIC
        );
    END COMPONENT ALU;

    COMPONENT MMU IS
        PORT (
            CLK             : IN  STD_LOGIC;
            RST             : IN  STD_LOGIC;
            ENABLE_MMU      : IN  STD_LOGIC;
            WINDOW_R        : IN  window_channel_t;
            WINDOW_G        : IN  window_channel_t;
            WINDOW_B        : IN  window_channel_t;
            WINDOW_VALID    : IN  STD_LOGIC;
            WEIGHTS         : IN  kernel_weights_t;
            DIVISOR         : IN  INTEGER RANGE 1 TO 256;
            PIXEL_OUT       : OUT STD_LOGIC_VECTOR(23 DOWNTO 0);
            PIXEL_VALID_OUT : OUT STD_LOGIC
        );
    END COMPONENT MMU;

    -- State Machine
    TYPE state_t IS (ST_IDLE, ST_RUN, ST_COMPLETE);
    SIGNAL state : state_t := ST_IDLE;

    -- Internal Signals
    SIGNAL opcode         : STD_LOGIC_VECTOR(2 DOWNTO 0);
    SIGNAL radius         : INTEGER RANGE 0 TO 3 := 0;
    SIGNAL unit_select    : STD_LOGIC;
    SIGNAL weights        : kernel_weights_t;
    SIGNAL divisor        : INTEGER RANGE 1 TO 256;

    SIGNAL window_r       : window_channel_t := (OTHERS => (OTHERS => '0'));
    SIGNAL window_g       : window_channel_t := (OTHERS => (OTHERS => '0'));
    SIGNAL window_b       : window_channel_t := (OTHERS => (OTHERS => '0'));
    SIGNAL window_valid   : STD_LOGIC := '0';
    SIGNAL lb_frame_done  : STD_LOGIC := '0';
    SIGNAL lb_busy        : STD_LOGIC := '0';

    SIGNAL enable_alu     : STD_LOGIC := '0';
    SIGNAL alu_pixel_out  : STD_LOGIC_VECTOR(23 DOWNTO 0) := (OTHERS => '0');
    SIGNAL alu_valid_out  : STD_LOGIC := '0';

    SIGNAL enable_mmu     : STD_LOGIC := '0';
    SIGNAL mmu_pixel_out  : STD_LOGIC_VECTOR(23 DOWNTO 0) := (OTHERS => '0');
    SIGNAL mmu_valid_out  : STD_LOGIC := '0';

    SIGNAL cycle_cnt      : UNSIGNED(31 DOWNTO 0) := (OTHERS => '0');
    SIGNAL out_count      : INTEGER RANGE 0 TO TOTAL_PIXELS := 0;

BEGIN

    -- Instantaneous Combinational Decoder
    U_DECODER : DECODER
        PORT MAP (
            INSTRUCTION  => INSTRUCTION_RAW,
            OPCODE       => opcode,
            RADIUS       => radius,
            UNIT_SELECT  => unit_select,
            WEIGHTS      => weights,
            DIVISOR      => divisor
        );

    -- Dynamic Multi-Scale Line Buffer & Window Generator
    U_LINE_BUFFER : LINE_BUFFER
        GENERIC MAP (
            IMG_WIDTH  => IMG_WIDTH,
            IMG_HEIGHT => IMG_HEIGHT
        )
        PORT MAP (
            CLK          => CLK,
            RST          => RESET,
            RADIUS       => radius,
            VALID_IN     => PIXEL_VALID_IN,
            PIXEL_IN     => PIXEL_IN,
            WINDOW_R     => window_r,
            WINDOW_G     => window_g,
            WINDOW_B     => window_b,
            WINDOW_VALID => window_valid,
            FRAME_DONE   => lb_frame_done,
            BUSY         => lb_busy
        );

    -- ALU (Direct 2D Spatial Convolution Accelerator)
    U_ALU : ALU
        PORT MAP (
            CLK             => CLK,
            RST             => RESET,
            ENABLE_ALU      => enable_alu,
            WINDOW_R        => window_r,
            WINDOW_G        => window_g,
            WINDOW_B        => window_b,
            WINDOW_VALID    => window_valid,
            WEIGHTS         => weights,
            DIVISOR         => divisor,
            PIXEL_OUT       => alu_pixel_out,
            PIXEL_VALID_OUT => alu_valid_out
        );

    -- MMU (Systolic Matrix Multiplier Accelerator)
    U_MMU : MMU
        PORT MAP (
            CLK             => CLK,
            RST             => RESET,
            ENABLE_MMU      => enable_mmu,
            WINDOW_R        => window_r,
            WINDOW_G        => window_g,
            WINDOW_B        => window_b,
            WINDOW_VALID    => window_valid,
            WEIGHTS         => weights,
            DIVISOR         => divisor,
            PIXEL_OUT       => mmu_pixel_out,
            PIXEL_VALID_OUT => mmu_valid_out
        );

    -- Accelerator Output Multiplexer
    PIXEL_OUT       <= mmu_pixel_out WHEN unit_select = '1' ELSE alu_pixel_out;
    PIXEL_VALID_OUT <= mmu_valid_out WHEN unit_select = '1' ELSE alu_valid_out;
    CYCLE_COUNT     <= cycle_cnt;

    -- Control FSM & Performance Cycle Counter
    PROCESS (CLK)
        VARIABLE cur_valid_out : STD_LOGIC;
    BEGIN
        IF RISING_EDGE(CLK) THEN
            IF RESET = '1' THEN
                state      <= ST_IDLE;
                enable_alu <= '0';
                enable_mmu <= '0';
                cycle_cnt  <= (OTHERS => '0');
                out_count  <= 0;
                BUSY       <= '0';
                DONE       <= '0';
            ELSE
                IF unit_select = '1' THEN
                    cur_valid_out := mmu_valid_out;
                ELSE
                    cur_valid_out := alu_valid_out;
                END IF;

                CASE state IS
                    WHEN ST_IDLE =>
                        DONE      <= '0';
                        BUSY      <= '0';
                        out_count <= 0;

                        IF ENABLE = '1' THEN
                            state     <= ST_RUN;
                            BUSY      <= '1';
                            cycle_cnt <= (OTHERS => '0');
                            IF unit_select = '1' THEN
                                enable_mmu <= '1';
                                enable_alu <= '0';
                            ELSE
                                enable_alu <= '1';
                                enable_mmu <= '0';
                            END IF;
                        ELSE
                            enable_alu <= '0';
                            enable_mmu <= '0';
                        END IF;

                    WHEN ST_RUN =>
                        BUSY      <= '1';
                        cycle_cnt <= cycle_cnt + 1;

                        IF cur_valid_out = '1' THEN
                            IF out_count = TOTAL_PIXELS - 1 THEN
                                state      <= ST_COMPLETE;
                                enable_alu <= '0';
                                enable_mmu <= '0';
                            ELSE
                                out_count <= out_count + 1;
                            END IF;
                        END IF;

                    WHEN ST_COMPLETE =>
                        BUSY <= '0';
                        DONE <= '1';
                        IF ENABLE = '0' THEN
                            state <= ST_IDLE;
                            DONE  <= '0';
                        END IF;

                END CASE;
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE RTL;