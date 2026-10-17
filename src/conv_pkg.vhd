LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

--! @brief Image Convolution Core Package
--! @details Defines constants, data types, and conversion functions for multi-scale 2D image convolution (1x1 to 7x7).
PACKAGE conv_pkg IS

    CONSTANT MAX_KERNEL_SIZE  : INTEGER := 7;                                 --! Maximum kernel window dimension (7x7) supporting dynamic scaling
    CONSTANT MAX_KERNEL_ELEMS : INTEGER := MAX_KERNEL_SIZE * MAX_KERNEL_SIZE; --! Total element count in maximum 7x7 spatial filter window (49)
    CONSTANT CENTER_ROW       : INTEGER := 3;                                 --! Row index of the center kernel element (0-indexed)
    CONSTANT CENTER_COL       : INTEGER := 3;                                 --! Column index of the center kernel element (0-indexed)
    CONSTANT CENTER_ELEM      : INTEGER := 24;                                --! Linear flattened array index of the center pixel (3 * 7 + 3)

    CONSTANT KERNEL_SIZE      : INTEGER := MAX_KERNEL_SIZE;                   --! Backward-compatible alias for MAX_KERNEL_SIZE
    CONSTANT KERNEL_ELEMS     : INTEGER := MAX_KERNEL_ELEMS;                  --! Backward-compatible alias for MAX_KERNEL_ELEMS

    --! 8-bit unsigned pixel channel data type
    SUBTYPE byte_t IS UNSIGNED(7 DOWNTO 0);
    
    --! 24-bit RGB color pixel record containing individual 8-bit color channels
    TYPE rgb_pixel_t IS RECORD
        r : byte_t; --! 8-bit red color channel intensity
        g : byte_t; --! 8-bit green color channel intensity
        b : byte_t; --! 8-bit blue color channel intensity
    END RECORD;

    --! Flattened 49-element array representing one color channel across the 7x7 window
    TYPE window_channel_t IS ARRAY (0 TO MAX_KERNEL_ELEMS - 1) OF byte_t;

    --! Flattened 49-element array of signed 16-bit convolution kernel coefficients
    TYPE kernel_weights_t IS ARRAY (0 TO MAX_KERNEL_ELEMS - 1) OF SIGNED(15 DOWNTO 0);

    --! Unpacks a 24-bit std_logic_vector (R=23..16, G=15..8, B=7..0) into an rgb_pixel_t record
    FUNCTION slv_to_rgb(slv : STD_LOGIC_VECTOR(23 DOWNTO 0)) RETURN rgb_pixel_t;

    --! Packs an rgb_pixel_t record into a 24-bit std_logic_vector (R=23..16, G=15..8, B=7..0)
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
