-- ============================================================
-- SPHERE_RENDERING.vhd
-- ECE 4377 Final Project
--
-- Sphere object type + per-pixel lit sphere renderer.
-- Keep sphere-specific logic here so scene wiring stays clean.
-- ============================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.graphics_test_utils.all;
  use work.rendering_pipeline.all;

package sphere_rendering is

  type sphere_t is record
    center_x : integer;
    center_y : integer;
    radius   : integer;
    scale_x_q8 : integer; -- 256 = 1.0x
    scale_y_q8 : integer; -- 256 = 1.0x
    color    : color_t;
  end record;
  type sphere_scene_t is array (natural range <>) of sphere_t;

  function render_lit_sphere_pixel(
    x, y   : integer;
    sphere : sphere_t;
    light  : light_t
  ) return color_t;

  function render_lit_sphere_triangle_pixel(
    x, y   : integer;
    sphere : sphere_t;
    light  : light_t;
    triangle_count : integer
  ) return color_t;

  function render_wireframe_sphere_pixel(
    x, y      : integer;
    sphere    : sphere_t;
    thickness : integer
  ) return color_t;

end package sphere_rendering;

package body sphere_rendering is

  function div_round_signed(num, den : integer) return integer is
  begin
    if den = 0 then
      return 0;
    end if;

    if num >= 0 then
      return (num + (den / 2)) / den;
    else
      return -(((-num) + (den / 2)) / den);
    end if;
  end function;

  function scale_local_axis(local_q8, radius_px, scale_q8 : integer) return integer is
  begin
    -- local_q8 (Q8.8 unit sphere) * radius_px * scale_q8 (Q8.8) -> pixels.
    return div_round_signed(local_q8 * radius_px * scale_q8, 65536);
  end function;

  function abs_int(v : integer) return integer is
  begin
    if v < 0 then
      return -v;
    end if;
    return v;
  end function;

  function render_lit_sphere_pixel(
    x, y   : integer;
    sphere : sphere_t;
    light  : light_t
  ) return color_t is
    variable dx        : integer;
    variable dy        : integer;
    variable dx_local  : integer;
    variable dy_local  : integer;
    variable adx       : integer;
    variable ady       : integer;
    variable radius2   : integer;
    variable dist2     : integer;
    variable z_approx  : integer;
    variable dot_num   : integer;
    variable dot_q8    : integer;
    variable shade     : integer;
  begin
    if sphere.radius <= 0 then
      return TRANSPARENT;
    end if;

    dx := x - sphere.center_x;
    dy := y - sphere.center_y;
    dx_local := inv_scale_delta_q8(dx, sphere.scale_x_q8);
    dy_local := inv_scale_delta_q8(dy, sphere.scale_y_q8);
    radius2 := sphere.radius * sphere.radius;
    dist2 := dx_local * dx_local + dy_local * dy_local;

    if dist2 > radius2 then
      return TRANSPARENT;
    end if;

    -- Fast hemisphere depth approximation (no sqrt/divide by variable).
    adx := abs_int(dx_local);
    ady := abs_int(dy_local);
    z_approx := sphere.radius - ((adx + ady) / 2);
    if z_approx < 0 then
      z_approx := 0;
    end if;

    -- Approximate N · L in a timing-friendly way for pixel-rate combinational logic.
    dot_num := (dx_local * light.x_q8) + (dy_local * light.y_q8) + (z_approx * light.z_q8);
    if dot_num < 0 then
      dot_q8 := 0;
    else
      if sphere.radius <= 32 then
        dot_q8 := dot_num / 32;
      elsif sphere.radius <= 64 then
        dot_q8 := dot_num / 64;
      elsif sphere.radius <= 128 then
        dot_q8 := dot_num / 128;
      else
        dot_q8 := dot_num / 256;
      end if;
    end if;

    shade := shade_from_dot_q8(dot_q8, light);
    return scale_color(sphere.color, shade);
  end function;

  function render_lit_sphere_triangle_pixel(
    x, y   : integer;
    sphere : sphere_t;
    light  : light_t;
    triangle_count : integer
  ) return color_t is
    constant MAX_SPHERE_TRIANGLES : integer := 16;
    constant NORM_Z_Q8 : integer := 181; -- keeps front-hemisphere lighting stable
    type ring_arr_t is array (0 to MAX_SPHERE_TRIANGLES - 1) of integer;
    constant RING_X_Q8 : ring_arr_t := (
       256,  236,  181,   98,    0,  -98, -181, -236,
      -256, -236, -181,  -98,    0,   98,  181,  236
    );
    constant RING_Y_Q8 : ring_arr_t := (
         0,   98,  181,  236,  256,  236,  181,   98,
         0,  -98, -181, -236, -256, -236, -181,  -98
    );
    variable tri_count : integer;
    variable idx0      : integer;
    variable idx1      : integer;
    variable avg_x_q8  : integer;
    variable avg_y_q8  : integer;
    variable tri       : triangle_t;
    variable pixel_color : color_t;
  begin
    if sphere.radius <= 0 then
      return TRANSPARENT;
    end if;

    tri_count := triangle_count;
    if tri_count < 1 then
      tri_count := 1;
    elsif tri_count > MAX_SPHERE_TRIANGLES then
      tri_count := MAX_SPHERE_TRIANGLES;
    end if;

    for i in 0 to MAX_SPHERE_TRIANGLES - 1 loop
      if i < tri_count then
        -- Spread samples around the full ring so any triangle_count forms
        -- a closed front-hemisphere fan.
        idx0 := (i * MAX_SPHERE_TRIANGLES) / tri_count;
        idx1 := ((i + 1) * MAX_SPHERE_TRIANGLES) / tri_count;
        if idx1 >= MAX_SPHERE_TRIANGLES then
          idx1 := idx1 - MAX_SPHERE_TRIANGLES;
        end if;
        if idx1 = idx0 then
          idx1 := idx0 + 1;
          if idx1 >= MAX_SPHERE_TRIANGLES then
            idx1 := 0;
          end if;
        end if;

        tri.x1 := sphere.center_x;
        tri.y1 := sphere.center_y;
        tri.x2 := sphere.center_x + scale_local_axis(RING_X_Q8(idx0), sphere.radius, sphere.scale_x_q8);
        tri.y2 := sphere.center_y + scale_local_axis(RING_Y_Q8(idx0), sphere.radius, sphere.scale_y_q8);
        tri.x3 := sphere.center_x + scale_local_axis(RING_X_Q8(idx1), sphere.radius, sphere.scale_x_q8);
        tri.y3 := sphere.center_y + scale_local_axis(RING_Y_Q8(idx1), sphere.radius, sphere.scale_y_q8);

        avg_x_q8 := (RING_X_Q8(idx0) + RING_X_Q8(idx1)) / 2;
        avg_y_q8 := (RING_Y_Q8(idx0) + RING_Y_Q8(idx1)) / 2;
        tri.normal_x_q8 := avg_x_q8;
        tri.normal_y_q8 := avg_y_q8;
        tri.normal_z_q8 := NORM_Z_Q8;

        pixel_color := render_lit_triangle_pixel(x, y, tri, sphere.color, light);
        if (pixel_color.r /= x"00") or (pixel_color.g /= x"00") or (pixel_color.b /= x"00") then
          return pixel_color;
        end if;
      end if;
    end loop;

    return TRANSPARENT;
  end function;

  function render_wireframe_sphere_pixel(
    x, y      : integer;
    sphere    : sphere_t;
    thickness : integer
  ) return color_t is
    variable dx        : integer;
    variable dy        : integer;
    variable dx_local  : integer;
    variable dy_local  : integer;
    variable radius2   : integer;
    variable dist2     : integer;
    variable ring_dist : integer;
    variable ring_span : integer;
    variable t         : integer;
  begin
    if sphere.radius <= 0 then
      return TRANSPARENT;
    end if;

    dx := x - sphere.center_x;
    dy := y - sphere.center_y;
    dx_local := inv_scale_delta_q8(dx, sphere.scale_x_q8);
    dy_local := inv_scale_delta_q8(dy, sphere.scale_y_q8);
    radius2 := sphere.radius * sphere.radius;
    dist2 := dx_local * dx_local + dy_local * dy_local;

    if thickness < 1 then
      t := 1;
    else
      t := thickness;
    end if;

    -- Approximate |sqrt(dist2) - radius| <= t without sqrt:
    -- |dist2 - radius^2| <= 2 * radius * t
    ring_dist := abs_int(dist2 - radius2);
    ring_span := 2 * sphere.radius * t;

    if ring_dist <= ring_span then
      return sphere.color;
    end if;

    return TRANSPARENT;
  end function;

end package body sphere_rendering;
