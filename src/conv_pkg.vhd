LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

PACKAGE conv_pkg IS

    -- Maximum kernel size (7x7) to support dynamic 1x1, 3x3, 5x5, 7x7
    CONSTANT MAX_KERNEL_SIZE  : INTEGER := 7;
    CONSTANT MAX_KERNEL_ELEMS : INTEGER := MAX_KERNEL_SIZE * MAX_KERNEL_SIZE; -- 49
    CONSTANT CENTER_ROW       : INTEGER := 3;
    CONSTANT CENTER_COL       : INTEGER := 3;
    CONSTANT CENTER_ELEM      : INTEGER := 24; -- 3 * 7 + 3

    -- Backward-compatible aliases
    CONSTANT KERNEL_SIZE      : INTEGER := MAX_KERNEL_SIZE;
    CONSTANT KERNEL_ELEMS     : INTEGER := MAX_KERNEL_ELEMS;

    -- 8-bit color channels
    SUBTYPE byte_t IS UNSIGNED(7 DOWNTO 0);
    
    -- 24-bit RGB pixel record
    TYPE rgb_pixel_t IS RECORD
        r : byte_t;
        g : byte_t;
        b : byte_t;
    END RECORD;

    -- Array of 49 bytes for one color channel across the 7x7 window
    TYPE window_channel_t IS ARRAY (0 TO MAX_KERNEL_ELEMS - 1) OF byte_t;

    -- Array of 49 signed weights for kernel coefficients
    TYPE kernel_weights_t IS ARRAY (0 TO MAX_KERNEL_ELEMS - 1) OF SIGNED(15 DOWNTO 0);

    -- Helper functions to pack/unpack 24-bit std_logic_vector
    FUNCTION slv_to_rgb(slv : STD_LOGIC_VECTOR(23 DOWNTO 0)) RETURN rgb_pixel_t;
    FUNCTION rgb_to_slv(rgb : rgb_pixel_t) RETURN STD_LOGIC_VECTOR;

END PACKAGE conv_pkg;

PACKAGE BODY conv_pkg IS

    FUNCTION slv_to_rgb(slv : STD_LOGIC_VECTOR(23 DOWNTO 0)) RETURN rgb_pixel_t IS
        VARIABLE res : rgb_pixel_t;
    BEGIN
        res.b := UNSIGNED(slv(7 DOWNTO 0));
        res.g := UNSIGNED(slv(15 DOWNTO 8));
        res.r := UNSIGNED(slv(23 DOWNTO 16));
        RETURN res;
    END FUNCTION;

    FUNCTION rgb_to_slv(rgb : rgb_pixel_t) RETURN STD_LOGIC_VECTOR IS
        VARIABLE res : STD_LOGIC_VECTOR(23 DOWNTO 0);
    BEGIN
        res(7 DOWNTO 0)   := STD_LOGIC_VECTOR(rgb.b);
        res(15 DOWNTO 8)  := STD_LOGIC_VECTOR(rgb.g);
        res(23 DOWNTO 16) := STD_LOGIC_VECTOR(rgb.r);
        RETURN res;
    END FUNCTION;

END PACKAGE BODY conv_pkg;
