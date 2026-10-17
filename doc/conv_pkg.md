# Package: conv_pkg

- **File:** conv_pkg.vhd
- **Brief:** Image Convolution Core Package
- **Details:** Defines constants, data types, and conversion functions for multi-scale 2D image convolution (1x1 to 7x7).

## Constants

| Name             | Type    | Value                              | Description                                                      |
| ---------------- | ------- | ---------------------------------- | ---------------------------------------------------------------- |
| MAX_KERNEL_SIZE  | INTEGER | 7                                  | Maximum kernel window dimension (7x7) supporting dynamic scaling |
| MAX_KERNEL_ELEMS | INTEGER | MAX_KERNEL_SIZE \* MAX_KERNEL_SIZE | Total element count in maximum 7x7 spatial filter window (49)    |
| CENTER_ROW       | INTEGER | 3                                  | Row index of the center kernel element (0-indexed)               |
| CENTER_COL       | INTEGER | 3                                  | Column index of the center kernel element (0-indexed)            |
| CENTER_ELEM      | INTEGER | 24                                 | Linear flattened array index of the center pixel (3 \* 7 + 3)    |
| KERNEL_SIZE      | INTEGER | MAX_KERNEL_SIZE                    | Backward-compatible alias for MAX_KERNEL_SIZE                    |
| KERNEL_ELEMS     | INTEGER | MAX_KERNEL_ELEMS                   | Backward-compatible alias for MAX_KERNEL_ELEMS                   |

## Types

| Name             | Description                                                                     |
| ---------------- | ------------------------------------------------------------------------------- |
| window_channel_t | Flattened 49-element array representing one color channel across the 7x7 window |
| kernel_weights_t | Flattened 49-element array of signed 16-bit convolution kernel coefficients     |

## Records

### _rgb_pixel_t_

24-bit RGB color pixel record containing individual 8-bit color channels

| Name | Type   | Description                         |
| ---- | ------ | ----------------------------------- |
| r    | byte_t | 8-bit red color channel intensity   |
| g    | byte_t | 8-bit green color channel intensity |
| b    | byte_t | 8-bit blue color channel intensity  |

## Functions

- slv_to_rgb
  - Unpacks a 24-bit std_logic_vector (R=23..16, G=15..8, B=7..0) into an rgb_pixel_t record
- rgb_to_slv
  - Packs an rgb_pixel_t record into a 24-bit std_logic_vector (R=23..16, G=15..8, B=7..0)

> R=23..16 means the red channel is stored in bits 23 down to 16 of the std_logic_vector, G=15..8 means the green channel is stored in bits 15 down to 8, and B=7..0 means the blue channel is stored in bits 7 down to 0.
