-- ============================================================
-- DEFINE_OBJECTS.vhd
-- ECE 4377 Final Project
--
-- Central scene description. Edit this file to add, move, or
-- recolour cubes and to adjust the light without touching
-- GRAPHICS_LAYER or RENDERING_PIPELINE.
--
-- cube_t fields (defined in RENDERING_PIPELINE):
--   center_x, center_y  : screen-space centre (pixels)
--   side_length          : full side length (pixels)
--   scale_x_q8, scale_y_q8 : non-uniform scale in Q8.8 (256 = 1.0x)
--   rotation_z             : 8-bit angle (0..255 => 0..360 deg), about cube center
--   color                : RGB 8-bit per channel
--
-- light_t fields (defined in RENDERING_PIPELINE):
--   x_q8, y_q8, z_q8    : light direction, Q8 integers
--   ambient_q8           : ambient term  (0-255)
--   diffuse_q8           : diffuse scale (0-255)
--
-- To add a cube: append a SCENE entry.
-- To hide one:   set side_length => 0  (zero-size = invisible).
-- ============================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.graphics_test_utils.all;
  use work.rendering_pipeline.all;
  use work.sphere_rendering.all;

package define_objects is

  -- ── Light ────────────────────────────────────────────────
  -- Direction roughly upper-left-front; Q8 unit vector (magnitude ~256).
  -- Original (160, 110, 220) was unnormalized (mag ~293.5).
  -- Normalized: divide by 293.5 then scale by 256: (139, 96, 191)
  constant scene_light : light_t :=
  (
    x_q8       => 200,
    y_q8       => 200,
    z_q8       => 100,
    ambient_q8 => 88,
    diffuse_q8 => 224
  );

  constant background_color : color_t :=
  (
    r => x"00",
    g => x"00",
    b => x"00"
  );

  -- ── Cubes ────────────────────────────────────────────────
  -- Simple debug cube.
  constant scene : cube_scene_t :=
  (
    0 => (
      center_x => 240, center_y => 240, side_length => 96,
      scale_x_q8 => 256, scale_y_q8 => 256,
      rotation_z => to_unsigned(0, 8),
      color => (r => x"D0", g => x"40", b => x"40")
    )
  );

  -- ── Spheres ──────────────────────────────────────────────
  -- Debug rendering switch:
  --   true  => draw spheres as wireframe rings
  --   false => draw fully lit/shaded spheres
  constant sphere_wireframe_mode : boolean := false;

  -- To add a sphere: append a SCENE_SPHERES entry.
  -- To hide one:     set radius => 0  (zero-radius = invisible).
  constant scene_spheres : sphere_scene_t :=
  (
    -- index 0: simple sphere
    0 => (center_x => 410, center_y => 240, radius => 80, scale_x_q8 => 256, scale_y_q8 => 256, color => (r => x"40", g => x"C0", b => x"40"))
  );

end package define_objects;
