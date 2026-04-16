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
  use work.graphics_test_utils.all;
  use work.rendering_pipeline.all;
  use work.sphere_rendering.all;
  use work.define_objects.all;

entity graphics_layer is
  port (
    clk_50       : in    std_logic;
    pixel_row    : in    std_logic_vector(9 downto 0);
    pixel_column : in    std_logic_vector(9 downto 0);
    vert_sync    : in    std_logic;
    show_sphere  : in    std_logic;
    show_cube    : in    std_logic;
    cycle_cube_color   : in    std_logic;
    cycle_sphere_color : in    std_logic;
    render_req    : in    std_logic;
    -- Pan/zoom controls (driven by BUTTON_CONTROL)
    x_offset     : in    integer range -320 to 320;
    y_offset     : in    integer range -240 to 240;
    zoom_level   : in    integer range 0 to 4;
    render_valid : out   std_logic;
    red          : out   std_logic_vector(7 downto 0);
    green        : out   std_logic_vector(7 downto 0);
    blue         : out   std_logic_vector(7 downto 0)
  );
end entity graphics_layer;

architecture behavioral of graphics_layer is

  constant SCREEN_CX : integer := 320;
  constant SCREEN_CY : integer := 240;
  constant RGB_CYCLE_MAX  : integer := 767;
  constant RGB_CYCLE_STEP : integer := 2;

  constant ROT_NONE_MAT   : mat4 := IDENTITY_MAT4;
  signal cube_color_phase   : integer range 0 to RGB_CYCLE_MAX := 0;
  signal sphere_color_phase : integer range 0 to RGB_CYCLE_MAX := 0;
  signal cube_cycle_latched   : std_logic := '0';
  signal sphere_cycle_latched : std_logic := '0';

  signal frame_show_sphere        : std_logic := '1';
  signal frame_show_cube          : std_logic := '1';
  signal frame_cycle_cube_color   : std_logic := '0';
  signal frame_cycle_sphere_color : std_logic := '0';
  signal frame_x_offset           : integer range -320 to 320 := 0;
  signal frame_y_offset           : integer range -240 to 240 := 0;
  signal frame_zoom_level         : integer range 0 to 4 := 2;

  signal vert_sync_s1       : std_logic := '0';
  signal vert_sync_s2       : std_logic := '0';
  signal vert_sync_prev     : std_logic := '0';

  signal req_s0        : std_logic := '0';
  signal req_s1        : std_logic := '0';
  signal x_s0          : integer range 0 to 639 := 0;
  signal y_s0          : integer range 0 to 479 := 0;
  signal x_s1          : integer range 0 to 639 := 0;
  signal y_s1          : integer range 0 to 479 := 0;
  signal scale_num_s0  : integer range 1 to 4 := 1;
  signal scale_den_s0  : integer range 1 to 4 := 1;
  signal scale_num_s1  : integer range 1 to 4 := 1;
  signal scale_den_s1  : integer range 1 to 4 := 1;
  signal cube_color_s1 : color_t := BACKGROUND_COLOR;
  signal render_color_r: color_t := BACKGROUND_COLOR;
  signal render_valid_r: std_logic := '0';

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

  function zoom_scale_num(level : integer) return integer is
  begin
    case level is
      when 0      => return 1;
      when 1      => return 1;
      when 3      => return 2;
      when 4      => return 4;
      when others => return 1; -- zoom_level 2: normal
    end case;
  end function;

  function zoom_scale_den(level : integer) return integer is
  begin
    case level is
      when 0      => return 4;
      when 1      => return 2;
      when others => return 1;
    end case;
  end function;

  function cycle_active(cycle_sw, latched : std_logic) return std_logic is
  begin
    if (cycle_sw = '1') or (latched = '1') then
      return '1';
    end if;
    return '0';
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

  function render_cubes_pixel(
    x, y                         : integer;
    show_cube                    : std_logic;
    cycle_cube                   : std_logic;
    cube_phase                   : integer;
    scale_num, scale_den         : integer;
    x_offset, y_offset           : integer
  ) return color_t is
    variable scaled_cube : cube_t;
    variable color       : color_t;
    variable hit         : color_t;
  begin
    color := BACKGROUND_COLOR;
    if show_cube = '1' then
      for i in SCENE'reverse_range loop
        scaled_cube := transform_cube(SCENE(i), ROT_NONE_MAT, scale_num, scale_den, x_offset, y_offset);
        if cycle_cube = '1' then
          scaled_cube.color := rgb_cycle_color(cube_phase);
        end if;

        hit := render_lit_cube_pixel(x, y, scaled_cube, SCENE_LIGHT);
        if ((hit.r /= x"00") or (hit.g /= x"00") or (hit.b /= x"00")) then
          color := hit;
        end if;
      end loop;
    end if;
    return color;
  end function;

  function render_spheres_over_pixel(
    x, y                         : integer;
    base_color                   : color_t;
    show_sphere                  : std_logic;
    cycle_sphere                 : std_logic;
    sphere_phase                 : integer;
    scale_num, scale_den         : integer;
    x_offset, y_offset           : integer
  ) return color_t is
    variable scaled_sphere : sphere_t;
    variable sample        : sphere_sample_t;
    variable color         : color_t;
  begin
    color := base_color;
    if show_sphere = '1' then
      for i in SCENE_SPHERES'reverse_range loop
        scaled_sphere := transform_sphere(SCENE_SPHERES(i), ROT_NONE_MAT, scale_num, scale_den, x_offset, y_offset);
        if cycle_sphere = '1' then
          scaled_sphere.color := rgb_cycle_color(sphere_phase);
        end if;

        if SPHERE_WIREFRAME_MODE then
          sample := sample_wireframe_sphere_pixel(x, y, scaled_sphere, 2);
        else
          sample := sample_lit_sphere_pixel(x, y, scaled_sphere, SCENE_LIGHT);
        end if;

        if sample.hit = '1' then
          color := sample.color;
        end if;
      end loop;
    end if;
    return color;
  end function;

begin

  pipeline_proc : process (clk_50) is
    variable stage2_color      : color_t;
    variable cube_cycle_enable : std_logic;
    variable sph_cycle_enable  : std_logic;
    variable x_req             : integer range 0 to 639;
    variable y_req             : integer range 0 to 479;
  begin
    if rising_edge(clk_50) then
      render_valid_r <= '0';

      -- Sync vert_sync into clk_50 domain and sample controls once per frame.
      vert_sync_s1 <= vert_sync;
      vert_sync_s2 <= vert_sync_s1;
      if (vert_sync_s2 = '1') and (vert_sync_prev = '0') then
        frame_show_sphere <= show_sphere;
        frame_show_cube <= show_cube;
        frame_cycle_cube_color <= cycle_cube_color;
        frame_cycle_sphere_color <= cycle_sphere_color;
        frame_x_offset <= x_offset;
        frame_y_offset <= y_offset;
        frame_zoom_level <= zoom_level;

        if cycle_cube_color = '1' then
          cube_color_phase <= next_rgb_phase(cube_color_phase);
          cube_cycle_latched <= '1';
        end if;

        if cycle_sphere_color = '1' then
          sphere_color_phase <= next_rgb_phase(sphere_color_phase);
          sphere_cycle_latched <= '1';
        end if;
      end if;
      vert_sync_prev <= vert_sync_s2;

      -- Stage 2: sphere composite + final output register.
      if req_s1 = '1' then
        sph_cycle_enable := cycle_active(frame_cycle_sphere_color, sphere_cycle_latched);
        stage2_color := render_spheres_over_pixel(
          x_s1, y_s1, cube_color_s1,
          frame_show_sphere,
          sph_cycle_enable,
          sphere_color_phase,
          scale_num_s1, scale_den_s1,
          frame_x_offset, frame_y_offset
        );
        render_color_r <= stage2_color;
        render_valid_r <= '1';
      end if;

      -- Stage 1: cube pass register.
      req_s1 <= req_s0;
      x_s1 <= x_s0;
      y_s1 <= y_s0;
      scale_num_s1 <= scale_num_s0;
      scale_den_s1 <= scale_den_s0;
      if req_s0 = '1' then
        cube_cycle_enable := cycle_active(frame_cycle_cube_color, cube_cycle_latched);
        cube_color_s1 <= render_cubes_pixel(
          x_s0, y_s0,
          frame_show_cube,
          cube_cycle_enable,
          cube_color_phase,
          scale_num_s0, scale_den_s0,
          frame_x_offset, frame_y_offset
        );
      end if;

      -- Stage 0: request capture.
      if render_req = '1' then
        x_req := to_integer(unsigned(pixel_column));
        y_req := to_integer(unsigned(pixel_row));
        req_s0 <= '1';
        x_s0 <= x_req;
        y_s0 <= y_req;
        scale_num_s0 <= zoom_scale_num(frame_zoom_level);
        scale_den_s0 <= zoom_scale_den(frame_zoom_level);
      else
        req_s0 <= '0';
      end if;
    end if;
  end process pipeline_proc;

  render_valid <= render_valid_r;
  red   <= render_color_r.r;
  green <= render_color_r.g;
  blue  <= render_color_r.b;

end architecture behavioral;
