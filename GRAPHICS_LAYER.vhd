LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE work.GRAPHICS_TEST_UTILS.ALL;

ENTITY GRAPHICS_LAYER IS
    PORT (
        pixel_row : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
        pixel_column : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
        vert_sync : IN STD_LOGIC;
        Red : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
        Green : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
        Blue : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
    );
END ENTITY GRAPHICS_LAYER;

ARCHITECTURE behavioral OF GRAPHICS_LAYER IS

    SIGNAL x : INTEGER RANGE 0 TO 639;
    SIGNAL y : INTEGER RANGE 0 TO 639;
    
    -- Track which shapes are visible at this pixel
    SIGNAL in_cube1 : BOOLEAN;
    SIGNAL in_cube2 : BOOLEAN;
    SIGNAL in_cube3 : BOOLEAN;

BEGIN

    x <= to_integer(unsigned(pixel_column));
    y <= to_integer(unsigned(pixel_row));
    
    -- Test membership for each cube
    in_cube1 <= is_cube_filled(x, y, 280, 240, 160);
    in_cube2 <= is_cube_filled(x, y, 460, 240, 120);
    in_cube3 <= is_cube_filled(x, y, 500, 240, 100);

    -- Render with priority: cube1 > cube2 > cube3 > background
    -- Use boolean priority instead of color values for cleaner logic
    Red <= x"FF" WHEN in_cube1 ELSE
           x"00" WHEN in_cube2 ELSE
           x"FF" WHEN in_cube3 ELSE
           x"00";
    
    Green <= x"FF" WHEN in_cube1 ELSE
             x"FF" WHEN in_cube2 ELSE
             x"00" WHEN in_cube3 ELSE
             x"00";
    
    Blue <= x"FF" WHEN in_cube1 ELSE
            x"FF" WHEN in_cube2 ELSE
            x"00" WHEN in_cube3 ELSE
            x"00";

END ARCHITECTURE behavioral;
