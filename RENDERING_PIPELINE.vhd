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
    TYPE cube_scene_t IS ARRAY (NATURAL RANGE <>) OF cube_t;

    TYPE light_t IS RECORD
        x_q8 : INTEGER;
        y_q8 : INTEGER;
        z_q8 : INTEGER;
        ambient_q8 : INTEGER;
        diffuse_q8 : INTEGER;
    END RECORD;

    -- Shared triangle primitive used across shape renderers.
    TYPE triangle_t IS RECORD
        x1 : INTEGER;
        y1 : INTEGER;
        x2 : INTEGER;
        y2 : INTEGER;
        x3 : INTEGER;
        y3 : INTEGER;
        normal_x_q8 : INTEGER;
        normal_y_q8 : INTEGER;
        normal_z_q8 : INTEGER;
    END RECORD;
    TYPE triangle_scene_t IS ARRAY (NATURAL RANGE <>) OF triangle_t;

    -- Shared fixed-point pixel helpers used by primitive renderers.
    FUNCTION clamp_u8(v : INTEGER) RETURN INTEGER;
    FUNCTION inv_scale_delta_q8(delta_px, scale_q8 : INTEGER) RETURN INTEGER;
    FUNCTION scale_color(base_color : color_t; shade_q8 : INTEGER) RETURN color_t;
    FUNCTION shade_from_dot_q8(dot_q8 : INTEGER; light : light_t) RETURN INTEGER;
    FUNCTION shade_from_normal_q8(
        normal_x_q8, normal_y_q8, normal_z_q8 : INTEGER;
        light : light_t
    ) RETURN INTEGER;
    FUNCTION render_lit_triangle_pixel(
        x, y : INTEGER;
        tri : triangle_t;
        base_color : color_t;
        light : light_t
    ) RETURN color_t;

    FUNCTION render_lit_cube_pixel(
        x, y : INTEGER;
        cube : cube_t;
        light : light_t
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
        VARIABLE shade  : INTEGER;
    BEGIN
        base_r := to_integer(unsigned(base_color.r));
        base_g := to_integer(unsigned(base_color.g));
        base_b := to_integer(unsigned(base_color.b));
        shade := clamp_u8(shade_q8);

        RETURN (
            -- Match SPHERE_RENDERING scale behavior for consistent shading.
            r => to_slv8((base_r * shade + 128) / 256),
            g => to_slv8((base_g * shade + 128) / 256),
            b => to_slv8((base_b * shade + 128) / 256)
        );
    END FUNCTION;

    FUNCTION shade_from_dot_q8(dot_q8 : INTEGER; light : light_t) RETURN INTEGER IS
        VARIABLE dot_clamped : INTEGER;
    BEGIN
        dot_clamped := clamp_u8(dot_q8);
        RETURN clamp_u8(light.ambient_q8 + ((dot_clamped * light.diffuse_q8 + 128) / 256));
    END FUNCTION;

    FUNCTION shade_from_normal_q8(
        normal_x_q8, normal_y_q8, normal_z_q8 : INTEGER;
        light : light_t
    ) RETURN INTEGER IS
        VARIABLE dot_q8 : INTEGER;
    BEGIN
        dot_q8 := (
            (normal_x_q8 * light.x_q8) +
            (normal_y_q8 * light.y_q8) +
            (normal_z_q8 * light.z_q8) +
            128
        ) / 256;
        RETURN shade_from_dot_q8(dot_q8, light);
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
        IF s = 256 THEN
            RETURN delta_px;
        END IF;
        RETURN div_round_signed(delta_px * 256, s);
    END FUNCTION;

    FUNCTION min2(a, b : INTEGER) RETURN INTEGER IS
    BEGIN
        IF a < b THEN
            RETURN a;
        END IF;
        RETURN b;
    END FUNCTION;

    FUNCTION max2(a, b : INTEGER) RETURN INTEGER IS
    BEGIN
        IF a > b THEN
            RETURN a;
        END IF;
        RETURN b;
    END FUNCTION;

    FUNCTION point_in_triangle_fast(
        px, py : INTEGER;
        x1, y1, x2, y2, x3, y3 : INTEGER
    ) RETURN BOOLEAN IS
        VARIABLE min_x : INTEGER;
        VARIABLE max_x : INTEGER;
        VARIABLE min_y : INTEGER;
        VARIABLE max_y : INTEGER;
    BEGIN
        min_x := min2(min2(x1, x2), x3);
        max_x := max2(max2(x1, x2), x3);
        min_y := min2(min2(y1, y2), y3);
        max_y := max2(max2(y1, y2), y3);

        IF (px < min_x) OR (px > max_x) OR (py < min_y) OR (py > max_y) THEN
            RETURN FALSE;
        END IF;
        RETURN is_point_in_triangle(px, py, x1, y1, x2, y2, x3, y3);
    END FUNCTION;

    FUNCTION render_lit_triangle_pixel(
        x, y : INTEGER;
        tri : triangle_t;
        base_color : color_t;
        light : light_t
    ) RETURN color_t IS
        VARIABLE shade_q8 : INTEGER;
    BEGIN
        IF point_in_triangle_fast(x, y, tri.x1, tri.y1, tri.x2, tri.y2, tri.x3, tri.y3) THEN
            shade_q8 := shade_from_normal_q8(tri.normal_x_q8, tri.normal_y_q8, tri.normal_z_q8, light);
            RETURN scale_color(base_color, shade_q8);
        END IF;
        RETURN TRANSPARENT;
    END FUNCTION;

    FUNCTION render_lit_cube_pixel(
        x, y : INTEGER;
        cube : cube_t;
        light : light_t
    ) RETURN color_t IS
        VARIABLE local_px : INTEGER;
        VARIABLE local_py : INTEGER;
        VARIABLE pixel_color : color_t;
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

        -- Visible-face triangle list: 2 front + 2 right + 2 top.
        -- This record can be reused by future meshes (e.g., torus).
        CONSTANT visible_face_triangles : triangle_scene_t(0 TO 5) := (
            0 => (x1 => f0_x, y1 => f0_y, x2 => f1_x, y2 => f1_y, x3 => f2_x, y3 => f2_y, normal_x_q8 =>   0, normal_y_q8 =>   0, normal_z_q8 => 256),
            1 => (x1 => f0_x, y1 => f0_y, x2 => f2_x, y2 => f2_y, x3 => f3_x, y3 => f3_y, normal_x_q8 =>   0, normal_y_q8 =>   0, normal_z_q8 => 256),
            2 => (x1 => f1_x, y1 => f1_y, x2 => f2_x, y2 => f2_y, x3 => b2_x, y3 => b2_y, normal_x_q8 => 256, normal_y_q8 =>   0, normal_z_q8 =>   0),
            3 => (x1 => f1_x, y1 => f1_y, x2 => b2_x, y2 => b2_y, x3 => b1_x, y3 => b1_y, normal_x_q8 => 256, normal_y_q8 =>   0, normal_z_q8 =>   0),
            4 => (x1 => f0_x, y1 => f0_y, x2 => f1_x, y2 => f1_y, x3 => b1_x, y3 => b1_y, normal_x_q8 =>   0, normal_y_q8 => 256, normal_z_q8 =>   0),
            5 => (x1 => f0_x, y1 => f0_y, x2 => b1_x, y2 => b1_y, x3 => b0_x, y3 => b0_y, normal_x_q8 =>   0, normal_y_q8 => 256, normal_z_q8 =>   0)
        );
    BEGIN
        -- Evaluate triangle coverage in cube local-space so scaling remains stable.
        local_px := cube.center_x + inv_scale_delta_q8(x - cube.center_x, cube.scale_x_q8);
        local_py := cube.center_y + inv_scale_delta_q8(y - cube.center_y, cube.scale_y_q8);

        FOR tri_idx IN visible_face_triangles'RANGE LOOP
            pixel_color := render_lit_triangle_pixel(
                local_px,
                local_py,
                visible_face_triangles(tri_idx),
                cube.color,
                light
            );
            IF NOT is_transparent(pixel_color) THEN
                RETURN pixel_color;
            END IF;
        END LOOP;

        -- Hidden faces (back/left/bottom) are intentionally not classified.
        RETURN TRANSPARENT;
    END FUNCTION;

END PACKAGE BODY RENDERING_PIPELINE;
