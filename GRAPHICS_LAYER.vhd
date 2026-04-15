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
    show_sphere  : in    std_logic;
    show_cube    : in    std_logic;
    rotate_left  : in    std_logic;
    rotate_right : in    std_logic;
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
  type cube_int_array_t is array (0 to NUM_CUBES - 1) of integer;
  type sphere_int_array_t is array (0 to NUM_SPHERES - 1) of integer;

  -- 16/256 turn = 22.5 degrees.
  constant ROT_STEP_ANGLE : angle_t := to_unsigned(16, 8);
  constant ROT_LEFT_MAT   : mat4 := make_rotate_z(ROT_STEP_ANGLE);
  constant ROT_RIGHT_MAT  : mat4 := make_rotate_z(to_unsigned(240, 8));

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

  function build_cube_rot_x(m : mat4) return cube_int_array_t is
    variable out_v : cube_int_array_t;
  begin
    for i in 0 to NUM_CUBES - 1 loop
      out_v(i) := rotated_x(SCENE(i).center_x, SCENE(i).center_y, m);
    end loop;
    return out_v;
  end function;

  function build_cube_rot_y(m : mat4) return cube_int_array_t is
    variable out_v : cube_int_array_t;
  begin
    for i in 0 to NUM_CUBES - 1 loop
      out_v(i) := rotated_y(SCENE(i).center_x, SCENE(i).center_y, m);
    end loop;
    return out_v;
  end function;

  function build_sphere_rot_x(m : mat4) return sphere_int_array_t is
    variable out_v : sphere_int_array_t;
  begin
    for i in 0 to NUM_SPHERES - 1 loop
      out_v(i) := rotated_x(SCENE_SPHERES(i).center_x, SCENE_SPHERES(i).center_y, m);
    end loop;
    return out_v;
  end function;

  function build_sphere_rot_y(m : mat4) return sphere_int_array_t is
    variable out_v : sphere_int_array_t;
  begin
    for i in 0 to NUM_SPHERES - 1 loop
      out_v(i) := rotated_y(SCENE_SPHERES(i).center_x, SCENE_SPHERES(i).center_y, m);
    end loop;
    return out_v;
  end function;

  constant CUBE_LEFT_X   : cube_int_array_t   := build_cube_rot_x(ROT_LEFT_MAT);
  constant CUBE_LEFT_Y   : cube_int_array_t   := build_cube_rot_y(ROT_LEFT_MAT);
  constant CUBE_RIGHT_X  : cube_int_array_t   := build_cube_rot_x(ROT_RIGHT_MAT);
  constant CUBE_RIGHT_Y  : cube_int_array_t   := build_cube_rot_y(ROT_RIGHT_MAT);
  constant SPHERE_LEFT_X : sphere_int_array_t := build_sphere_rot_x(ROT_LEFT_MAT);
  constant SPHERE_LEFT_Y : sphere_int_array_t := build_sphere_rot_y(ROT_LEFT_MAT);
  constant SPHERE_RIGHT_X : sphere_int_array_t := build_sphere_rot_x(ROT_RIGHT_MAT);
  constant SPHERE_RIGHT_Y : sphere_int_array_t := build_sphere_rot_y(ROT_RIGHT_MAT);

begin

  x <= to_integer(unsigned(pixel_column));
  y <= to_integer(unsigned(pixel_row));

  -- Render all cubes in SCENE with flat shading from SCENE_LIGHT.
  -- Front-to-back priority: index 0 is drawn on top.
  -- Walk back-to-front (highest index first) so index 0 overwrites last.
  -- Spheres are then composited with the same per-index priority.
  -- zoom_level and x/y_offset are applied before each draw call so
  -- the scene can be panned and zoomed at run-time via BUTTON_CONTROL.
  render_proc : process (x, y, show_sphere, show_cube, rotate_left, rotate_right, x_offset, y_offset, zoom_level) is

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
    variable cube_center_x   : integer;
    variable cube_center_y   : integer;
    variable sphere_center_x : integer;
    variable sphere_center_y : integer;

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
      for i in NUM_CUBES - 1 downto 0 loop

        -- Apply zoom (around screen centre 320,240) then pan offset.
        -- Offset is in screen-space so panning distance is independent of zoom.
        if (rotate_left = '1') and (rotate_right = '0') then
          cube_center_x := CUBE_LEFT_X(i);
          cube_center_y := CUBE_LEFT_Y(i);
        elsif (rotate_right = '1') and (rotate_left = '0') then
          cube_center_x := CUBE_RIGHT_X(i);
          cube_center_y := CUBE_RIGHT_Y(i);
        else
          cube_center_x := SCENE(i).center_x;
          cube_center_y := SCENE(i).center_y;
        end if;

        scaled_cube := (
          center_x    => SCREEN_CX + (cube_center_x - SCREEN_CX) * scale_num / scale_den + x_offset,
          center_y    => SCREEN_CY + (cube_center_y - SCREEN_CY) * scale_num / scale_den + y_offset,
          side_length => SCENE(i).side_length * scale_num / scale_den,
          scale_x_q8  => SCENE(i).scale_x_q8,
          scale_y_q8  => SCENE(i).scale_y_q8,
          color       => SCENE(i).color
        );

        hit := render_lit_cube_pixel(x, y, scaled_cube, SCENE_LIGHT);

        if ((hit.r /= x"00") or (hit.g /= x"00") or (hit.b /= x"00")) then
          color := hit;
        end if;

      end loop;
    end if;

    if show_sphere = '1' then
      for i in NUM_SPHERES - 1 downto 0 loop

        if (rotate_left = '1') and (rotate_right = '0') then
          sphere_center_x := SPHERE_LEFT_X(i);
          sphere_center_y := SPHERE_LEFT_Y(i);
        elsif (rotate_right = '1') and (rotate_left = '0') then
          sphere_center_x := SPHERE_RIGHT_X(i);
          sphere_center_y := SPHERE_RIGHT_Y(i);
        else
          sphere_center_x := SCENE_SPHERES(i).center_x;
          sphere_center_y := SCENE_SPHERES(i).center_y;
        end if;

        scaled_sphere := (
          center_x => SCREEN_CX + (sphere_center_x - SCREEN_CX) * scale_num / scale_den + x_offset,
          center_y => SCREEN_CY + (sphere_center_y - SCREEN_CY) * scale_num / scale_den + y_offset,
          radius   => SCENE_SPHERES(i).radius * scale_num / scale_den,
          scale_x_q8 => SCENE_SPHERES(i).scale_x_q8,
          scale_y_q8 => SCENE_SPHERES(i).scale_y_q8,
          color    => SCENE_SPHERES(i).color
        );

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
