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
  signal frame_cubes              : cube_scene_t(SCENE_CUBES'range) := SCENE_CUBES;
  signal frame_spheres            : sphere_scene_t(SCENE_SPHERES'range) := SCENE_SPHERES;

  signal vert_sync_s1       : std_logic := '0';
  signal vert_sync_s2       : std_logic := '0';
  signal vert_sync_prev     : std_logic := '0';

  type render_state_t is (
    RENDER_IDLE,
    RENDER_CUBE,
    RENDER_SPHERE_PREP,
    RENDER_SPHERE_SHADE
  );
  signal render_state  : render_state_t := RENDER_IDLE;

  signal pixel_x_r     : integer range 0 to 639 := 0;
  signal pixel_y_r     : integer range 0 to 479 := 0;
  signal work_color_r  : color_t := BACKGROUND_COLOR;
  signal render_color_r: color_t := BACKGROUND_COLOR;
  signal render_valid_r: std_logic := '0';

  signal sphere_idx_r        : integer range SCENE_SPHERES'low to SCENE_SPHERES'high := SCENE_SPHERES'high;
  signal sphere_dx_local_r   : integer := 0;
  signal sphere_dy_local_r   : integer := 0;
  signal sphere_z_r          : integer := 0;
  signal sphere_radius_r     : integer := 0;
  signal sphere_base_color_r : color_t := BACKGROUND_COLOR;

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

  function abs_int(v : integer) return integer is
  begin
    if v < 0 then
      return -v;
    end if;
    return v;
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
    x, y      : integer;
    show_cube : std_logic;
    cubes     : cube_scene_t
  ) return color_t is
    variable cube_ref : cube_t;
    variable color    : color_t;
    variable hit      : color_t;
  begin
    color := BACKGROUND_COLOR;
    if show_cube = '1' then
      for i in cubes'reverse_range loop
        cube_ref := cubes(i);
        hit := render_lit_cube_pixel(x, y, cube_ref, SCENE_LIGHT);
        if ((hit.r /= x"00") or (hit.g /= x"00") or (hit.b /= x"00")) then
          color := hit;
        end if;
      end loop;
    end if;
    return color;
  end function;

begin

  pipeline_proc : process (clk_50) is
    variable sphere_ref         : sphere_t;
    variable sample             : sphere_sample_t;
    variable work_color_v       : color_t;
    variable cube_color_v       : color_t;
    variable x_req              : integer range 0 to 639;
    variable y_req              : integer range 0 to 479;
    variable scale_num_frame    : integer range 1 to 4;
    variable scale_den_frame    : integer range 1 to 4;
    variable next_cube_phase    : integer range 0 to RGB_CYCLE_MAX;
    variable next_sphere_phase  : integer range 0 to RGB_CYCLE_MAX;
    variable cube_cycle_frame   : std_logic;
    variable sphere_cycle_frame : std_logic;
    variable transformed_cube   : cube_t;
    variable transformed_sphere : sphere_t;
    variable dx                 : integer;
    variable dy                 : integer;
    variable dx_local           : integer;
    variable dy_local           : integer;
    variable radius2            : integer;
    variable dist2              : integer;
    variable adx                : integer;
    variable ady                : integer;
    variable major              : integer;
    variable minor              : integer;
    variable radial_approx      : integer;
    variable z_approx           : integer;
    variable dot_num            : integer;
    variable dot_q8             : integer;
    variable shade              : integer;
  begin
    if rising_edge(clk_50) then
      render_valid_r <= '0';
      work_color_v := work_color_r;

      -- Sync vert_sync into clk_50 domain and sample controls once per frame.
      vert_sync_s1 <= vert_sync;
      vert_sync_s2 <= vert_sync_s1;
      if (vert_sync_s2 = '1') and (vert_sync_prev = '0') then
        frame_show_sphere <= show_sphere;
        frame_show_cube <= show_cube;

        cube_cycle_frame := cycle_cube_color;
        if cube_cycle_latched = '1' then
          cube_cycle_frame := '1';
        end if;
        sphere_cycle_frame := cycle_sphere_color;
        if sphere_cycle_latched = '1' then
          sphere_cycle_frame := '1';
        end if;

        next_cube_phase := cube_color_phase;
        if cycle_cube_color = '1' then
          next_cube_phase := next_rgb_phase(cube_color_phase);
          cube_color_phase <= next_cube_phase;
          cube_cycle_latched <= '1';
        end if;

        next_sphere_phase := sphere_color_phase;
        if cycle_sphere_color = '1' then
          next_sphere_phase := next_rgb_phase(sphere_color_phase);
          sphere_color_phase <= next_sphere_phase;
          sphere_cycle_latched <= '1';
        end if;

        scale_num_frame := zoom_scale_num(zoom_level);
        scale_den_frame := zoom_scale_den(zoom_level);

        for i in SCENE_CUBES'range loop
          transformed_cube := transform_cube(SCENE_CUBES(i), ROT_NONE_MAT, scale_num_frame, scale_den_frame, x_offset, y_offset);
          if cube_cycle_frame = '1' then
            transformed_cube.color := rgb_cycle_color(next_cube_phase);
          end if;
          frame_cubes(i) <= transformed_cube;
        end loop;

        for i in SCENE_SPHERES'range loop
          transformed_sphere := transform_sphere(SCENE_SPHERES(i), ROT_NONE_MAT, scale_num_frame, scale_den_frame, x_offset, y_offset);
          if sphere_cycle_frame = '1' then
            transformed_sphere.color := rgb_cycle_color(next_sphere_phase);
          end if;
          frame_spheres(i) <= transformed_sphere;
        end loop;
      end if;
      vert_sync_prev <= vert_sync_s2;

      case render_state is
        when RENDER_IDLE =>
          if render_req = '1' then
            x_req := to_integer(unsigned(pixel_column));
            y_req := to_integer(unsigned(pixel_row));
            pixel_x_r <= x_req;
            pixel_y_r <= y_req;
            render_state <= RENDER_CUBE;
          end if;

        when RENDER_CUBE =>
          cube_color_v := render_cubes_pixel(
            pixel_x_r, pixel_y_r,
            frame_show_cube,
            frame_cubes
          );
          work_color_v := cube_color_v;
          work_color_r <= work_color_v;

          if frame_show_sphere = '1' then
            sphere_idx_r <= SCENE_SPHERES'high;
            render_state <= RENDER_SPHERE_PREP;
          else
            render_color_r <= cube_color_v;
            render_valid_r <= '1';
            render_state <= RENDER_IDLE;
          end if;

        when RENDER_SPHERE_PREP =>
          sphere_ref := frame_spheres(sphere_idx_r);
          if SPHERE_WIREFRAME_MODE then
            sample := sample_wireframe_sphere_pixel(pixel_x_r, pixel_y_r, sphere_ref, 2);
            if sample.hit = '1' then
              work_color_v := sample.color;
              work_color_r <= work_color_v;
            end if;

            if sphere_idx_r = SCENE_SPHERES'low then
              render_color_r <= work_color_v;
              render_valid_r <= '1';
              render_state <= RENDER_IDLE;
            else
              sphere_idx_r <= sphere_idx_r - 1;
            end if;
          else
            if sphere_ref.radius <= 0 then
              if sphere_idx_r = SCENE_SPHERES'low then
                render_color_r <= work_color_v;
                render_valid_r <= '1';
                render_state <= RENDER_IDLE;
              else
                sphere_idx_r <= sphere_idx_r - 1;
              end if;
            else
              dx := pixel_x_r - sphere_ref.center_x;
              dy := pixel_y_r - sphere_ref.center_y;
              dx_local := inv_scale_delta_q8(dx, sphere_ref.scale_x_q8);
              dy_local := inv_scale_delta_q8(dy, sphere_ref.scale_y_q8);
              radius2 := sphere_ref.radius * sphere_ref.radius;
              dist2 := dx_local * dx_local + dy_local * dy_local;

              if dist2 > radius2 then
                if sphere_idx_r = SCENE_SPHERES'low then
                  render_color_r <= work_color_v;
                  render_valid_r <= '1';
                  render_state <= RENDER_IDLE;
                else
                  sphere_idx_r <= sphere_idx_r - 1;
                end if;
              else
                adx := abs_int(dx_local);
                ady := abs_int(dy_local);
                if adx >= ady then
                  major := adx;
                  minor := ady;
                else
                  major := ady;
                  minor := adx;
                end if;
                radial_approx := major + ((3 * minor) / 8);
                z_approx := sphere_ref.radius - radial_approx;
                if z_approx < 0 then
                  z_approx := 0;
                end if;

                sphere_dx_local_r <= dx_local;
                sphere_dy_local_r <= dy_local;
                sphere_z_r <= z_approx;
                sphere_radius_r <= sphere_ref.radius;
                sphere_base_color_r <= sphere_ref.color;
                render_state <= RENDER_SPHERE_SHADE;
              end if;
            end if;
          end if;

        when RENDER_SPHERE_SHADE =>
          dot_num := (sphere_dx_local_r * SCENE_LIGHT.x_q8) +
                     (sphere_dy_local_r * SCENE_LIGHT.y_q8) +
                     (sphere_z_r * SCENE_LIGHT.z_q8);
          if dot_num < 0 then
            dot_q8 := 0;
          else
            if sphere_radius_r <= 32 then
              dot_q8 := dot_num / 32;
            elsif sphere_radius_r <= 64 then
              dot_q8 := dot_num / 64;
            elsif sphere_radius_r <= 128 then
              dot_q8 := dot_num / 128;
            else
              dot_q8 := dot_num / 256;
            end if;
          end if;

          shade := shade_from_dot_q8(dot_q8, SCENE_LIGHT);
          work_color_v := scale_color(sphere_base_color_r, shade);
          work_color_r <= work_color_v;
          if sphere_idx_r = SCENE_SPHERES'low then
            render_color_r <= work_color_v;
            render_valid_r <= '1';
            render_state <= RENDER_IDLE;
          else
            sphere_idx_r <= sphere_idx_r - 1;
            render_state <= RENDER_SPHERE_PREP;
          end if;
      end case;
    end if;
  end process pipeline_proc;

  render_valid <= render_valid_r;
  red   <= render_color_r.r;
  green <= render_color_r.g;
  blue  <= render_color_r.b;

end architecture behavioral;
