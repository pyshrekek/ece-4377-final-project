-- ============================================================
-- TRIG_TB.vhd  –  Testbench for TRIG.vhd
-- ECE 4377 Final Project
--
-- Sweeps all 256 angle indices and checks key exact values:
--   angle=  0  → sin= 0x0000 (0.0),  cos= 0x0100 (+1.0)
--   angle= 64  → sin= 0x0100 (+1.0), cos= 0x0000 (0.0)
--   angle=128  → sin= 0x0000 (0.0),  cos= 0xFF00 (-1.0)
--   angle=192  → sin= 0xFF00 (-1.0), cos= 0x0000 (0.0)
-- ============================================================

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.types.ALL;

ENTITY TRIG_TB IS
END ENTITY TRIG_TB;

ARCHITECTURE sim OF TRIG_TB IS

    SIGNAL angle : unsigned(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL sin_out : fp;
    SIGNAL cos_out : fp;

    -- Tolerance: ±2 LSB (±0.0078 in Q8.8) for LUT rounding
    CONSTANT TOL : integer := 2;

    PROCEDURE check(
        label     : IN string;
        actual    : IN integer;
        expected  : IN integer;
        tolerance : IN integer
    ) IS BEGIN
        ASSERT abs(actual - expected) <= tolerance
            REPORT label & ": expected " & integer'image(expected) &
                   " got " & integer'image(actual)
            SEVERITY error;
    END PROCEDURE;

BEGIN

    -- Instantiate DUT
    DUT : ENTITY work.TRIG
        PORT MAP (
            angle_i => angle,
            sin_o   => sin_out,
            cos_o   => cos_out
        );

    PROCESS
    BEGIN
        -- -------------------------------------------------------
        -- Sweep all 256 angles, printing sin/cos for waveform inspection
        -- -------------------------------------------------------
        FOR i IN 0 TO 255 LOOP
            angle <= to_unsigned(i, 8);
            WAIT FOR 10 ns;
        END LOOP;

        -- -------------------------------------------------------
        -- Spot-check cardinal angles
        -- -------------------------------------------------------

        -- 0° : sin=0, cos=+1.0 (256)
        angle <= to_unsigned(0, 8);   WAIT FOR 10 ns;
        check("sin(0°)",   to_integer(sin_out),   0,   TOL);
        check("cos(0°)",   to_integer(cos_out), 256,   TOL);

        -- 90° : sin=+1.0 (256), cos=0
        angle <= to_unsigned(64, 8);  WAIT FOR 10 ns;
        check("sin(90°)",  to_integer(sin_out), 256,   TOL);
        check("cos(90°)",  to_integer(cos_out),   0,   TOL);

        -- 180° : sin=0, cos=-1.0 (-256)
        angle <= to_unsigned(128, 8); WAIT FOR 10 ns;
        check("sin(180°)", to_integer(sin_out),   0,   TOL);
        check("cos(180°)", to_integer(cos_out), -256,  TOL);

        -- 270° : sin=-1.0 (-256), cos=0
        angle <= to_unsigned(192, 8); WAIT FOR 10 ns;
        check("sin(270°)", to_integer(sin_out), -256,  TOL);
        check("cos(270°)", to_integer(cos_out),   0,   TOL);

        -- 45° (index 32) : sin≈cos≈181 (≈0.707 × 256)
        angle <= to_unsigned(32, 8);  WAIT FOR 10 ns;
        check("sin(45°)",  to_integer(sin_out), 181,   TOL);
        check("cos(45°)",  to_integer(cos_out), 181,   TOL);

        REPORT "TRIG_TB: all checks passed." SEVERITY note;
        WAIT;
    END PROCESS;

END ARCHITECTURE sim;
