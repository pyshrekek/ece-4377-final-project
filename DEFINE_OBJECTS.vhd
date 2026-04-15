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
--   color                : RGB 8-bit per channel
--
-- light_t fields (defined in RENDERING_PIPELINE):
--   x_q8, y_q8, z_q8    : light direction, Q8 integers
--   ambient_q8           : ambient term  (0-255)
--   diffuse_q8           : diffuse scale (0-255)
--
-- To add a cube: increment NUM_CUBES and append a SCENE entry.
-- To hide one:   set side_length => 0  (zero-size = invisible).
-- ============================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.graphics_test_utils.all;
  use work.types.all;
  use work.transforms.all;
  use work.rendering_pipeline.all;
  use work.sphere_rendering.all;

package define_objects is

  -- ── Light ────────────────────────────────────────────────
  -- Direction roughly upper-left-front; Q8 unit vector (magnitude ~256).
  -- Original (160, 110, 220) was unnormalized (mag ~293.5).
  -- Normalized: divide by 293.5 then scale by 256: (139, 96, 191)
  constant scene_light : light_t :=
  (
    x_q8       => 139,
    y_q8       => 96,
    z_q8       => 191,
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
  -- Face eyes: two cubes placed on the sphere "head".
  constant num_cubes : INTEGER := 2;
  -- Built via transform matrix helpers (Q8.8 diagonal entries).
  constant eye_scale_mat : mat4 :=
    mat4_mul(
      IDENTITY_MAT4,
      make_scale(to_signed(224, FP_WIDTH), to_signed(160, FP_WIDTH), FP_ONE)
    );

  type scene_t is array (0 to NUM_CUBES - 1) of cube_t;

  constant scene : scene_t :=
  (
    -- Left eye
    0 => (center_x => 285, center_y => 215, side_length => 22, scale_x_q8 => to_integer(eye_scale_mat(0, 0)), scale_y_q8 => to_integer(eye_scale_mat(1, 1)), color => (r => x"20", g => x"20", b => x"40")),
    -- Right eye
    1 => (center_x => 335, center_y => 215, side_length => 22, scale_x_q8 => to_integer(eye_scale_mat(0, 0)), scale_y_q8 => to_integer(eye_scale_mat(1, 1)), color => (r => x"20", g => x"20", b => x"40"))
  );

  -- ── Spheres ──────────────────────────────────────────────
  -- Debug rendering switch:
  --   true  => draw spheres as wireframe rings
  --   false => draw fully lit/shaded spheres
  constant sphere_wireframe_mode : boolean := false;

  -- To add a sphere: increment NUM_SPHERES and append a SCENE_SPHERES entry.
  -- To hide one:     set radius => 0  (zero-radius = invisible).
  constant num_spheres : integer := 1;
  constant head_scale_mat : mat4 :=
    mat4_mul(
      IDENTITY_MAT4,
      make_scale(to_signed(256, FP_WIDTH), to_signed(208, FP_WIDTH), FP_ONE)
    );

  type sphere_scene_t is array (0 to NUM_SPHERES - 1) of sphere_t;

  constant scene_spheres : sphere_scene_t :=
  (
    -- index 0: face head sphere
    0 => (center_x => 310, center_y => 240, radius => 105, scale_x_q8 => to_integer(head_scale_mat(0, 0)), scale_y_q8 => to_integer(head_scale_mat(1, 1)), color => (r => x"FF", g => x"DE", b => x"72"))
  );

end package define_objects;
