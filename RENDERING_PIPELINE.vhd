LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE work.GRAPHICS_TEST_UTILS.ALL;
USE work.transforms.ALL;

PACKAGE RENDERING_PIPELINE IS

    TYPE cube_t IS RECORD
        center_x : INTEGER;
        center_y : INTEGER;
        side_length : INTEGER;
        scale_x_q8 : INTEGER; -- 256 = 1.0x
        scale_y_q8 : INTEGER; -- 256 = 1.0x
        rotation_x : angle_t; -- 0..255 maps to 0..360°, tilt around local X
        rotation_y : angle_t; -- 0..255 maps to 0..360°, tilt around local Y
        rotation_z : angle_t; -- 0..255 maps to 0..360°, rotates about cube center
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
    FUNCTION render_lit_triangle_scene_pixel(
        x, y : INTEGER;
        triangles : triangle_scene_t;
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

    TYPE normal_q8_t IS RECORD
        x : INTEGER;
        y : INTEGER;
        z : INTEGER;
    END RECORD;

    FUNCTION rotate_normal_q8(
        nx, ny, nz : INTEGER;
        ax, ay, az : angle_t
    ) RETURN normal_q8_t IS
        VARIABLE cx : INTEGER;
        VARIABLE sx : INTEGER;
        VARIABLE cy : INTEGER;
        VARIABLE sy : INTEGER;
        VARIABLE cz : INTEGER;
        VARIABLE sz : INTEGER;
        VARIABLE x1, y1, z1 : INTEGER;
        VARIABLE x2, y2, z2 : INTEGER;
        VARIABLE out_n : normal_q8_t;
    BEGIN
        cx := to_integer(fp_cos(ax));
        sx := to_integer(fp_sin(ax));
        cy := to_integer(fp_cos(ay));
        sy := to_integer(fp_sin(ay));
        cz := to_integer(fp_cos(az));
        sz := to_integer(fp_sin(az));

        -- Rotate around X.
        x1 := nx;
        y1 := div_round_signed((cx * ny) - (sx * nz), 256);
        z1 := div_round_signed((sx * ny) + (cx * nz), 256);

        -- Rotate around Y.
        x2 := div_round_signed((cy * x1) + (sy * z1), 256);
        y2 := y1;
        z2 := div_round_signed(((-sy) * x1) + (cy * z1), 256);

        -- Rotate around Z.
        out_n.x := div_round_signed((cz * x2) - (sz * y2), 256);
        out_n.y := div_round_signed((sz * x2) + (cz * y2), 256);
        out_n.z := z2;
        RETURN out_n;
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

    FUNCTION render_lit_triangle_scene_pixel(
        x, y : INTEGER;
        triangles : triangle_scene_t;
        base_color : color_t;
        light : light_t
    ) RETURN color_t IS
        VARIABLE pixel_color : color_t;
    BEGIN
        FOR tri_idx IN triangles'RANGE LOOP
            pixel_color := render_lit_triangle_pixel(x, y, triangles(tri_idx), base_color, light);
            IF NOT is_transparent(pixel_color) THEN
                RETURN pixel_color;
            END IF;
        END LOOP;
        RETURN TRANSPARENT;
    END FUNCTION;

    FUNCTION render_lit_cube_pixel(
        x, y : INTEGER;
        cube : cube_t;
        light : light_t
    ) RETURN color_t IS
        VARIABLE local_px : INTEGER;
        VARIABLE local_py : INTEGER;
        VARIABLE local_dx : INTEGER;
        VARIABLE local_dy : INTEGER;
        VARIABLE rot_dx   : INTEGER;
        VARIABLE rot_dy   : INTEGER;
        VARIABLE cos_z_q8 : INTEGER;
        VARIABLE sin_z_q8 : INTEGER;
        VARIABLE cos_x_q8 : INTEGER;
        VARIABLE sin_x_q8 : INTEGER;
        VARIABLE cos_y_q8 : INTEGER;
        VARIABLE sin_y_q8 : INTEGER;
        VARIABLE pixel_color : color_t;
        VARIABLE half_side : INTEGER;
        VARIABLE half_w    : INTEGER;
        VARIABLE half_h    : INTEGER;
        VARIABLE depth_x   : INTEGER;
        VARIABLE depth_y   : INTEGER;
        VARIABLE f0_x, f0_y, f1_x, f1_y, f2_x, f2_y, f3_x, f3_y : INTEGER;
        VARIABLE b0_x, b0_y, b1_x, b1_y, b2_x, b2_y : INTEGER;
        VARIABLE front_n : normal_q8_t;
        VARIABLE right_n : normal_q8_t;
        VARIABLE top_n   : normal_q8_t;
        VARIABLE visible_face_triangles : triangle_scene_t(0 TO 5);
    BEGIN
        half_side := cube.side_length / 2;
        cos_x_q8 := to_integer(fp_cos(cube.rotation_x));
        sin_x_q8 := to_integer(fp_sin(cube.rotation_x));
        cos_y_q8 := to_integer(fp_cos(cube.rotation_y));
        sin_y_q8 := to_integer(fp_sin(cube.rotation_y));

        -- Approximate X/Y-axis tilt in screen-space by foreshortening the front face
        -- and skewing the back-face offset.
        half_w := max2(1, div_round_signed(half_side * abs(cos_y_q8), 256));
        half_h := max2(1, div_round_signed(half_side * abs(cos_x_q8), 256));
        depth_x := (cube.side_length / 3) + div_round_signed(cube.side_length * sin_y_q8, 1024);
        depth_y := (-cube.side_length / 4) - div_round_signed(cube.side_length * sin_x_q8, 1024);

        f0_x := cube.center_x - half_w;
        f0_y := cube.center_y - half_h;
        f1_x := cube.center_x + half_w;
        f1_y := cube.center_y - half_h;
        f2_x := cube.center_x + half_w;
        f2_y := cube.center_y + half_h;
        f3_x := cube.center_x - half_w;
        f3_y := cube.center_y + half_h;

        b0_x := f0_x + depth_x;
        b0_y := f0_y + depth_y;
        b1_x := f1_x + depth_x;
        b1_y := f1_y + depth_y;
        b2_x := f2_x + depth_x;
        b2_y := f2_y + depth_y;

        front_n := rotate_normal_q8(0, 0, 256, cube.rotation_x, cube.rotation_y, cube.rotation_z);
        right_n := rotate_normal_q8(256, 0, 0, cube.rotation_x, cube.rotation_y, cube.rotation_z);
        top_n := rotate_normal_q8(0, 256, 0, cube.rotation_x, cube.rotation_y, cube.rotation_z);

        -- Visible-face triangle list: 2 front + 2 right + 2 top.
        visible_face_triangles(0) := (
            x1 => f0_x, y1 => f0_y, x2 => f1_x, y2 => f1_y, x3 => f2_x, y3 => f2_y,
            normal_x_q8 => front_n.x, normal_y_q8 => front_n.y, normal_z_q8 => front_n.z
        );
        visible_face_triangles(1) := (
            x1 => f0_x, y1 => f0_y, x2 => f2_x, y2 => f2_y, x3 => f3_x, y3 => f3_y,
            normal_x_q8 => front_n.x, normal_y_q8 => front_n.y, normal_z_q8 => front_n.z
        );
        visible_face_triangles(2) := (
            x1 => f1_x, y1 => f1_y, x2 => f2_x, y2 => f2_y, x3 => b2_x, y3 => b2_y,
            normal_x_q8 => right_n.x, normal_y_q8 => right_n.y, normal_z_q8 => right_n.z
        );
        visible_face_triangles(3) := (
            x1 => f1_x, y1 => f1_y, x2 => b2_x, y2 => b2_y, x3 => b1_x, y3 => b1_y,
            normal_x_q8 => right_n.x, normal_y_q8 => right_n.y, normal_z_q8 => right_n.z
        );
        visible_face_triangles(4) := (
            x1 => f0_x, y1 => f0_y, x2 => f1_x, y2 => f1_y, x3 => b1_x, y3 => b1_y,
            normal_x_q8 => top_n.x, normal_y_q8 => top_n.y, normal_z_q8 => top_n.z
        );
        visible_face_triangles(5) := (
            x1 => f0_x, y1 => f0_y, x2 => b1_x, y2 => b1_y, x3 => b0_x, y3 => b0_y,
            normal_x_q8 => top_n.x, normal_y_q8 => top_n.y, normal_z_q8 => top_n.z
        );

        -- Evaluate triangle coverage in cube local-space so scaling remains stable.
        local_px := cube.center_x + inv_scale_delta_q8(x - cube.center_x, cube.scale_x_q8);
        local_py := cube.center_y + inv_scale_delta_q8(y - cube.center_y, cube.scale_y_q8);

        -- Rotate sample point by -theta around cube center so unrotated geometry
        -- tests represent a cube rotated by +theta about its own center.
        IF cube.rotation_z /= to_unsigned(0, cube.rotation_z'length) THEN
            cos_z_q8 := to_integer(fp_cos(cube.rotation_z));
            sin_z_q8 := to_integer(fp_sin(cube.rotation_z));
            local_dx := local_px - cube.center_x;
            local_dy := local_py - cube.center_y;
            rot_dx := div_round_signed((cos_z_q8 * local_dx) + (sin_z_q8 * local_dy), 256);
            rot_dy := div_round_signed(((-sin_z_q8) * local_dx) + (cos_z_q8 * local_dy), 256);
            local_px := cube.center_x + rot_dx;
            local_py := cube.center_y + rot_dy;
        END IF;

        pixel_color := render_lit_triangle_scene_pixel(
            local_px,
            local_py,
            visible_face_triangles,
            cube.color,
            light
        );
        RETURN pixel_color;
    END FUNCTION;

END PACKAGE BODY RENDERING_PIPELINE;
