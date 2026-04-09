-- ============================================================
-- Transform Matrix Builders (Q8.8 fixed-point)
-- ECE 4377 Final Project
--
-- Pure functions that build mat4 transform matrices to feed
-- into MATRIX_MULT. All matrices are column-vector style:
--     v_out = M * v_in
--
-- Compositions follow OpenGL convention:
--     M_total = T * R * S
-- (i.e. scale first, then rotate, then translate.)
--
-- Provided builders:
--   make_scale       (sx, sy, sz)            -> mat4
--   make_scale_uni   (s)                     -> mat4
--   make_translate   (tx, ty, tz)            -> mat4
--   make_rotate_x    (angle_idx)             -> mat4
--   make_rotate_y    (angle_idx)             -> mat4
--   make_rotate_z    (angle_idx)             -> mat4
--   mat4_mul         (A, B)                  -> mat4   (A * B)
--
-- Angles are passed as an 8-bit "binary angle" (0..255 = 0..360°)
-- which indexes the SIN_LUT directly. This avoids any runtime
-- trig and keeps everything in Q8.8.
--
-- All functions are PURE -- if their inputs are constants the
-- synthesizer will fold the result into a constant mat4. They
-- can also be used in clocked processes for runtime transforms.
-- ============================================================

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.types.ALL;

PACKAGE transforms IS

    -- 8-bit binary angle: 0 = 0deg, 64 = 90deg, 128 = 180deg, 192 = 270deg
    SUBTYPE angle_t IS unsigned(7 DOWNTO 0);

    -- Helper: build an fp value from an integer (whole number, no fraction)
    FUNCTION to_fp(i : INTEGER) RETURN fp;

    -- Sin / cos in Q8.8 from an 8-bit binary angle
    FUNCTION fp_sin(a : angle_t) RETURN fp;
    FUNCTION fp_cos(a : angle_t) RETURN fp;

    -- Q8.8 multiply with truncation back to Q8.8
    FUNCTION fp_mul(a, b : fp) RETURN fp;

    -- Matrix * Matrix (both mat4), result is A*B in Q8.8
    FUNCTION mat4_mul(A, B : mat4) RETURN mat4;

    -- Transform builders
    FUNCTION make_scale     (sx, sy, sz : fp) RETURN mat4;
    FUNCTION make_scale_uni (s : fp)          RETURN mat4;
    FUNCTION make_translate (tx, ty, tz : fp) RETURN mat4;
    FUNCTION make_rotate_x  (a : angle_t)     RETURN mat4;
    FUNCTION make_rotate_y  (a : angle_t)     RETURN mat4;
    FUNCTION make_rotate_z  (a : angle_t)     RETURN mat4;

END PACKAGE;


PACKAGE BODY transforms IS

    -- ----------------------------------------------------------
    -- 256-entry sine LUT, Q8.8 fixed-point.
    -- Index = binary angle (0..255 maps to 0..360 degrees).
    -- Generated so that SIN_LUT(i) = round(sin(2*pi*i/256) * 256).
    -- ----------------------------------------------------------
    TYPE sin_lut_t IS ARRAY (0 TO 255) OF INTEGER;
    CONSTANT SIN_LUT : sin_lut_t := (
             0,      6,     13,     19,     25,     31,     38,     44,
            50,     56,     62,     68,     74,     80,     86,     92,
            98,    104,    109,    115,    121,    126,    132,    137,
           142,    147,    152,    157,    162,    167,    172,    177,
           181,    185,    190,    194,    198,    202,    206,    209,
           213,    216,    220,    223,    226,    229,    231,    234,
           237,    239,    241,    243,    245,    247,    248,    250,
           251,    252,    253,    254,    255,    255,    256,    256,
           256,    256,    256,    255,    255,    254,    253,    252,
           251,    250,    248,    247,    245,    243,    241,    239,
           237,    234,    231,    229,    226,    223,    220,    216,
           213,    209,    206,    202,    198,    194,    190,    185,
           181,    177,    172,    167,    162,    157,    152,    147,
           142,    137,    132,    126,    121,    115,    109,    104,
            98,     92,     86,     80,     74,     68,     62,     56,
            50,     44,     38,     31,     25,     19,     13,      6,
             0,     -6,    -13,    -19,    -25,    -31,    -38,    -44,
           -50,    -56,    -62,    -68,    -74,    -80,    -86,    -92,
           -98,   -104,   -109,   -115,   -121,   -126,   -132,   -137,
          -142,   -147,   -152,   -157,   -162,   -167,   -172,   -177,
          -181,   -185,   -190,   -194,   -198,   -202,   -206,   -209,
          -213,   -216,   -220,   -223,   -226,   -229,   -231,   -234,
          -237,   -239,   -241,   -243,   -245,   -247,   -248,   -250,
          -251,   -252,   -253,   -254,   -255,   -255,   -256,   -256,
          -256,   -256,   -256,   -255,   -255,   -254,   -253,   -252,
          -251,   -250,   -248,   -247,   -245,   -243,   -241,   -239,
          -237,   -234,   -231,   -229,   -226,   -223,   -220,   -216,
          -213,   -209,   -206,   -202,   -198,   -194,   -190,   -185,
          -181,   -177,   -172,   -167,   -162,   -157,   -152,   -147,
          -142,   -137,   -132,   -126,   -121,   -115,   -109,   -104,
           -98,    -92,    -86,    -80,    -74,    -68,    -62,    -56,
           -50,    -44,    -38,    -31,    -25,    -19,    -13,     -6
    );

    -- ----------------------------------------------------------
    -- Convert an integer to Q8.8 (whole number, fraction = 0)
    -- ----------------------------------------------------------
    FUNCTION to_fp(i : INTEGER) RETURN fp IS
    BEGIN
        RETURN to_signed(i * (2 ** FP_FRAC), FP_WIDTH);
    END FUNCTION;

    -- ----------------------------------------------------------
    -- sin(angle) in Q8.8 -- direct LUT lookup
    -- ----------------------------------------------------------
    FUNCTION fp_sin(a : angle_t) RETURN fp IS
    BEGIN
        RETURN to_signed(SIN_LUT(to_integer(a)), FP_WIDTH);
    END FUNCTION;

    -- ----------------------------------------------------------
    -- cos(angle) = sin(angle + 90deg) = sin(angle + 64)
    -- ----------------------------------------------------------
    FUNCTION fp_cos(a : angle_t) RETURN fp IS
        VARIABLE idx : unsigned(7 DOWNTO 0);
    BEGIN
        idx := a + to_unsigned(64, 8);  -- wraps mod 256 naturally
        RETURN to_signed(SIN_LUT(to_integer(idx)), FP_WIDTH);
    END FUNCTION;

    -- ----------------------------------------------------------
    -- Q8.8 multiply: 16 x 16 -> 32, then shift right by FP_FRAC
    -- to re-align the binary point. No saturation here -- callers
    -- using sin/cos values stay well within range.
    -- ----------------------------------------------------------
    FUNCTION fp_mul(a, b : fp) RETURN fp IS
        VARIABLE prod : signed(2 * FP_WIDTH - 1 DOWNTO 0);
    BEGIN
        prod := a * b;
        RETURN prod(FP_WIDTH + FP_FRAC - 1 DOWNTO FP_FRAC);
    END FUNCTION;

    -- ----------------------------------------------------------
    -- 4x4 * 4x4 matrix multiply, Q8.8 throughout.
    -- C(i,j) = sum_k A(i,k) * B(k,j)
    -- Useful for composing transforms: M = T * R * S
    -- ----------------------------------------------------------
    FUNCTION mat4_mul(A, B : mat4) RETURN mat4 IS
        VARIABLE C   : mat4;
        VARIABLE acc : signed(2 * FP_WIDTH + 1 DOWNTO 0);  -- 34-bit guard
    BEGIN
        FOR i IN 0 TO 3 LOOP
            FOR j IN 0 TO 3 LOOP
                acc := (OTHERS => '0');
                FOR k IN 0 TO 3 LOOP
                    acc := acc + resize(A(i, k) * B(k, j), 2 * FP_WIDTH + 2);
                END LOOP;
                -- shift right by FP_FRAC to convert Q16.16 -> Q8.8
                C(i, j) := acc(FP_WIDTH + FP_FRAC - 1 DOWNTO FP_FRAC);
            END LOOP;
        END LOOP;
        RETURN C;
    END FUNCTION;

    -- ----------------------------------------------------------
    -- Scale matrix:
    --   [ sx  0   0   0 ]
    --   [ 0   sy  0   0 ]
    --   [ 0   0   sz  0 ]
    --   [ 0   0   0   1 ]
    -- ----------------------------------------------------------
    FUNCTION make_scale(sx, sy, sz : fp) RETURN mat4 IS
        VARIABLE M : mat4 := IDENTITY_MAT4;
    BEGIN
        M(0, 0) := sx;
        M(1, 1) := sy;
        M(2, 2) := sz;
        RETURN M;
    END FUNCTION;

    -- Uniform scale convenience wrapper
    FUNCTION make_scale_uni(s : fp) RETURN mat4 IS
    BEGIN
        RETURN make_scale(s, s, s);
    END FUNCTION;

    -- ----------------------------------------------------------
    -- Translation matrix:
    --   [ 1  0  0  tx ]
    --   [ 0  1  0  ty ]
    --   [ 0  0  1  tz ]
    --   [ 0  0  0  1  ]
    -- ----------------------------------------------------------
    FUNCTION make_translate(tx, ty, tz : fp) RETURN mat4 IS
        VARIABLE M : mat4 := IDENTITY_MAT4;
    BEGIN
        M(0, 3) := tx;
        M(1, 3) := ty;
        M(2, 3) := tz;
        RETURN M;
    END FUNCTION;

    -- ----------------------------------------------------------
    -- Rotation about X axis:
    --   [ 1   0    0   0 ]
    --   [ 0   c   -s   0 ]
    --   [ 0   s    c   0 ]
    --   [ 0   0    0   1 ]
    -- ----------------------------------------------------------
    FUNCTION make_rotate_x(a : angle_t) RETURN mat4 IS
        VARIABLE M : mat4 := IDENTITY_MAT4;
        VARIABLE c, s : fp;
    BEGIN
        c := fp_cos(a);
        s := fp_sin(a);
        M(1, 1) := c;
        M(1, 2) := -s;
        M(2, 1) := s;
        M(2, 2) := c;
        RETURN M;
    END FUNCTION;

    -- ----------------------------------------------------------
    -- Rotation about Y axis:
    --   [ c   0   s   0 ]
    --   [ 0   1   0   0 ]
    --   [-s   0   c   0 ]
    --   [ 0   0   0   1 ]
    -- ----------------------------------------------------------
    FUNCTION make_rotate_y(a : angle_t) RETURN mat4 IS
        VARIABLE M : mat4 := IDENTITY_MAT4;
        VARIABLE c, s : fp;
    BEGIN
        c := fp_cos(a);
        s := fp_sin(a);
        M(0, 0) := c;
        M(0, 2) := s;
        M(2, 0) := -s;
        M(2, 2) := c;
        RETURN M;
    END FUNCTION;

    -- ----------------------------------------------------------
    -- Rotation about Z axis:
    --   [ c  -s   0   0 ]
    --   [ s   c   0   0 ]
    --   [ 0   0   1   0 ]
    --   [ 0   0   0   1 ]
    -- ----------------------------------------------------------
    FUNCTION make_rotate_z(a : angle_t) RETURN mat4 IS
        VARIABLE M : mat4 := IDENTITY_MAT4;
        VARIABLE c, s : fp;
    BEGIN
        c := fp_cos(a);
        s := fp_sin(a);
        M(0, 0) := c;
        M(0, 1) := -s;
        M(1, 0) := s;
        M(1, 1) := c;
        RETURN M;
    END FUNCTION;

END PACKAGE BODY;
