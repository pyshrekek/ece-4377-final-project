LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

PACKAGE GRAPHICS_TEST_UTILS IS

    TYPE color_t IS RECORD
        r : STD_LOGIC_VECTOR(7 DOWNTO 0);
        g : STD_LOGIC_VECTOR(7 DOWNTO 0);
        b : STD_LOGIC_VECTOR(7 DOWNTO 0);
    END RECORD;

    CONSTANT TRANSPARENT : color_t := (x"00", x"00", x"00");

    FUNCTION is_on_line (
        x, y, x0, y0, x1, y1, thickness : INTEGER
    ) RETURN BOOLEAN;

    FUNCTION is_on_cube (
        x, y, center_x, center_y, side_length : INTEGER
    ) RETURN BOOLEAN;

    FUNCTION is_point_in_triangle (
        px, py, x1, y1, x2, y2, x3, y3 : INTEGER
    ) RETURN BOOLEAN;

    FUNCTION is_cube_filled (
        x, y, center_x, center_y, side_length : INTEGER
    ) RETURN BOOLEAN;

    FUNCTION render_cube (
        x, y, center_x, center_y, side_length : INTEGER;
        color : color_t
    ) RETURN color_t;

END PACKAGE GRAPHICS_TEST_UTILS;

PACKAGE BODY GRAPHICS_TEST_UTILS IS

    FUNCTION sign_of_cross (
        x1, y1, x2, y2, px, py : INTEGER
    ) RETURN INTEGER IS
        VARIABLE cross : INTEGER;
    BEGIN
        cross := (x2 - x1) * (py - y1) - (y2 - y1) * (px - x1);
        IF cross > 0 THEN
            RETURN 1;
        ELSIF cross < 0 THEN
            RETURN -1;
        ELSE
            RETURN 0;
        END IF;
    END FUNCTION;

    FUNCTION is_point_in_triangle (
        px, py, x1, y1, x2, y2, x3, y3 : INTEGER
    ) RETURN BOOLEAN IS
        VARIABLE d1, d2, d3 : INTEGER;
        VARIABLE has_neg, has_pos : BOOLEAN;
    BEGIN
        d1 := sign_of_cross(x1, y1, x2, y2, px, py);
        d2 := sign_of_cross(x2, y2, x3, y3, px, py);
        d3 := sign_of_cross(x3, y3, x1, y1, px, py);

        has_neg := (d1 < 0) OR (d2 < 0) OR (d3 < 0);
        has_pos := (d1 > 0) OR (d2 > 0) OR (d3 > 0);

        RETURN NOT (has_neg AND has_pos);
    END FUNCTION;

    FUNCTION is_on_line (
        x, y, x0, y0, x1, y1, thickness : INTEGER
    ) RETURN BOOLEAN IS
        VARIABLE dx, dy, ex, ey, dot, len_sq, cross_product : INTEGER;
        VARIABLE cross_product_squared, max_allowed_cross_squared : signed(63 DOWNTO 0);
        VARIABLE thickness_sq : INTEGER;
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

        thickness_sq := thickness * thickness;
        cross_product_squared := to_signed(cross_product, 32) * to_signed(cross_product, 32);
        max_allowed_cross_squared := to_signed(thickness_sq, 32) * to_signed(len_sq, 32);

        RETURN (cross_product_squared <= max_allowed_cross_squared)
        AND (dot >= 0)
        AND (dot <= len_sq);
    END FUNCTION;

    FUNCTION is_on_cube (
        x, y, center_x, center_y, side_length : INTEGER
    ) RETURN BOOLEAN IS
        CONSTANT half_side : INTEGER := side_length / 2;
        CONSTANT depth_x : INTEGER := side_length / 3;
        CONSTANT depth_y : INTEGER := -side_length / 4;

        CONSTANT f0_x : INTEGER := center_x - half_side;
        CONSTANT f0_y : INTEGER := center_y - half_side;
        CONSTANT f1_x : INTEGER := center_x + half_side;
        CONSTANT f1_y : INTEGER := center_y - half_side;
        CONSTANT f2_x : INTEGER := center_x + half_side;
        CONSTANT f2_y : INTEGER := center_y + half_side;
        CONSTANT f3_x : INTEGER := center_x - half_side;
        CONSTANT f3_y : INTEGER := center_y + half_side;

        CONSTANT b0_x : INTEGER := f0_x + depth_x;
        CONSTANT b0_y : INTEGER := f0_y + depth_y;
        CONSTANT b1_x : INTEGER := f1_x + depth_x;
        CONSTANT b1_y : INTEGER := f1_y + depth_y;
        CONSTANT b2_x : INTEGER := f2_x + depth_x;
        CONSTANT b2_y : INTEGER := f2_y + depth_y;
        CONSTANT b3_x : INTEGER := f3_x + depth_x;
        CONSTANT b3_y : INTEGER := f3_y + depth_y;
    BEGIN
        RETURN
            is_on_line(x, y, f0_x, f0_y, f1_x, f1_y, 1) OR
            is_on_line(x, y, f1_x, f1_y, f2_x, f2_y, 1) OR
            is_on_line(x, y, f2_x, f2_y, f3_x, f3_y, 1) OR
            is_on_line(x, y, f3_x, f3_y, f0_x, f0_y, 1) OR
            is_on_line(x, y, b0_x, b0_y, b1_x, b1_y, 1) OR
            is_on_line(x, y, b1_x, b1_y, b2_x, b2_y, 1) OR
            is_on_line(x, y, b2_x, b2_y, b3_x, b3_y, 1) OR
            is_on_line(x, y, b3_x, b3_y, b0_x, b0_y, 1) OR
            is_on_line(x, y, f0_x, f0_y, b0_x, b0_y, 1) OR
            is_on_line(x, y, f1_x, f1_y, b1_x, b1_y, 1) OR
            is_on_line(x, y, f2_x, f2_y, b2_x, b2_y, 1) OR
            is_on_line(x, y, f3_x, f3_y, b3_x, b3_y, 1);
    END FUNCTION;

    FUNCTION is_cube_filled (
        x, y, center_x, center_y, side_length : INTEGER
    ) RETURN BOOLEAN IS
        CONSTANT half_side : INTEGER := side_length / 2;
        CONSTANT depth_x : INTEGER := side_length / 3;
        CONSTANT depth_y : INTEGER := -side_length / 4;

        CONSTANT f0_x : INTEGER := center_x - half_side;
        CONSTANT f0_y : INTEGER := center_y - half_side;
        CONSTANT f1_x : INTEGER := center_x + half_side;
        CONSTANT f1_y : INTEGER := center_y - half_side;
        CONSTANT f2_x : INTEGER := center_x + half_side;
        CONSTANT f2_y : INTEGER := center_y + half_side;
        CONSTANT f3_x : INTEGER := center_x - half_side;
        CONSTANT f3_y : INTEGER := center_y + half_side;

        CONSTANT b0_x : INTEGER := f0_x + depth_x;
        CONSTANT b0_y : INTEGER := f0_y + depth_y;
        CONSTANT b1_x : INTEGER := f1_x + depth_x;
        CONSTANT b1_y : INTEGER := f1_y + depth_y;
        CONSTANT b2_x : INTEGER := f2_x + depth_x;
        CONSTANT b2_y : INTEGER := f2_y + depth_y;
        CONSTANT b3_x : INTEGER := f3_x + depth_x;
        CONSTANT b3_y : INTEGER := f3_y + depth_y;
    BEGIN
        -- Front face: 2 triangles
        IF is_point_in_triangle(x, y, f0_x, f0_y, f1_x, f1_y, f2_x, f2_y) THEN
            RETURN true;
        END IF;
        IF is_point_in_triangle(x, y, f0_x, f0_y, f2_x, f2_y, f3_x, f3_y) THEN
            RETURN true;
        END IF;

        -- Back face: 2 triangles
        IF is_point_in_triangle(x, y, b0_x, b0_y, b2_x, b2_y, b1_x, b1_y) THEN
            RETURN true;
        END IF;
        IF is_point_in_triangle(x, y, b0_x, b0_y, b3_x, b3_y, b2_x, b2_y) THEN
            RETURN true;
        END IF;

        -- Left face: 2 triangles
        IF is_point_in_triangle(x, y, f0_x, f0_y, b0_x, b0_y, b3_x, b3_y) THEN
            RETURN true;
        END IF;
        IF is_point_in_triangle(x, y, f0_x, f0_y, b3_x, b3_y, f3_x, f3_y) THEN
            RETURN true;
        END IF;

        -- Right face: 2 triangles
        IF is_point_in_triangle(x, y, f1_x, f1_y, f2_x, f2_y, b2_x, b2_y) THEN
            RETURN true;
        END IF;
        IF is_point_in_triangle(x, y, f1_x, f1_y, b2_x, b2_y, b1_x, b1_y) THEN
            RETURN true;
        END IF;

        -- Top face: 2 triangles
        IF is_point_in_triangle(x, y, f0_x, f0_y, f1_x, f1_y, b1_x, b1_y) THEN
            RETURN true;
        END IF;
        IF is_point_in_triangle(x, y, f0_x, f0_y, b1_x, b1_y, b0_x, b0_y) THEN
            RETURN true;
        END IF;

        -- Bottom face: 2 triangles
        IF is_point_in_triangle(x, y, f3_x, f3_y, b3_x, b3_y, b2_x, b2_y) THEN
            RETURN true;
        END IF;
        IF is_point_in_triangle(x, y, f3_x, f3_y, b2_x, b2_y, f2_x, f2_y) THEN
            RETURN true;
        END IF;

        RETURN false;
    END FUNCTION;

    FUNCTION render_cube (
        x, y, center_x, center_y, side_length : INTEGER;
        color : color_t
    ) RETURN color_t IS
    BEGIN
        IF is_cube_filled(x, y, center_x, center_y, side_length) THEN
            RETURN color;
        ELSE
            RETURN TRANSPARENT;
        END IF;
    END FUNCTION;

END PACKAGE BODY GRAPHICS_TEST_UTILS;