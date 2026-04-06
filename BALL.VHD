			-- Bouncing Ball Video 
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.all;
USE  IEEE.STD_LOGIC_ARITH.all;
USE  IEEE.STD_LOGIC_UNSIGNED.all;
			-- Bouncing Ball Video 


ENTITY ball IS


   PORT(pixel_row, pixel_column		: IN std_logic_vector(9 DOWNTO 0);
        Red,Green,Blue 				: OUT std_logic_vector(7 downto 0);
        Vert_sync	: IN std_logic);
       
				
END ball;

architecture behavior of ball is

			-- Video Display Signals   
SIGNAL Ball_on, Direction			: std_logic;
SIGNAL Size 						: std_logic_vector(9 DOWNTO 0);  
SIGNAL Ball_X_motion 				: std_logic_vector(9 DOWNTO 0);
SIGNAL Ball_Y_motion 				: std_logic_vector(9 DOWNTO 0);
SIGNAL Ball_Y_pos, Ball_X_pos		: std_logic_vector(9 DOWNTO 0);


BEGIN           

Size <= CONV_STD_LOGIC_VECTOR(8,10);

		-- Colors for pixel data on video signal
Red <=   (others => '0') when Ball_on = '1' else (others => '1');
Green <= (others => '0') when Ball_on = '1' else (others => '1');
Blue <=  (others => '1') when Ball_on = '1' else (others => '1');

RGB_Display: Process (Ball_X_pos, Ball_Y_pos, pixel_column, pixel_row, Size)
BEGIN
			-- Set Ball_on ='1' to display ball
 IF ('0' & Ball_X_pos <= pixel_column + Size) AND
 			-- compare positive numbers only
 	(Ball_X_pos + Size >= '0' & pixel_column) AND
 	('0' & Ball_Y_pos <= pixel_row + Size) AND
 	(Ball_Y_pos + Size >= '0' & pixel_row ) THEN
 		Ball_on <= '1';
 	ELSE
 		Ball_on <= '0';
END IF;
END process RGB_Display;


Move_Ball: process
BEGIN
	WAIT UNTIL vert_sync'event and vert_sync = '1';
	-- Move ball once every vertical sync: Y direction
			-- Bounce off top or bottom of screen
			IF ('0' & Ball_Y_pos) >= 480 - Size THEN
				Ball_Y_motion <= CONV_STD_LOGIC_VECTOR(-2,10);
			ELSIF Ball_Y_pos <= Size THEN
				Ball_Y_motion <= CONV_STD_LOGIC_VECTOR(2,10);
			END IF;
			-- Compute next ball Y position
				Ball_Y_pos <= Ball_Y_pos + Ball_Y_motion;
	-- Move ball once every vertical sync: X direction
			-- Bounce off top or bottom of screen
			IF ('0' & Ball_X_pos) >= 640 - Size THEN
				Ball_X_motion <= CONV_STD_LOGIC_VECTOR(-2,10);
			ELSIF Ball_X_pos <= Size THEN
				Ball_X_motion <= CONV_STD_LOGIC_VECTOR(2,10);
			END IF;
			-- Compute next ball Y position
				Ball_X_pos <= Ball_X_pos + Ball_X_motion;
				
END process Move_Ball;

END behavior;

