-- ============================================================
-- 4x4 Matrix × 4x1 Vector Multiplier (Q8.8 fixed-point)
-- ECE 4377 Final Project
--
-- Computes result = M × v, where M is a 4×4 transform matrix
-- and v is a homogeneous vertex [x, y, z, w].
-- Each output row is the dot product of one matrix row with v:
--   result.x = M(0,0)*v.x + M(0,1)*v.y + M(0,2)*v.z + M(0,3)*v.w
--   result.y = M(1,0)*v.x + ...
--   result.z = M(2,0)*v.x + ...
--   result.w = M(3,0)*v.x + ...
--
-- All values use the fp / Q8.8 type from types.VHD.
-- Result is ready 2 clock cycles after valid_i is raised.
-- ============================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types.ALL;

entity MATRIX_MULT is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        valid_i : in  std_logic;  -- raise when M and v are ready

        M       : in  mat4;       -- 4×4 transform matrix
        v       : in  vec4;       -- input vertex [x, y, z, w]

        result  : out vec4;       -- transformed vertex M × v
        valid_o : out std_logic   -- high 2 cycles after valid_i
    );
end entity MATRIX_MULT;

architecture rtl of MATRIX_MULT is

    -- Multiplying two Q8.8 (16-bit) values gives a 32-bit Q16.16 product.
    -- Summing 4 such products can overflow 32 bits, so we use a 34-bit
    -- accumulator (2 extra guard bits cover the worst case of 4 max products).
    constant ACC_WIDTH : integer := 2 * FP_WIDTH + 2;  -- 34 bits

    subtype fp_acc is signed(ACC_WIDTH - 1 downto 0);
    type    row_acc is array(0 to 3) of fp_acc;

    -- Stage 1: accumulated dot products, full 34-bit precision
    signal stage1_valid : std_logic;
    signal stage1_dot   : row_acc;

    -- Stage 2: results truncated back to Q8.8
    signal stage2_valid : std_logic;
    signal stage2_x, stage2_y, stage2_z, stage2_w : fp;

    -- Any accumulator value outside these bounds would overflow a 16-bit output
    constant SAT_MAX : fp_acc :=
        to_signed( (2 ** (FP_WIDTH - 1) - 1) * (2 ** FP_FRAC), ACC_WIDTH);
    constant SAT_MIN : fp_acc :=
        to_signed(-(2 ** (FP_WIDTH - 1))     * (2 ** FP_FRAC), ACC_WIDTH);

    -- Clamp and shift a 34-bit Q16.16 accumulator down to Q8.8
    function truncate_sat(x : fp_acc) return fp is
    begin
        if x > SAT_MAX then
            return to_signed( 2 ** (FP_WIDTH - 1) - 1, FP_WIDTH);  -- max positive
        elsif x < SAT_MIN then
            return to_signed(-(2 ** (FP_WIDTH - 1)),   FP_WIDTH);  -- min negative
        else
            -- Drop the bottom FP_FRAC bits to re-align the binary point
            return x(FP_WIDTH + FP_FRAC - 1 downto FP_FRAC);
        end if;
    end function;

begin

    -- ----------------------------------------------------------
    -- Stage 1: compute 4 dot products (registered)
    -- Pack the vec4 record into a local array so we can loop over it.
    -- ----------------------------------------------------------
    process(clk)
        type fp_arr4 is array(0 to 3) of fp;
        variable v_arr : fp_arr4;
        variable acc   : fp_acc;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                stage1_valid <= '0';
                for i in 0 to 3 loop
                    stage1_dot(i) <= (others => '0');
                end loop;
            else
                stage1_valid <= valid_i;

                v_arr(0) := v.x;
                v_arr(1) := v.y;
                v_arr(2) := v.z;
                v_arr(3) := v.w;

                for row in 0 to 3 loop
                    acc := (others => '0');
                    for col in 0 to 3 loop
                        acc := acc + resize(M(row, col) * v_arr(col), ACC_WIDTH);
                    end loop;
                    stage1_dot(row) <= acc;
                end loop;
            end if;
        end if;
    end process;

    -- ----------------------------------------------------------
    -- Stage 2: truncate 34-bit Q16.16 back to Q8.8 (registered)
    -- ----------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                stage2_valid <= '0';
                stage2_x <= FP_ZERO;
                stage2_y <= FP_ZERO;
                stage2_z <= FP_ZERO;
                stage2_w <= FP_ZERO;
            else
                stage2_valid <= stage1_valid;
                stage2_x <= truncate_sat(stage1_dot(0));
                stage2_y <= truncate_sat(stage1_dot(1));
                stage2_z <= truncate_sat(stage1_dot(2));
                stage2_w <= truncate_sat(stage1_dot(3));
            end if;
        end if;
    end process;

    -- ----------------------------------------------------------
    -- Output assignments
    -- ----------------------------------------------------------
    result.x <= stage2_x;
    result.y <= stage2_y;
    result.z <= stage2_z;
    result.w <= stage2_w;
    valid_o  <= stage2_valid;

end architecture rtl;
