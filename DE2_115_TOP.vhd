--
-- DE2-115 top-level module (entity declaration)
--
-- William H. Robinson, Vanderbilt University University
--   william.h.robinson@vanderbilt.edu
--
-- Updated from the DE2 top-level module created by 
-- Stephen A. Edwards, Columbia University, sedwards@cs.columbia.edu
--

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY DE2_115_TOP IS
    GENERIC (
        TICKS_PER_SECOND : NATURAL := 50_000_000 -- default for 50 MHz CLOCK_50
    );
    PORT (
        -- Clocks

        CLOCK_50 : IN STD_LOGIC; -- 50 MHz
        CLOCK2_50 : IN STD_LOGIC; -- 50 MHz
        CLOCK3_50 : IN STD_LOGIC; -- 50 MHz
        SMA_CLKIN : IN STD_LOGIC; -- External Clock Input
        SMA_CLKOUT : OUT STD_LOGIC; -- External Clock Output

        -- Buttons and switches

        KEY : IN STD_LOGIC_VECTOR(3 DOWNTO 0); -- Push buttons
        SW : IN STD_LOGIC_VECTOR(17 DOWNTO 0); -- DPDT switches

        -- LED displays

        HEX0 : OUT STD_LOGIC_VECTOR(6 DOWNTO 0); -- 7-segment display (active low)
        HEX1 : OUT STD_LOGIC_VECTOR(6 DOWNTO 0); -- 7-segment display (active low)
        HEX2 : OUT STD_LOGIC_VECTOR(6 DOWNTO 0); -- 7-segment display (active low)
        HEX3 : OUT STD_LOGIC_VECTOR(6 DOWNTO 0); -- 7-segment display (active low)
        HEX4 : OUT STD_LOGIC_VECTOR(6 DOWNTO 0); -- 7-segment display (active low)
        HEX5 : OUT STD_LOGIC_VECTOR(6 DOWNTO 0); -- 7-segment display (active low)
        HEX6 : OUT STD_LOGIC_VECTOR(6 DOWNTO 0); -- 7-segment display (active low)
        HEX7 : OUT STD_LOGIC_VECTOR(6 DOWNTO 0); -- 7-segment display (active low)
        LEDG : OUT STD_LOGIC_VECTOR(8 DOWNTO 0); -- Green LEDs (active high)
        LEDR : OUT STD_LOGIC_VECTOR(17 DOWNTO 0); -- Red LEDs (active high)

        -- RS-232 interface

        UART_CTS : OUT STD_LOGIC; -- UART Clear to Send   
        UART_RTS : IN STD_LOGIC; -- UART Request to Send   
        UART_RXD : IN STD_LOGIC; -- UART Receiver
        UART_TXD : OUT STD_LOGIC; -- UART Transmitter   

        -- 16 X 2 LCD Module

        LCD_BLON : OUT STD_LOGIC; -- Back Light ON/OFF
        LCD_EN : OUT STD_LOGIC; -- Enable
        LCD_ON : OUT STD_LOGIC; -- Power ON/OFF
        LCD_RS : OUT STD_LOGIC; -- Command/Data Select, 0 = Command, 1 = Data
        LCD_RW : OUT STD_LOGIC; -- Read/Write Select, 0 = Write, 1 = Read
        LCD_DATA : INOUT STD_LOGIC_VECTOR(7 DOWNTO 0); -- Data bus 8 bits

        -- PS/2 ports

        PS2_CLK : INOUT STD_LOGIC; -- Clock
        PS2_DAT : INOUT STD_LOGIC; -- Data

        PS2_CLK2 : INOUT STD_LOGIC; -- Clock
        PS2_DAT2 : INOUT STD_LOGIC; -- Data

        -- VGA output

        VGA_BLANK_N : OUT STD_LOGIC; -- BLANK
        VGA_CLK : OUT STD_LOGIC; -- Clock
        VGA_HS : OUT STD_LOGIC; -- H_SYNC
        VGA_SYNC_N : OUT STD_LOGIC; -- SYNC
        VGA_VS : OUT STD_LOGIC; -- V_SYNC
        VGA_R : OUT STD_LOGIC_VECTOR(7 DOWNTO 0); -- Red[9:0]
        VGA_G : OUT STD_LOGIC_VECTOR(7 DOWNTO 0); -- Green[9:0]
        VGA_B : OUT STD_LOGIC_VECTOR(7 DOWNTO 0); -- Blue[9:0]

        -- SRAM

        SRAM_ADDR : OUT unsigned(19 DOWNTO 0); -- Address bus 20 Bits
        SRAM_DQ : INOUT unsigned(15 DOWNTO 0); -- Data bus 16 Bits
        SRAM_CE_N : OUT STD_LOGIC; -- Chip Enable
        SRAM_LB_N : OUT STD_LOGIC; -- Low-byte Data Mask 
        SRAM_OE_N : OUT STD_LOGIC; -- Output Enable
        SRAM_UB_N : OUT STD_LOGIC; -- High-byte Data Mask 
        SRAM_WE_N : OUT STD_LOGIC; -- Write Enable

        -- Audio CODEC

        AUD_ADCDAT : IN STD_LOGIC; -- ADC Data
        AUD_ADCLRCK : INOUT STD_LOGIC; -- ADC LR Clock
        AUD_BCLK : INOUT STD_LOGIC; -- Bit-Stream Clock
        AUD_DACDAT : OUT STD_LOGIC; -- DAC Data
        AUD_DACLRCK : INOUT STD_LOGIC; -- DAC LR Clock
        AUD_XCK : OUT STD_LOGIC -- Chip Clock

    );

END DE2_115_TOP;

-- Architecture body
--      Describes the functionality or internal implementation of the entity

ARCHITECTURE structural OF DE2_115_TOP IS

    COMPONENT VGA_SYNC_module
        PORT (
            clock_50Mhz : IN STD_LOGIC;
            red, green, blue : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
            red_out, green_out, blue_out : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
            horiz_sync_out, vert_sync_out, video_on, pixel_clock : OUT STD_LOGIC;
            pixel_row, pixel_column : OUT STD_LOGIC_VECTOR(9 DOWNTO 0));
    END COMPONENT;
	 
     COMPONENT GRAPHICS_LAYER
        PORT (
            pixel_row, pixel_column : IN  STD_LOGIC_VECTOR(9 DOWNTO 0);
            vert_sync               : IN  STD_LOGIC;
            anim_tick               : IN  STD_LOGIC;
            show_sphere, show_cube  : IN  STD_LOGIC;
            cycle_cube_color        : IN  STD_LOGIC;
            cycle_sphere_color      : IN  STD_LOGIC;
            rotate_cube_x           : IN  STD_LOGIC;
            rotate_cube_y           : IN  STD_LOGIC;
            rotate_cube_z           : IN  STD_LOGIC;
            x_offset                : IN  INTEGER RANGE -320 TO 320;
            y_offset                : IN  INTEGER RANGE -240 TO 240;
            zoom_level              : IN  INTEGER RANGE 0 TO 4;
            Red, Green, Blue        : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
        );
    END COMPONENT;

    COMPONENT FRAMEBUFFER_SRAM
        PORT (
            clk_50         : IN  STD_LOGIC;
            vert_sync      : IN  STD_LOGIC;
            display_active : IN  STD_LOGIC;
            display_row    : IN  STD_LOGIC_VECTOR(9 DOWNTO 0);
            display_col    : IN  STD_LOGIC_VECTOR(9 DOWNTO 0);
            render_row     : OUT STD_LOGIC_VECTOR(9 DOWNTO 0);
            render_col     : OUT STD_LOGIC_VECTOR(9 DOWNTO 0);
            frame_swap_tick : OUT STD_LOGIC;
            render_red     : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
            render_green   : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
            render_blue    : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
            display_red    : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
            display_green  : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
            display_blue   : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
            sram_addr      : OUT unsigned(19 DOWNTO 0);
            sram_dq        : INOUT unsigned(15 DOWNTO 0);
            sram_ce_n      : OUT STD_LOGIC;
            sram_lb_n      : OUT STD_LOGIC;
            sram_oe_n      : OUT STD_LOGIC;
            sram_ub_n      : OUT STD_LOGIC;
            sram_we_n      : OUT STD_LOGIC
        );
    END COMPONENT;

    COMPONENT BUTTON_CONTROL
        PORT (
            clk         : IN  STD_LOGIC;
            vert_sync   : IN  STD_LOGIC;
            key_n       : IN  STD_LOGIC_VECTOR(3 DOWNTO 0);
            zoom_in_sw  : IN  STD_LOGIC;
            zoom_out_sw : IN  STD_LOGIC;
            x_offset    : OUT INTEGER RANGE -320 TO 320;
            y_offset    : OUT INTEGER RANGE -240 TO 240;
            zoom_level  : OUT INTEGER RANGE 0 TO 4);
    END COMPONENT;

    SIGNAL red_int         : STD_LOGIC_VECTOR(7 DOWNTO 0);  -- VGA input from framebuffer
    SIGNAL green_int       : STD_LOGIC_VECTOR(7 DOWNTO 0);  -- VGA input from framebuffer
    SIGNAL blue_int        : STD_LOGIC_VECTOR(7 DOWNTO 0);  -- VGA input from framebuffer
    SIGNAL render_red_int  : STD_LOGIC_VECTOR(7 DOWNTO 0);  -- Renderer output to back buffer
    SIGNAL render_green_int: STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL render_blue_int : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL vga_r_int       : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL vga_g_int       : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL vga_b_int       : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL video_on_int    : STD_LOGIC;
    SIGNAL vert_sync_int   : STD_LOGIC;
    SIGNAL horiz_sync_int  : STD_LOGIC;
    SIGNAL pixel_clock_int : STD_LOGIC;
    SIGNAL pixel_row_int   : STD_LOGIC_VECTOR(9 DOWNTO 0); -- display scan coordinate
    SIGNAL pixel_column_int: STD_LOGIC_VECTOR(9 DOWNTO 0); -- display scan coordinate
    SIGNAL render_row_int  : STD_LOGIC_VECTOR(9 DOWNTO 0); -- off-screen render coordinate
    SIGNAL render_col_int  : STD_LOGIC_VECTOR(9 DOWNTO 0); -- off-screen render coordinate
    SIGNAL render_frame_tick_int : STD_LOGIC := '0';

    -- Pan / zoom state (driven by BUTTON_CONTROL)
    -- SW(0): show_sphere  SW(1): show_cube  (unchanged)
    -- KEY(0-3): move right/left/down/up
    -- SW(2): zoom in  SW(3): zoom out
    -- SW(4): cube RGB color cycle  SW(5): sphere RGB color cycle
    -- SW(15): cube rotate around X  SW(16): around Y  SW(17): around Z
    SIGNAL x_offset_int    : INTEGER RANGE -320 TO 320 := 0;
    SIGNAL y_offset_int    : INTEGER RANGE -240 TO 240 := 0;
    SIGNAL zoom_level_int  : INTEGER RANGE 0 TO 4      := 2;

BEGIN

    VGA_HS <= horiz_sync_int;
    VGA_VS <= vert_sync_int;
    VGA_BLANK_N <= video_on_int;
    VGA_CLK <= pixel_clock_int;
    VGA_R  <= vga_r_int;
    VGA_G  <= vga_g_int;
    VGA_B  <= vga_b_int;

    -- VGA sync and pixel clock generation
    U1 : VGA_SYNC_module PORT MAP (
        clock_50Mhz    => CLOCK_50,
        red            => red_int,
        green          => green_int,
        blue           => blue_int,
        red_out        => vga_r_int,
        green_out      => vga_g_int,
        blue_out       => vga_b_int,
        horiz_sync_out => horiz_sync_int,
        vert_sync_out  => vert_sync_int,
        video_on       => video_on_int,
        pixel_clock    => pixel_clock_int,
        pixel_row      => pixel_row_int,
        pixel_column   => pixel_column_int
    );

    -- Pan/zoom input handler
    -- KEY(0): right  KEY(1): left  KEY(2): down  KEY(3): up
    -- SW(2): zoom in (hold)        SW(3): zoom out (hold)
    U3 : BUTTON_CONTROL PORT MAP (
        clk         => CLOCK_50,
        vert_sync   => vert_sync_int,
        key_n       => KEY,
        zoom_in_sw  => SW(2),
        zoom_out_sw => SW(3),
        x_offset    => x_offset_int,
        y_offset    => y_offset_int,
        zoom_level  => zoom_level_int
    );

    U4 : FRAMEBUFFER_SRAM PORT MAP (
        clk_50         => CLOCK_50,
        vert_sync      => vert_sync_int,
        display_active => video_on_int,
        display_row    => pixel_row_int,
        display_col    => pixel_column_int,
        render_row     => render_row_int,
        render_col     => render_col_int,
        frame_swap_tick => render_frame_tick_int,
        render_red     => render_red_int,
        render_green   => render_green_int,
        render_blue    => render_blue_int,
        display_red    => red_int,
        display_green  => green_int,
        display_blue   => blue_int,
        sram_addr      => SRAM_ADDR,
        sram_dq        => SRAM_DQ,
        sram_ce_n      => SRAM_CE_N,
        sram_lb_n      => SRAM_LB_N,
        sram_oe_n      => SRAM_OE_N,
        sram_ub_n      => SRAM_UB_N,
        sram_we_n      => SRAM_WE_N
    );

    U2 : GRAPHICS_LAYER PORT MAP (
        pixel_row    => render_row_int,
        pixel_column => render_col_int,
        vert_sync    => vert_sync_int,
        anim_tick    => render_frame_tick_int,
        show_sphere  => SW(0),
        show_cube    => SW(1),
        cycle_cube_color   => SW(4),
        cycle_sphere_color => SW(5),
        rotate_cube_x      => SW(15),
        rotate_cube_y      => SW(16),
        rotate_cube_z      => SW(17),
        x_offset     => x_offset_int,
        y_offset     => y_offset_int,
        zoom_level   => zoom_level_int,
        Red          => render_red_int,
        Green        => render_green_int,
        Blue         => render_blue_int
    );

END structural;
