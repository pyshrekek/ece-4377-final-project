LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;

ENTITY ball IS
    PORT (
        pixel_row, pixel_column : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
        Red, Green, Blue        : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
        Vert_sync               : IN STD_LOGIC);
END ball;

ARCHITECTURE behavior OF ball IS

    SIGNAL Ball_on    : STD_LOGIC;
    SIGNAL Size       : STD_LOGIC_VECTOR(9 DOWNTO 0);
    SIGNAL Ball_Y_pos : STD_LOGIC_VECTOR(9 DOWNTO 0);
    SIGNAL Ball_X_pos : STD_LOGIC_VECTOR(9 DOWNTO 0);
    SIGNAL angle      : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');

    CONSTANT CENTER_X : INTEGER := 320;
    CONSTANT CENTER_Y : INTEGER := 240;

    TYPE sin_table_t IS ARRAY(0 TO 255) OF INTEGER RANGE -128 TO 127;

    CONSTANT SIN_LUT : sin_table_t := (
          0,   3,   6,   9,  12,  15,  18,  21,
         24,  28,  31,  34,  37,  40,  43,  46,
         48,  51,  54,  57,  60,  63,  65,  68,
         71,  73,  76,  78,  81,  83,  85,  88,
         90,  92,  94,  96,  98, 100, 102, 104,
        105, 107, 108, 110, 111, 112, 114, 115,
        116, 117, 118, 119, 120, 120, 121, 122,
        122, 123, 123, 123, 124, 124, 124, 124,
        124, 124, 124, 124, 123, 123, 123, 122,
        122, 121, 120, 120, 119, 118, 117, 116,
        115, 114, 112, 111, 110, 108, 107, 105,
        104, 102, 100,  98,  96,  94,  92,  90,
         88,  85,  83,  81,  78,  76,  73,  71,
         68,  65,  63,  60,  57,  54,  51,  48,
         46,  43,  40,  37,  34,  31,  28,  24,
         21,  18,  15,  12,   9,   6,   3,   0,
         -3,  -6,  -9, -12, -15, -18, -21, -24,
        -28, -31, -34, -37, -40, -43, -46, -48,
        -51, -54, -57, -60, -63, -65, -68, -71,
        -73, -76, -78, -81, -83, -85, -88, -90,
        -92, -94, -96, -98,-100,-102,-104,-105,
       -107,-108,-110,-111,-112,-114,-115,-116,
       -117,-118,-119,-120,-120,-121,-122,-122,
       -123,-123,-123,-124,-124,-124,-124,-124,
       -124,-124,-124,-123,-123,-123,-122,-122,
       -121,-120,-120,-119,-118,-117,-116,-115,
       -114,-112,-111,-110,-108,-107,-105,-104,
       -102,-100, -98, -96, -94, -92, -90, -88,
        -85, -83, -81, -78, -76, -73, -71, -68,
        -65, -63, -60, -57, -54, -51, -48, -46,
        -43, -40, -37, -34, -31, -28, -24, -21,
        -18, -15, -12,  -9,  -6,  -3,   0,   0
    );

BEGIN

    Size <= CONV_STD_LOGIC_VECTOR(8, 10);

    Red   <= (OTHERS => '0') WHEN Ball_on = '1' ELSE (OTHERS => '1');
    Green <= (OTHERS => '0') WHEN Ball_on = '1' ELSE (OTHERS => '1');
    Blue  <= (OTHERS => '1') WHEN Ball_on = '1' ELSE (OTHERS => '1');

    Move_Ball : PROCESS
        VARIABLE sin_val  : INTEGER RANGE -128 TO 127;
        VARIABLE cos_val  : INTEGER RANGE -128 TO 127;
        VARIABLE angle_int : INTEGER RANGE 0 TO 255;
    BEGIN
        WAIT UNTIL vert_sync'EVENT AND vert_sync = '1';
        angle <= angle + 1;
        angle_int := CONV_INTEGER(angle);
        sin_val := SIN_LUT(angle_int);
        cos_val := SIN_LUT((angle_int + 64) MOD 256);
        Ball_X_pos <= CONV_STD_LOGIC_VECTOR(CENTER_X + cos_val, 10);
        Ball_Y_pos <= CONV_STD_LOGIC_VECTOR(CENTER_Y + sin_val, 10);
    END PROCESS Move_Ball;

    RGB_Display : PROCESS (Ball_X_pos, Ball_Y_pos, pixel_column, pixel_row, Size)
    BEGIN
        IF ('0' & Ball_X_pos <= pixel_column + Size) AND
           (Ball_X_pos + Size >= '0' & pixel_column) AND
           ('0' & Ball_Y_pos <= pixel_row + Size) AND
           (Ball_Y_pos + Size >= '0' & pixel_row) THEN
            Ball_on <= '1';
        ELSE
            Ball_on <= '0';
        END IF;
    END PROCESS RGB_Display;

END behavior;