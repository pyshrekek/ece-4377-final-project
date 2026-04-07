LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

PACKAGE types IS

    -- Fixed-point configuration
    CONSTANT FP_WIDTH : INTEGER := 16;
    CONSTANT FP_FRAC : INTEGER := 8;

    SUBTYPE fp IS signed(FP_WIDTH - 1 DOWNTO 0);

    CONSTANT FP_ZERO : fp := to_signed(0, FP_WIDTH);
    CONSTANT FP_ONE : fp := to_signed(2 ** FP_FRAC, FP_WIDTH);

    -- Vector types
    TYPE vec2 IS RECORD
        x : fp;
        y : fp;
    END RECORD;

    TYPE vec3 IS RECORD
        x : fp;
        y : fp;
        z : fp;
    END RECORD;

    TYPE vec4 IS RECORD
        x : fp;
        y : fp;
        z : fp;
        w : fp;
    END RECORD;

    -- Matrix types
    TYPE mat3 IS ARRAY (0 TO 2, 0 TO 2) OF fp;
    TYPE mat4 IS ARRAY (0 TO 3, 0 TO 3) OF fp;

    -- Common constants
    CONSTANT IDENTITY_MAT4 : mat4 := (
        0 => (0 => FP_ONE, 1 => FP_ZERO, 2 => FP_ZERO, 3 => FP_ZERO),
        1 => (0 => FP_ZERO, 1 => FP_ONE, 2 => FP_ZERO, 3 => FP_ZERO),
        2 => (0 => FP_ZERO, 1 => FP_ZERO, 2 => FP_ONE, 3 => FP_ZERO),
        3 => (0 => FP_ZERO, 1 => FP_ZERO, 2 => FP_ZERO, 3 => FP_ONE)
    );

END PACKAGE;

PACKAGE BODY types IS
END PACKAGE BODY;