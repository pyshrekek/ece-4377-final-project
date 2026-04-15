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

begin

  x <= to_integer(unsigned(pixel_column));
  y <= to_integer(unsigned(pixel_row));

  -- Render all cubes in SCENE with flat shading from SCENE_LIGHT.
  -- Front-to-back priority: index 0 is drawn on top.
  -- Walk back-to-front (highest index first) so index 0 overwrites last.
  -- Spheres are then composited with the same per-index priority.
  -- zoom_level and x/y_offset are applied before each draw call so
  -- the scene can be panned and zoomed at run-time via BUTTON_CONTROL.
  render_proc : process (x, y, show_sphere, show_cube, x_offset, y_offset, zoom_level) is

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
      for i in NUM_CUBES - 1 downto 0 loop

        -- Apply zoom (around screen centre 320,240) then pan offset.
        -- Offset is in screen-space so panning distance is independent of zoom.
        scaled_cube := (
          center_x    => 320 + (SCENE(i).center_x - 320) * scale_num / scale_den + x_offset,
          center_y    => 240 + (SCENE(i).center_y - 240) * scale_num / scale_den + y_offset,
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

        scaled_sphere := (
          center_x => 320 + (SCENE_SPHERES(i).center_x - 320) * scale_num / scale_den + x_offset,
          center_y => 240 + (SCENE_SPHERES(i).center_y - 240) * scale_num / scale_den + y_offset,
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
