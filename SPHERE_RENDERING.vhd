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

  function int_sqrt(n : integer) return integer;

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

  function clamp_u8(v : integer) return integer is
  begin
    if v < 0 then
      return 0;
    elsif v > 255 then
      return 255;
    end if;
    return v;
  end function;

  function abs_int(v : integer) return integer is
  begin
    if v < 0 then
      return -v;
    end if;
    return v;
  end function;

  function clamp_scale_q8(scale_q8 : integer) return integer is
  begin
    if scale_q8 < 1 then
      return 1;
    end if;
    return scale_q8;
  end function;

  function inv_scale_delta_q8(delta_px, scale_q8 : integer) return integer is
    variable s : integer;
  begin
    s := clamp_scale_q8(scale_q8);
    return div_round_signed(delta_px * 256, s);
  end function;

  function to_slv8(v : integer) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(clamp_u8(v), 8));
  end function;

  function scale_color(base_color : color_t; shade_q8 : integer) return color_t is
    variable base_r : integer;
    variable base_g : integer;
    variable base_b : integer;
    variable shade  : integer;
  begin
    base_r := to_integer(unsigned(base_color.r));
    base_g := to_integer(unsigned(base_color.g));
    base_b := to_integer(unsigned(base_color.b));
    shade := clamp_u8(shade_q8);

    return (
      -- /256 keeps this path to shifts/adds in synthesis.
      r => to_slv8((base_r * shade + 128) / 256),
      g => to_slv8((base_g * shade + 128) / 256),
      b => to_slv8((base_b * shade + 128) / 256)
    );
  end function;

  function int_sqrt(n : integer) return integer is
    variable val : unsigned(31 downto 0);
    variable res : unsigned(31 downto 0) := (others => '0');
    variable bit : unsigned(31 downto 0) := to_unsigned(1073741824, 32); -- 1 << 30
  begin
    if n <= 0 then
      return 0;
    end if;

    val := to_unsigned(n, 32);

    -- Find the highest power-of-4 <= val.
    for i in 0 to 15 loop
      if bit > val then
        bit := shift_right(bit, 2);
      end if;
    end loop;

    -- Restoring integer sqrt: fixed maximum of 16 iterations for 32-bit input.
    for i in 0 to 15 loop
      if bit = 0 then
        exit;
      end if;

      if val >= (res + bit) then
        val := val - (res + bit);
        res := shift_right(res, 1) + bit;
      else
        res := shift_right(res, 1);
      end if;

      bit := shift_right(bit, 2);
    end loop;

    return to_integer(res);
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
    variable diff_term : integer;
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

      if dot_q8 < 0 then
        dot_q8 := 0;
      elsif dot_q8 > 255 then
        dot_q8 := 255;
      end if;
    end if;

    diff_term := (dot_q8 * light.diffuse_q8 + 128) / 256;
    shade := light.ambient_q8 + diff_term;
    return scale_color(sphere.color, clamp_u8(shade));
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
