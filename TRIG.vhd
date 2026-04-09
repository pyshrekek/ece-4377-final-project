-- ============================================================
-- TRIG.vhd  –  Sin / Cos lookup table  (Q8.8 fixed-point)
-- ECE 4377 Final Project
--
-- Converts an 8-bit angle (0–255, representing 0–360°, i.e.
-- 256 steps of ~1.406° each) into Q8.8 sin and cos values.
--
-- Output scaling:
--   sin/cos = +1.0  →  0x0100  (256)
--   sin/cos = -1.0  →  0xFF00  (-256 in two's complement)
--
-- This matches the fp type in types.VHD  (FP_FRAC = 8, so
-- 1.0 is represented as 2^8 = 256 = 0x0100).
--
-- Interface:
--   angle_i  : 8-bit unsigned angle index (0 = 0°, 64 = 90°,
--              128 = 180°, 192 = 270°)
--   sin_o    : Q8.8 fp sine of angle_i
--   cos_o    : Q8.8 fp cosine of angle_i
--
-- Combinational – result is available the same clock cycle.
-- Wrap in a register if you need a clocked output.
-- ============================================================

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.types.ALL;

ENTITY TRIG IS
    PORT (
        angle_i : IN  unsigned(7 DOWNTO 0);   -- 0–255 angle index
        sin_o   : OUT fp;                      -- Q8.8 sine
        cos_o   : OUT fp                       -- Q8.8 cosine
    );
END ENTITY TRIG;

ARCHITECTURE lut OF TRIG IS

    -- -----------------------------------------------------------
    -- 256-entry sin LUT, Q8.8 scaled.
    -- Values = round(sin(2π·i/256) × 256) for i = 0..255.
    -- Range: -256 to +256 (fits in a 16-bit signed word).
    -- -----------------------------------------------------------
    TYPE sin_lut_t IS ARRAY(0 TO 255) OF integer RANGE -256 TO 256;

    CONSTANT SIN_LUT : sin_lut_t := (
    --   0        1        2        3        4        5        6        7
         0,       6,      13,      19,      25,      31,      38,      44,    --   0– 7
        50,      56,      62,      68,      74,      80,      86,      92,    --   8–15
        98,     104,     109,     115,     121,     126,     132,     137,    --  16–23
       143,     148,     153,     158,     163,     168,     173,     178,    --  24–31
       183,     187,     192,     196,     200,     205,     209,     213,    --  32–39
       217,     221,     224,     228,     231,     235,     238,     241,    --  40–47
       244,     247,     249,     252,     254,     256,     258,     260,    --  48–55
       262,     263,     265,     266,     267,     268,     269,     270,    --  56–63
       --  i=64 → sin(90°) = 1.0 → 256
       256,     256,     256,     255,     255,     254,     253,     252,    --  64–71
       251,     250,     248,     247,     245,     243,     241,     239,    --  72–79
       237,     235,     232,     230,     227,     224,     221,     218,    --  80–87
       215,     212,     209,     205,     202,     198,     194,     190,    --  88–95
       186,     182,     178,     174,     170,     165,     161,     156,    --  96–103
       152,     147,     142,     137,     132,     127,     122,     117,    -- 104–111
       112,     107,     102,      96,      91,      86,      80,      75,    -- 112–119
        69,      64,      58,      53,      47,      42,      36,      30,    -- 120–127
       --  i=128 → sin(180°) = 0
        25,      19,      13,       8,       2,      -4,     -10,     -15,    -- 128–135
       -21,     -27,     -32,     -38,     -44,     -49,     -55,     -60,    -- 136–143
       -66,     -71,     -77,     -82,     -87,     -93,     -98,    -103,    -- 144–151
      -108,    -113,    -118,    -123,    -128,    -133,    -138,    -143,    -- 152–159
      -147,    -152,    -157,    -161,    -165,    -170,    -174,    -178,    -- 160–167
      -182,    -186,    -190,    -194,    -198,    -202,    -205,    -209,    -- 168–175
      -212,    -215,    -218,    -221,    -224,    -227,    -230,    -232,    -- 176–183
      -235,    -237,    -239,    -241,    -243,    -245,    -247,    -248,    -- 184–191
      --  i=192 → sin(270°) = -1.0 → -256
      -250,    -251,    -252,    -253,    -254,    -255,    -255,    -256,    -- 192–199
      -256,    -256,    -256,    -256,    -255,    -255,    -254,    -253,    -- 200–207
      -252,    -251,    -249,    -247,    -245,    -244,    -241,    -238,    -- 208–215
      -235,    -231,    -228,    -224,    -221,    -217,    -213,    -209,    -- 216–223
      -205,    -200,    -196,    -192,    -187,    -183,    -178,    -173,    -- 224–231
      -168,    -163,    -158,    -153,    -148,    -143,    -137,    -132,    -- 232–239
      -126,    -121,    -115,    -109,    -104,     -98,     -92,     -86,    -- 240–247
       -80,     -74,     -68,     -62,     -56,     -50,     -44,     -38     -- 248–255
    );

    SIGNAL sin_int : integer RANGE -256 TO 256;
    SIGNAL cos_int : integer RANGE -256 TO 256;

    -- cos(x) = sin(x + 90°); +90° = +64 steps in 256-step circle
    SIGNAL cos_idx : unsigned(7 DOWNTO 0);

BEGIN

    cos_idx <= angle_i + to_unsigned(64, 8);  -- wraps naturally at 256

    sin_int <= SIN_LUT(to_integer(angle_i));
    cos_int <= SIN_LUT(to_integer(cos_idx));

    -- Cast integer [-256..256] directly to the 16-bit signed fp type.
    -- The binary point sits after bit 7, so the integer value IS the
    -- Q8.8 representation (e.g. 256 = 0x0100 = 1.0 in Q8.8).
    sin_o <= to_signed(sin_int, FP_WIDTH);
    cos_o <= to_signed(cos_int, FP_WIDTH);

END ARCHITECTURE lut;
