-- ============================================================
-- FRAMEBUFFER_SRAM.vhd
-- ECE 4377 Final Project
--
-- 640x480 RGB565 double framebuffer in external SRAM (single-port):
--   - Front buffer is read for VGA scanout
--   - Back buffer is written by renderer
--   - Buffers swap on vsync after a full back-buffer render
--
-- Throughput mode:
--   - Front-buffer reads are prioritized whenever scan coordinates advance
--   - Back-buffer writes use remaining memory cycles
-- ============================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity framebuffer_sram is
  port (
    clk_50         : in  std_logic;
    vert_sync      : in  std_logic;
    display_active : in  std_logic;
    display_row    : in  std_logic_vector(9 downto 0);
    display_col    : in  std_logic_vector(9 downto 0);

    render_row     : out std_logic_vector(9 downto 0);
    render_col     : out std_logic_vector(9 downto 0);
    frame_swap_tick : out std_logic;
    render_red     : in  std_logic_vector(7 downto 0);
    render_green   : in  std_logic_vector(7 downto 0);
    render_blue    : in  std_logic_vector(7 downto 0);

    display_red    : out std_logic_vector(7 downto 0);
    display_green  : out std_logic_vector(7 downto 0);
    display_blue   : out std_logic_vector(7 downto 0);

    sram_addr      : out unsigned(19 downto 0);
    sram_dq        : inout unsigned(15 downto 0);
    sram_ce_n      : out std_logic;
    sram_lb_n      : out std_logic;
    sram_oe_n      : out std_logic;
    sram_ub_n      : out std_logic;
    sram_we_n      : out std_logic
  );
end entity framebuffer_sram;

architecture rtl of framebuffer_sram is

  constant WIDTH          : integer := 640;
  constant HEIGHT         : integer := 480;
  constant FRAME_PIXELS   : integer := WIDTH * HEIGHT; -- 307200 words
  constant FRAME_BASE_0   : unsigned(19 downto 0) := to_unsigned(0, 20);
  constant FRAME_BASE_1   : unsigned(19 downto 0) := to_unsigned(FRAME_PIXELS, 20);

  signal front_base       : unsigned(19 downto 0) := FRAME_BASE_0;
  signal back_base        : unsigned(19 downto 0) := FRAME_BASE_1;
  signal front_valid      : std_logic := '0';

  signal render_x         : integer range 0 to WIDTH - 1 := 0;
  signal render_y         : integer range 0 to HEIGHT - 1 := 0;
  signal render_done      : std_logic := '0';

  signal vert_sync_s1     : std_logic := '0';
  signal vert_sync_s2     : std_logic := '0';
  signal display_active_s1: std_logic := '0';
  signal display_active_s2: std_logic := '0';
  signal display_row_s1   : std_logic_vector(9 downto 0) := (others => '0');
  signal display_row_s2   : std_logic_vector(9 downto 0) := (others => '0');
  signal display_col_s1   : std_logic_vector(9 downto 0) := (others => '0');
  signal display_col_s2   : std_logic_vector(9 downto 0) := (others => '0');
  signal vsync_prev       : std_logic := '0';
  signal read_pending     : std_logic := '0';
  signal display_prev     : std_logic := '0';
  signal last_disp_row    : unsigned(9 downto 0) := (others => '0');
  signal last_disp_col    : unsigned(9 downto 0) := (others => '0');

  signal sram_addr_r      : unsigned(19 downto 0) := (others => '0');
  signal sram_we_n_r      : std_logic := '1';
  signal sram_oe_n_r      : std_logic := '1';
  signal sram_dq_oe       : std_logic := '0';
  signal sram_dq_out      : unsigned(15 downto 0) := (others => '0');
  signal disp_r           : std_logic_vector(7 downto 0) := (others => '0');
  signal disp_g           : std_logic_vector(7 downto 0) := (others => '0');
  signal disp_b           : std_logic_vector(7 downto 0) := (others => '0');
  signal frame_swap_tick_r : std_logic := '0';

  constant MAX_COL_U10    : unsigned(9 downto 0) := to_unsigned(WIDTH - 1, 10);
  constant MAX_ROW_U10    : unsigned(9 downto 0) := to_unsigned(HEIGHT - 1, 10);

  function pixel_offset(xu, yu : unsigned(9 downto 0)) return unsigned is
    variable x20 : unsigned(19 downto 0);
    variable y20 : unsigned(19 downto 0);
  begin
    x20 := resize(xu, 20);
    y20 := resize(yu, 20);
    -- y*640 + x = y*(512+128) + x
    return (y20 sll 9) + (y20 sll 7) + x20;
  end function;

  function render_offset(rx, ry : integer) return unsigned is
    variable x20 : unsigned(19 downto 0);
    variable y20 : unsigned(19 downto 0);
  begin
    x20 := to_unsigned(rx, 20);
    y20 := to_unsigned(ry, 20);
    return (y20 sll 9) + (y20 sll 7) + x20;
  end function;

  function rgb888_to_565(
    r8, g8, b8 : std_logic_vector(7 downto 0)
  ) return unsigned is
  begin
    return unsigned(r8(7 downto 3) & g8(7 downto 2) & b8(7 downto 3));
  end function;

begin

  render_row <= std_logic_vector(to_unsigned(render_y, 10));
  render_col <= std_logic_vector(to_unsigned(render_x, 10));

  display_red   <= disp_r;
  display_green <= disp_g;
  display_blue  <= disp_b;
  frame_swap_tick <= frame_swap_tick_r;

  sram_addr <= sram_addr_r;
  sram_ce_n <= '0';
  sram_lb_n <= '0';
  sram_ub_n <= '0';
  sram_we_n <= sram_we_n_r;
  sram_oe_n <= sram_oe_n_r;
  sram_dq   <= sram_dq_out when sram_dq_oe = '1' else (others => 'Z');

  arbiter_proc : process (clk_50) is
    variable read_addr  : unsigned(19 downto 0);
    variable write_addr : unsigned(19 downto 0);
    variable pix565     : unsigned(15 downto 0);
    variable disp_row_u : unsigned(9 downto 0);
    variable disp_col_u : unsigned(9 downto 0);
    variable in_bounds  : boolean;
    variable need_read  : boolean;
    variable stable_sample : boolean;
  begin
    if rising_edge(clk_50) then
      -- Synchronize VGA-domain control/coordinate inputs into clk_50 domain.
      vert_sync_s1 <= vert_sync;
      vert_sync_s2 <= vert_sync_s1;
      display_active_s1 <= display_active;
      display_active_s2 <= display_active_s1;
      display_row_s1 <= display_row;
      display_row_s2 <= display_row_s1;
      display_col_s1 <= display_col;
      display_col_s2 <= display_col_s1;

      frame_swap_tick_r <= '0';
      disp_row_u := unsigned(display_row_s2);
      disp_col_u := unsigned(display_col_s2);
      in_bounds := (disp_col_u <= MAX_COL_U10) and (disp_row_u <= MAX_ROW_U10);
      need_read := false;
      stable_sample := (display_row_s1 = display_row_s2) and (display_col_s1 = display_col_s2);

      -- Swap only at frame boundary after a complete back-buffer render.
      if vert_sync_s2 = '1' and vsync_prev = '0' then
        if render_done = '1' then
          front_base  <= back_base;
          back_base   <= front_base;
          front_valid <= '1';
          render_x    <= 0;
          render_y    <= 0;
          render_done <= '0';
          frame_swap_tick_r <= '1';
        end if;
      end if;
      vsync_prev <= vert_sync_s2;

      -- Defaults: no SRAM operation.
      sram_dq_oe  <= '0';
      sram_we_n_r <= '1';
      sram_oe_n_r <= '1';

      -- Complete prior read (one-cycle latency).
      if read_pending = '1' then
        pix565 := sram_dq;
        disp_r <= std_logic_vector(pix565(15 downto 11) & pix565(15 downto 13));
        disp_g <= std_logic_vector(pix565(10 downto 5) & pix565(10 downto 9));
        disp_b <= std_logic_vector(pix565(4 downto 0) & pix565(4 downto 2));
        read_pending <= '0';
      end if;

      -- Request a new display read whenever scan coordinate changes.
      if (display_active_s2 = '1') and (display_active_s1 = display_active_s2) and stable_sample and (front_valid = '1') and in_bounds then
        if (display_prev = '0') or (disp_col_u /= last_disp_col) or (disp_row_u /= last_disp_row) then
          need_read := true;
        end if;
      end if;

      if need_read then
        read_addr := front_base + pixel_offset(disp_col_u, disp_row_u);
        sram_addr_r <= read_addr;
        sram_oe_n_r <= '0';
        read_pending <= '1';
        last_disp_col <= disp_col_u;
        last_disp_row <= disp_row_u;
        -- Suppress one-cycle seam at x=0 where prior-line tail can leak.
        if disp_col_u = 0 then
          disp_r <= (others => '0');
          disp_g <= (others => '0');
          disp_b <= (others => '0');
        end if;

      elsif render_done = '0' then
        -- Use remaining bandwidth for back-buffer writes.
        write_addr := back_base + render_offset(render_x, render_y);
        sram_addr_r <= write_addr;
        sram_dq_out <= rgb888_to_565(render_red, render_green, render_blue);
        sram_dq_oe  <= '1';
        sram_we_n_r <= '0';

        if render_x = WIDTH - 1 then
          render_x <= 0;
          if render_y = HEIGHT - 1 then
            render_y <= 0;
            render_done <= '1';
          else
            render_y <= render_y + 1;
          end if;
        else
          render_x <= render_x + 1;
        end if;
      elsif (display_active_s2 = '0') or (not in_bounds) or (front_valid = '0') then
        disp_r <= (others => '0');
        disp_g <= (others => '0');
        disp_b <= (others => '0');
      end if;
      display_prev <= display_active_s2;
    end if;
  end process;

end architecture rtl;
