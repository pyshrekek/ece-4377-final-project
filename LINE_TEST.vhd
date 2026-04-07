LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY LINE_TEST IS
    PORT (
        pixel_row : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
        pixel_column : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
        vert_sync : IN STD_LOGIC;
        Red : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
        Green : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
        Blue : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
    );
END ENTITY LINE_TEST;

ARCHITECTURE behavioral OF LINE_TEST IS

    CONSTANT THICKNESS : INTEGER := 1;
    CONSTANT THICK_SQ : INTEGER := THICKNESS * THICKNESS;

    FUNCTION is_on_line (x, y, x0, y0, x1, y1 : INTEGER) RETURN BOOLEAN IS
        VARIABLE dx, dy, ex, ey, dot, len_sq, cross_product : INTEGER;
        VARIABLE cross_product_squared, max_allowed_cross_squared : signed(63 DOWNTO 0);
    BEGIN
        dx := x1 - x0;
        dy := y1 - y0;
        ex := x - x0;
        ey := y - y0;
        cross_product := ex * dy - ey * dx;
        dot := ex * dx + ey * dy;
        len_sq := dx * dx + dy * dy;

        IF len_sq = 0 THEN
            RETURN false;
        END IF;

        cross_product_squared := to_signed(cross_product, 32) * to_signed(cross_product, 32);
        max_allowed_cross_squared := to_signed(THICK_SQ, 32) * to_signed(len_sq, 32);

        RETURN (cross_product_squared <= max_allowed_cross_squared)
        AND (dot >= 0)
        AND (dot <= len_sq);
    END FUNCTION;

    SIGNAL x : INTEGER RANGE 0 TO 639;
    SIGNAL y : INTEGER RANGE 0 TO 639;
    SIGNAL on_line : BOOLEAN;

BEGIN

    x <= to_integer(unsigned(pixel_column));
    y <= to_integer(unsigned(pixel_row));
    on_line <= is_on_line(x, y, 0, 10, 639, 420); -- temp random coordinates for now. need to imp passing a set of coords thru a diff file

    Red <= x"FF" WHEN on_line ELSE
        x"00";
    Green <= x"FF" WHEN on_line ELSE
        x"00";
    Blue <= x"FF" WHEN on_line ELSE
        x"00";

END ARCHITECTURE behavioral;