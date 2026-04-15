LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE work.GRAPHICS_TEST_UTILS.ALL;

PACKAGE RENDERING_PIPELINE IS

    TYPE cube_t IS RECORD
        center_x : INTEGER;
        center_y : INTEGER;
        side_length : INTEGER;
        scale_x_q8 : INTEGER; -- 256 = 1.0x
        scale_y_q8 : INTEGER; -- 256 = 1.0x
        color : color_t;
    END RECORD;

    TYPE light_t IS RECORD
        x_q8 : INTEGER;
        y_q8 : INTEGER;
        z_q8 : INTEGER;
        ambient_q8 : INTEGER;
        diffuse_q8 : INTEGER;
    END RECORD;

    FUNCTION render_lit_cube_pixel(
        x, y : INTEGER;
        cube : cube_t;
        light : light_t
    ) RETURN color_t;

    FUNCTION render_scene_pixel(
        x, y : INTEGER;
        cube1, cube2, cube3 : cube_t;
        light : light_t;
        background : color_t
    ) RETURN color_t;

END PACKAGE RENDERING_PIPELINE;

PACKAGE BODY RENDERING_PIPELINE IS

    FUNCTION div_round_signed(num, den : INTEGER) RETURN INTEGER IS
    BEGIN
        IF den = 0 THEN
            RETURN 0;
        END IF;

        IF num >= 0 THEN
            RETURN (num + (den / 2)) / den;
        ELSE
            RETURN -(((-num) + (den / 2)) / den);
        END IF;
    END FUNCTION;

    FUNCTION clamp_u8(v : INTEGER) RETURN INTEGER IS
    BEGIN
        IF v < 0 THEN
            RETURN 0;
        ELSIF v > 255 THEN
            RETURN 255;
        END IF;
        RETURN v;
    END FUNCTION;

    FUNCTION to_slv8(v : INTEGER) RETURN STD_LOGIC_VECTOR IS
    BEGIN
        RETURN STD_LOGIC_VECTOR(to_unsigned(clamp_u8(v), 8));
    END FUNCTION;

    FUNCTION is_transparent(c : color_t) RETURN BOOLEAN IS
    BEGIN
        RETURN (c.r = x"00") AND (c.g = x"00") AND (c.b = x"00");
    END FUNCTION;

    FUNCTION scale_color(base_color : color_t; shade_q8 : INTEGER) RETURN color_t IS
        VARIABLE base_r : INTEGER;
        VARIABLE base_g : INTEGER;
        VARIABLE base_b : INTEGER;
    BEGIN
        base_r := to_integer(unsigned(base_color.r));
        base_g := to_integer(unsigned(base_color.g));
        base_b := to_integer(unsigned(base_color.b));

        RETURN (
            r => to_slv8((base_r * shade_q8) / 255),
            g => to_slv8((base_g * shade_q8) / 255),
            b => to_slv8((base_b * shade_q8) / 255)
        );
    END FUNCTION;

    FUNCTION clamp_scale_q8(scale_q8 : INTEGER) RETURN INTEGER IS
    BEGIN
        IF scale_q8 < 1 THEN
            RETURN 1;
        END IF;
        RETURN scale_q8;
    END FUNCTION;

    FUNCTION inv_scale_delta_q8(delta_px, scale_q8 : INTEGER) RETURN INTEGER IS
        VARIABLE s : INTEGER;
    BEGIN
        s := clamp_scale_q8(scale_q8);
        RETURN div_round_signed(delta_px * 256, s);
    END FUNCTION;

    FUNCTION cube_face_id(
        px, py : INTEGER;
        cube : cube_t
    ) RETURN INTEGER IS
        VARIABLE local_px : INTEGER;
        VARIABLE local_py : INTEGER;
        CONSTANT half_side : INTEGER := cube.side_length / 2;
        CONSTANT depth_x : INTEGER := cube.side_length / 3;
        CONSTANT depth_y : INTEGER := -cube.side_length / 4;

        CONSTANT f0_x : INTEGER := cube.center_x - half_side;
        CONSTANT f0_y : INTEGER := cube.center_y - half_side;
        CONSTANT f1_x : INTEGER := cube.center_x + half_side;
        CONSTANT f1_y : INTEGER := cube.center_y - half_side;
        CONSTANT f2_x : INTEGER := cube.center_x + half_side;
        CONSTANT f2_y : INTEGER := cube.center_y + half_side;
        CONSTANT f3_x : INTEGER := cube.center_x - half_side;
        CONSTANT f3_y : INTEGER := cube.center_y + half_side;

        CONSTANT b0_x : INTEGER := f0_x + depth_x;
        CONSTANT b0_y : INTEGER := f0_y + depth_y;
        CONSTANT b1_x : INTEGER := f1_x + depth_x;
        CONSTANT b1_y : INTEGER := f1_y + depth_y;
        CONSTANT b2_x : INTEGER := f2_x + depth_x;
        CONSTANT b2_y : INTEGER := f2_y + depth_y;
        CONSTANT b3_x : INTEGER := f3_x + depth_x;
        CONSTANT b3_y : INTEGER := f3_y + depth_y;
    BEGIN
        local_px := cube.center_x + inv_scale_delta_q8(px - cube.center_x, cube.scale_x_q8);
        local_py := cube.center_y + inv_scale_delta_q8(py - cube.center_y, cube.scale_y_q8);

        IF is_point_in_triangle(local_px, local_py, f0_x, f0_y, f1_x, f1_y, f2_x, f2_y) OR
           is_point_in_triangle(local_px, local_py, f0_x, f0_y, f2_x, f2_y, f3_x, f3_y) THEN
            RETURN 1; -- front
        END IF;

        IF is_point_in_triangle(local_px, local_py, f1_x, f1_y, f2_x, f2_y, b2_x, b2_y) OR
           is_point_in_triangle(local_px, local_py, f1_x, f1_y, b2_x, b2_y, b1_x, b1_y) THEN
            RETURN 2; -- right
        END IF;

        IF is_point_in_triangle(local_px, local_py, f0_x, f0_y, f1_x, f1_y, b1_x, b1_y) OR
           is_point_in_triangle(local_px, local_py, f0_x, f0_y, b1_x, b1_y, b0_x, b0_y) THEN
            RETURN 3; -- top
        END IF;

        IF is_point_in_triangle(local_px, local_py, b0_x, b0_y, b2_x, b2_y, b1_x, b1_y) OR
           is_point_in_triangle(local_px, local_py, b0_x, b0_y, b3_x, b3_y, b2_x, b2_y) THEN
            RETURN 4; -- back
        END IF;

        IF is_point_in_triangle(local_px, local_py, f0_x, f0_y, b0_x, b0_y, b3_x, b3_y) OR
           is_point_in_triangle(local_px, local_py, f0_x, f0_y, b3_x, b3_y, f3_x, f3_y) THEN
            RETURN 5; -- left
        END IF;

        IF is_point_in_triangle(local_px, local_py, f3_x, f3_y, b3_x, b3_y, b2_x, b2_y) OR
           is_point_in_triangle(local_px, local_py, f3_x, f3_y, b2_x, b2_y, f2_x, f2_y) THEN
            RETURN 6; -- bottom
        END IF;

        RETURN 0;
    END FUNCTION;

    FUNCTION face_shade_q8(face_id : INTEGER; light : light_t) RETURN INTEGER IS
        VARIABLE dot_q8 : INTEGER;
        VARIABLE shade_q8 : INTEGER;
    BEGIN
        CASE face_id IS
            WHEN 1 => dot_q8 := light.z_q8;
            WHEN 2 => dot_q8 := light.x_q8;
            WHEN 3 => dot_q8 := light.y_q8;
            WHEN 4 => dot_q8 := -light.z_q8;
            WHEN 5 => dot_q8 := -light.x_q8;
            WHEN 6 => dot_q8 := -light.y_q8;
            WHEN OTHERS => dot_q8 := 0;
        END CASE;

        IF dot_q8 < 0 THEN
            dot_q8 := 0;
        END IF;

        shade_q8 := light.ambient_q8 + ((dot_q8 * light.diffuse_q8) / 255);
        RETURN clamp_u8(shade_q8);
    END FUNCTION;

    FUNCTION render_lit_cube_pixel(
        x, y : INTEGER;
        cube : cube_t;
        light : light_t
    ) RETURN color_t IS
        VARIABLE face_id : INTEGER;
        VARIABLE shade_q8 : INTEGER;
    BEGIN
        face_id := cube_face_id(x, y, cube);
        IF face_id = 0 THEN
            RETURN TRANSPARENT;
        END IF;

        shade_q8 := face_shade_q8(face_id, light);
        RETURN scale_color(cube.color, shade_q8);
    END FUNCTION;

    FUNCTION render_scene_pixel(
        x, y : INTEGER;
        cube1, cube2, cube3 : cube_t;
        light : light_t;
        background : color_t
    ) RETURN color_t IS
        VARIABLE pixel_color : color_t;
    BEGIN
        pixel_color := render_lit_cube_pixel(x, y, cube1, light);
        IF NOT is_transparent(pixel_color) THEN
            RETURN pixel_color;
        END IF;

        pixel_color := render_lit_cube_pixel(x, y, cube2, light);
        IF NOT is_transparent(pixel_color) THEN
            RETURN pixel_color;
        END IF;

        pixel_color := render_lit_cube_pixel(x, y, cube3, light);
        IF NOT is_transparent(pixel_color) THEN
            RETURN pixel_color;
        END IF;

        RETURN background;
    END FUNCTION;

END PACKAGE BODY RENDERING_PIPELINE;
