-- ============================================================
-- GRAPHICS_LAYER.vhd
-- ECE 4377 Final Project
--
-- Top-level pixel renderer. Reads the scene (cubes + light)
-- entirely from DEFINE_OBJECTS — nothing is hardcoded here.
--
-- To change the scene, edit DEFINE_OBJECTS.vhd only.
-- ============================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.types.all;
  use work.transforms.all;
  use work.graphics_test_utils.all;
  use work.rendering_pipeline.all;
  use work.sphere_rendering.all;
  use work.define_objects.all;

entity graphics_layer is
  port (
    pixel_row    : in    std_logic_vector(9 downto 0);
    pixel_column : in    std_logic_vector(9 downto 0);
    vert_sync    : in    std_logic;
    anim_tick    : in    std_logic;
    show_sphere  : in    std_logic;
    show_cube    : in    std_logic;
    cycle_cube_color   : in    std_logic;
    cycle_sphere_color : in    std_logic;
    rotate_cube_cw     : in    std_logic;
    rotate_cube_ccw    : in    std_logic;
    -- Pan/zoom controls (driven by BUTTON_CONTROL)
    x_offset     : in    integer range -320 to 320;
    y_offset     : in    integer range -240 to 240;
    zoom_level   : in    integer range 0 to 4;
    red          : out   std_logic_vector(7 downto 0);
    green        : out   std_logic_vector(7 downto 0);
    blue         : out   std_logic_vector(7 downto 0)
  );
end entity graphics_layer;

architecture behavioral of graphics_layer is

  signal x           : integer range 0 to 639;
  signal y           : integer range 0 to 479;
  signal pixel_color : color_t;
  constant SCREEN_CX : integer := 320;
  constant SCREEN_CY : integer := 240;
  constant RGB_CYCLE_MAX  : integer := 767;
  constant RGB_CYCLE_STEP : integer := 2;
  constant ANGLE_CYCLE_MAX  : integer := 255;
  constant ANGLE_CYCLE_STEP : integer := 1;

  constant ROT_NONE_MAT   : mat4 := IDENTITY_MAT4;
  signal cube_color_phase   : integer range 0 to RGB_CYCLE_MAX := 0;
  signal sphere_color_phase : integer range 0 to RGB_CYCLE_MAX := 0;
  signal cube_rotation_phase : integer range 0 to ANGLE_CYCLE_MAX := 0;
  signal cube_cycle_color    : color_t := (r => x"FF", g => x"00", b => x"00");
  signal sphere_cycle_color  : color_t := (r => x"FF", g => x"00", b => x"00");

  function div_round_signed_256(num : integer) return integer is
  begin
    if num >= 0 then
      return (num + 128) / 256;
    else
      return -(((-num) + 128) / 256);
    end if;
  end function;

  function q8_mul_int(coeff : fp; val : integer) return integer is
  begin
    return div_round_signed_256(to_integer(coeff) * val);
  end function;

  function clamp_u8_local(v : integer) return integer is
  begin
    if v < 0 then
      return 0;
    elsif v > 255 then
      return 255;
    end if;
    return v;
  end function;

  function next_rgb_phase(phase : integer) return integer is
    variable p : integer;
  begin
    p := phase + RGB_CYCLE_STEP;
    if p > RGB_CYCLE_MAX then
      return p - (RGB_CYCLE_MAX + 1);
    end if;
    return p;
  end function;

  function next_angle_phase(phase : integer) return integer is
    variable p : integer;
  begin
    p := phase + ANGLE_CYCLE_STEP;
    if p > ANGLE_CYCLE_MAX then
      return p - (ANGLE_CYCLE_MAX + 1);
    end if;
    return p;
  end function;

  function prev_angle_phase(phase : integer) return integer is
  begin
    if phase < ANGLE_CYCLE_STEP then
      return phase + (ANGLE_CYCLE_MAX + 1) - ANGLE_CYCLE_STEP;
    end if;
    return phase - ANGLE_CYCLE_STEP;
  end function;

  function add_angle_phase(base_angle : angle_t; phase : integer) return angle_t is
  begin
    return base_angle + to_unsigned(phase, base_angle'length);
  end function;

  function rgb_cycle_color(phase : integer) return color_t is
    variable p : integer;
    variable t : integer;
    variable r : integer;
    variable g : integer;
    variable b : integer;
  begin
    if phase < 0 then
      p := 0;
    elsif phase > RGB_CYCLE_MAX then
      p := RGB_CYCLE_MAX;
    else
      p := phase;
    end if;

    if p < 256 then
      r := 255 - p;
      g := p;
      b := 0;
    elsif p < 512 then
      t := p - 256;
      r := 0;
      g := 255 - t;
      b := t;
    else
      t := p - 512;
      r := t;
      g := 0;
      b := 255 - t;
    end if;

    return (
      r => std_logic_vector(to_unsigned(clamp_u8_local(r), 8)),
      g => std_logic_vector(to_unsigned(clamp_u8_local(g), 8)),
      b => std_logic_vector(to_unsigned(clamp_u8_local(b), 8))
    );
  end function;

  function rotated_x(px, py : integer; m : mat4) return integer is
    variable dx : integer;
    variable dy : integer;
  begin
    dx := px - SCREEN_CX;
    dy := py - SCREEN_CY;
    return SCREEN_CX + q8_mul_int(m(0, 0), dx) + q8_mul_int(m(0, 1), dy);
  end function;

  function rotated_y(px, py : integer; m : mat4) return integer is
    variable dx : integer;
    variable dy : integer;
  begin
    dx := px - SCREEN_CX;
    dy := py - SCREEN_CY;
    return SCREEN_CY + q8_mul_int(m(1, 0), dx) + q8_mul_int(m(1, 1), dy);
  end function;

  function transform_cube(
    base_cube : cube_t;
    m : mat4;
    scale_num, scale_den, x_offset, y_offset : integer
  ) return cube_t is
    variable out_cube : cube_t;
    variable cx_rot   : integer;
    variable cy_rot   : integer;
  begin
    cx_rot := rotated_x(base_cube.center_x, base_cube.center_y, m);
    cy_rot := rotated_y(base_cube.center_x, base_cube.center_y, m);
    out_cube := base_cube;
    out_cube.center_x := SCREEN_CX + (cx_rot - SCREEN_CX) * scale_num / scale_den + x_offset;
    out_cube.center_y := SCREEN_CY + (cy_rot - SCREEN_CY) * scale_num / scale_den + y_offset;
    out_cube.side_length := base_cube.side_length * scale_num / scale_den;
    return out_cube;
  end function;

  function transform_sphere(
    base_sphere : sphere_t;
    m : mat4;
    scale_num, scale_den, x_offset, y_offset : integer
  ) return sphere_t is
    variable out_sphere : sphere_t;
    variable cx_rot     : integer;
    variable cy_rot     : integer;
  begin
    cx_rot := rotated_x(base_sphere.center_x, base_sphere.center_y, m);
    cy_rot := rotated_y(base_sphere.center_x, base_sphere.center_y, m);
    out_sphere := base_sphere;
    out_sphere.center_x := SCREEN_CX + (cx_rot - SCREEN_CX) * scale_num / scale_den + x_offset;
    out_sphere.center_y := SCREEN_CY + (cy_rot - SCREEN_CY) * scale_num / scale_den + y_offset;
    out_sphere.radius := base_sphere.radius * scale_num / scale_den;
    return out_sphere;
  end function;

begin

  x <= to_integer(unsigned(pixel_column));
  y <= to_integer(unsigned(pixel_row));

  color_cycle_proc : process (anim_tick) is
    variable next_cube_color_phase   : integer;
    variable next_sphere_color_phase : integer;
  begin
    if rising_edge(anim_tick) then
      next_cube_color_phase := cube_color_phase;
      next_sphere_color_phase := sphere_color_phase;

      if cycle_cube_color = '1' then
        next_cube_color_phase := next_rgb_phase(cube_color_phase);
      end if;

      if cycle_sphere_color = '1' then
        next_sphere_color_phase := next_rgb_phase(sphere_color_phase);
      end if;

      cube_color_phase <= next_cube_color_phase;
      sphere_color_phase <= next_sphere_color_phase;
      cube_cycle_color <= rgb_cycle_color(next_cube_color_phase);
      sphere_cycle_color <= rgb_cycle_color(next_sphere_color_phase);

      if rotate_cube_cw = '1' and rotate_cube_ccw = '0' then
        cube_rotation_phase <= next_angle_phase(cube_rotation_phase);
      elsif rotate_cube_ccw = '1' and rotate_cube_cw = '0' then
        cube_rotation_phase <= prev_angle_phase(cube_rotation_phase);
      end if;
    end if;
  end process color_cycle_proc;

  -- Render all cubes in SCENE with flat shading from SCENE_LIGHT.
  -- Front-to-back priority: index 0 is drawn on top.
  -- Walk back-to-front (highest index first) so index 0 overwrites last.
  -- Spheres are then composited with the same per-index priority.
  -- zoom_level and x/y_offset are applied before each draw call so
  -- the scene can be panned and zoomed at run-time via BUTTON_CONTROL.
  render_proc : process (
    x, y, show_sphere, show_cube, cycle_cube_color, cycle_sphere_color,
    cube_cycle_color, sphere_cycle_color, cube_rotation_phase,
    x_offset, y_offset, zoom_level
  ) is

    -- Scale factors derived from zoom_level:
    --   zoom_level 0 => 0.25x (scale_num=1, scale_den=4)
    --   zoom_level 1 => 0.50x (scale_num=1, scale_den=2)
    --   zoom_level 2 => 1.00x (scale_num=1, scale_den=1)  ← default
    --   zoom_level 3 => 2.00x (scale_num=2, scale_den=1)
    --   zoom_level 4 => 4.00x (scale_num=4, scale_den=1)
    variable scale_num     : integer;
    variable scale_den     : integer;

    -- Temporaries for transformed object geometry
    variable scaled_cube   : cube_t;
    variable scaled_sphere : sphere_t;
    variable color : color_t;
    variable hit   : color_t;

  begin

    -- ── Pick scale numerator / denominator ──────────────────
    case zoom_level is
      when 0      => scale_num := 1; scale_den := 4;
      when 1      => scale_num := 1; scale_den := 2;
      when 3      => scale_num := 2; scale_den := 1;
      when 4      => scale_num := 4; scale_den := 1;
      when others => scale_num := 1; scale_den := 1;   -- zoom_level 2: normal
    end case;

    color := BACKGROUND_COLOR;

    if show_cube = '1' then
      for i in SCENE'reverse_range loop
        scaled_cube := transform_cube(SCENE(i), ROT_NONE_MAT, scale_num, scale_den, x_offset, y_offset);
        scaled_cube.rotation_z := add_angle_phase(scaled_cube.rotation_z, cube_rotation_phase);
        if cycle_cube_color = '1' then
          scaled_cube.color := cube_cycle_color;
        end if;

        hit := render_lit_cube_pixel(x, y, scaled_cube, SCENE_LIGHT);

        if ((hit.r /= x"00") or (hit.g /= x"00") or (hit.b /= x"00")) then
          color := hit;
        end if;

      end loop;
    end if;

    if show_sphere = '1' then
      for i in SCENE_SPHERES'reverse_range loop
        scaled_sphere := transform_sphere(SCENE_SPHERES(i), ROT_NONE_MAT, scale_num, scale_den, x_offset, y_offset);
        if cycle_sphere_color = '1' then
          scaled_sphere.color := sphere_cycle_color;
        end if;

        if SPHERE_WIREFRAME_MODE then
          hit := render_wireframe_sphere_pixel(x, y, scaled_sphere, 2);
        else
          hit := render_lit_sphere_pixel(x, y, scaled_sphere, SCENE_LIGHT);
        end if;

        if ((hit.r /= x"00") or (hit.g /= x"00") or (hit.b /= x"00")) then
          color := hit;
        end if;

      end loop;
    end if;

    pixel_color <= color;

  end process render_proc;

  red   <= pixel_color.r;
  green <= pixel_color.g;
  blue  <= pixel_color.b;

end architecture behavioral;
