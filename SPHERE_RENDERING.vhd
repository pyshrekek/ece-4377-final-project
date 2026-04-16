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

  function render_wireframe_sphere_pixel(
    x, y      : integer;
    sphere    : sphere_t;
    thickness : integer
  ) return color_t;

end package sphere_rendering;

package body sphere_rendering is

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
