-- Bouncing Ball Video 
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;
-- Bouncing Ball Video 
ENTITY ball IS
    PORT (
        pixel_row, pixel_column : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
        Red, Green, Blue : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
        Vert_sync : IN STD_LOGIC);
END ball;

ARCHITECTURE behavior OF ball IS

    -- Video Display Signals   
    SIGNAL Ball_on, Direction : STD_LOGIC;
    SIGNAL Size : STD_LOGIC_VECTOR(9 DOWNTO 0);
    SIGNAL Ball_X_motion : STD_LOGIC_VECTOR(9 DOWNTO 0);
    SIGNAL Ball_Y_motion : STD_LOGIC_VECTOR(9 DOWNTO 0);
    SIGNAL Ball_Y_pos, Ball_X_pos : STD_LOGIC_VECTOR(9 DOWNTO 0);
BEGIN

    Size <= CONV_STD_LOGIC_VECTOR(8, 10);

    -- Colors for pixel data on video signal
    Red <= (OTHERS => '0') WHEN Ball_on = '1' ELSE
        (OTHERS => '1');
    Green <= (OTHERS => '0') WHEN Ball_on = '1' ELSE
        (OTHERS => '1');
    Blue <= (OTHERS => '1') WHEN Ball_on = '1' ELSE
        (OTHERS => '1');

    RGB_Display : PROCESS (Ball_X_pos, Ball_Y_pos, pixel_column, pixel_row, Size)
    BEGIN
        -- Set Ball_on ='1' to display ball
        IF ('0' & Ball_X_pos <= pixel_column + Size) AND
            -- compare positive numbers only
            (Ball_X_pos + Size >= '0' & pixel_column) AND
            ('0' & Ball_Y_pos <= pixel_row + Size) AND
            (Ball_Y_pos + Size >= '0' & pixel_row) THEN
            Ball_on <= '1';
        ELSE
            Ball_on <= '0';
        END IF;
    END PROCESS RGB_Display;
    Move_Ball : PROCESS
    BEGIN
        WAIT UNTIL vert_sync'event AND vert_sync = '1';
        -- Move ball once every vertical sync: Y direction
        -- Bounce off top or bottom of screen
        IF ('0' & Ball_Y_pos) >= 480 - Size THEN
            Ball_Y_motion <= CONV_STD_LOGIC_VECTOR(-2, 10);
        ELSIF Ball_Y_pos <= Size THEN
            Ball_Y_motion <= CONV_STD_LOGIC_VECTOR(2, 10);
        END IF;
        -- Compute next ball Y position
        Ball_Y_pos <= Ball_Y_pos + Ball_Y_motion;
        -- Move ball once every vertical sync: X direction
        -- Bounce off top or bottom of screen
        IF ('0' & Ball_X_pos) >= 640 - Size THEN
            Ball_X_motion <= CONV_STD_LOGIC_VECTOR(-2, 10);
        ELSIF Ball_X_pos <= Size THEN
            Ball_X_motion <= CONV_STD_LOGIC_VECTOR(2, 10);
        END IF;
        -- Compute next ball Y position
        Ball_X_pos <= Ball_X_pos + Ball_X_motion;

    END PROCESS Move_Ball;

END behavior;