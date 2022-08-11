library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.ESCBasicTypesPkg.all;
use work.Lan9254Pkg.all;

library unisim;
use     unisim.vcomponents.all;

-- Synchronous fifo buffer (usr bits are ignored!)
-- Converts a 16-bit stream with byte-enables into
-- a contiguous 8-bit stream.

entity StrmFifoSync is
   generic (
      -- depth in bytes (18kb -> 2kB data or 36kb -> 4kB data)
      DEPTH_36kb  : boolean := false
   );
   port (
      clk         : in  std_logic;
      rst         : in  std_logic;
      fifoRst     : out std_logic;

      strmMstIb   : in  Lan9254StrmMstType    := LAN9254STRM_MST_INIT_C;
      strmRdyIb   : out std_logic;

      emptySlots  : out unsigned(12 downto 0);

      -- reformatted to *byte* stream; i.e., ben(1) is always '0'
      strmMstOb   : out Lan9254StrmMstType;
      strmRdyOb   : in  std_logic := '0'
   );
end entity StrmFifoSync;

architecture rtl of StrmFifoSync is

--   7series rden 0 for before reset, 5 reset, rden remain low for 2
--   virtex6 rden 0 for 4 cycles,  reset hi 3

   constant USE_DO_REG_C : integer range 0 to 1 := 0;

   constant LST_C        : natural := 8;

   signal fifoDo     : std_logic_vector(8 downto 0);
   signal fifoDi     : std_logic_vector(8 downto 0);
   signal fifoWe     : std_logic := '1';
   signal fifoRe     : std_logic := '1';
   signal fifoWem    : std_logic := '1';
   signal fifoRem    : std_logic := '1';
   signal fifoFull   : std_logic;

   signal fifoRstLoc : std_logic := '0';
   signal fifoRstExt : std_logic := '0';
   signal fifoEnMsk  : std_logic := '0';
   signal fifoRstPnd : std_logic := '1';

   signal fifoRstCnt : natural range 0 to 11 := 0;

   signal fullSlots  : unsigned(12 downto 0);
   signal availLoc   : unsigned(12 downto 0);

   signal tst : std_logic;

begin

   P_FIFO_RST : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            -- remember a new request while we process this one
            fifoRstPnd <= '1';
         end if;
         if ( fifoRstCnt = 0 ) then
            if ( ( rst or fifoRstPnd ) = '1' ) then
               fifoEnMsk  <= '0';
               fifoRstLoc <= '0';
               
               -- start a new reset sequence once 'rst' is released
               if ( (not rst and fifoRstPnd) = '1' ) then
                  fifoRstPnd <= '0';
                  fifoRstCnt <= 11;
               end if;
            end if;
         else
            fifoRstCnt <= fifoRstCnt - 1;
            if     ( fifoRstCnt = 8 ) then
               -- held RDEN/RWEN low for 4 cycles
               -- assert RST
               fifoRstLoc <= '1';
            elsif  ( fifoRstCnt = 3 ) then
               -- was RST asserted for 5 cycles, now deassert
               fifoRstLoc <= '0';
            elsif  ( fifoRstCnt = 1 ) then
               -- complete
               fifoEnMsk  <= '1';
            end if;
         end if;
      end if;
   end process P_FIFO_RST;

   fifoRstExt <= rst or not fifoEnMsk;

   fifoWem    <= fifoWe and fifoEnMsk;
   fifoRem    <= fifoRe and fifoEnMsk;

   P_RAMWR : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
      end if;
   end process P_RAMWR;

   GEN_FIFO18 : if ( not DEPTH_36kb ) generate
      signal rp        : std_logic_vector(11 downto 0);
      signal wp        : std_logic_vector(11 downto 0);
      signal diff      : unsigned        (10 downto 0);
      signal di,  do   : std_logic_vector(31 downto 0);
      signal dip, dop  : std_logic_vector( 3 downto 0);
   begin

      di(31 downto 8)            <= (others => '0');
      di( 7 downto 0)            <= fifoDi(7 downto 0);

      dip(3 downto 1)            <= (others => '0');
      dip(0 downto 0)            <= fifoDi(LST_C downto LST_C);

      fifoDo(7 downto 0)         <= do(7 downto 0);
      fifoDo(LST_C downto LST_C) <= dop(0 downto 0);

      U_FIFO : component FIFO18E1
         generic map (
            DATA_WIDTH              => 9,
            DO_REG                  => USE_DO_REG_C,
            SIM_DEVICE              => "7SERIES",
            EN_SYN                  => true
         )
         port map (
            WRCLK                   => clk,
            RDCLK                   => clk,
            RST                     => fifoRstLoc,
            RSTREG                  => fifoRstLoc,

            REGCE                   => '1',

            DI                      => di,
            DIP                     => dip,
            WREN                    => fifoWem,

            DO                      => do,
            DOP                     => dop,
            RDEN                    => fifoRem,

            RDCOUNT                 => rp,
            WRCOUNT                 => wp,

            FULL                    => fifoFull,
            ALMOSTFULL              => open,
            EMPTY                   => open,
            ALMOSTEMPTY             => open,
            WRERR                   => open,
            RDERR                   => open
         );

      diff <= unsigned( wp(diff'range) ) - unsigned( rp(diff'range) );

      P_COUNT : process ( fifoFull, diff ) is
      begin
         if ( fifoFull = '1' ) then
            fullSlots  <= to_unsigned(2048, fullSlots'length);
            availLoc   <= to_unsigned(   0, availLoc'length);
         else
            fullSlots  <= resize( diff, fullSlots'length );
            availLoc   <= 2048 - resize( diff, availLoc'length );
         end if;
      end process P_COUNT;
   end generate GEN_FIFO18;

   GEN_FIFO36 : if ( DEPTH_36kb ) generate
      signal rp        : std_logic_vector(12 downto 0);
      signal wp        : std_logic_vector(12 downto 0);
      signal diff      : unsigned        (11 downto 0);
      signal di,  do   : std_logic_vector(63 downto 0);
      signal dip, dop  : std_logic_vector( 7 downto 0);
   begin

      di(63 downto 8)               <= (others => '0');
      di( 7 downto 0)               <= fifoDi(7 downto 0);

      dip(7 downto 1)               <= (others => '0');
      dip(0 downto 0)               <= fifoDi(LST_C downto LST_C);

      fifoDo(7 downto 0)            <= do(7 downto 0);
      fifoDo(LST_C downto LST_C)    <= dop(0 downto 0);

      U_FIFO : component FIFO36E1
         generic map (
            DATA_WIDTH              => 9,
            DO_REG                  => USE_DO_REG_C,
            SIM_DEVICE              => "7SERIES",
            EN_SYN                  => true
         )
         port map (
            WRCLK                   => clk,
            RDCLK                   => clk,
            RST                     => fifoRstLoc,
            RSTREG                  => fifoRstLoc,

            REGCE                   => '1',

            DI                      => di,
            DIP                     => dip,
            WREN                    => fifoWem,

            DO                      => do,
            DOP                     => dop,
            RDEN                    => fifoRem,

            RDCOUNT                 => rp,
            WRCOUNT                 => wp,

            INJECTDBITERR           => '0',
            INJECTSBITERR           => '0',

            FULL                    => fifoFull,
            ALMOSTFULL              => open,
            EMPTY                   => open,
            ALMOSTEMPTY             => open,
            WRERR                   => open,
            RDERR                   => open
         );

      diff <= unsigned( wp(diff'range) ) - unsigned( rp(diff'range) );

      P_COUNT : process ( fifoFull, rp, wp ) is
      begin
         if ( fifoFull = '1' ) then
            fullSlots  <= to_unsigned(4096, fullSlots'length);
            availLoc   <= to_unsigned(   0, availLoc'length);
         else
            fullSlots  <= resize( diff, fullSlots'length );
            availLoc   <= 4096 - resize( diff, availLoc'length );
         end if;
      end process P_COUNT;
   end generate GEN_FIFO36;

   B_READ : block is
      type RegType is record
         vld   : std_logic;
      end record;

      constant REG_INIT_C : RegType := (
         vld => '0'
      );

      signal r          : RegType := REG_INIT_C;
      signal rin        : RegType;
   begin

      P_COMB : process ( r, fullSlots, fifoDo, strmRdyOb ) is
         variable v   : RegType;
         variable m   : Lan9254StrmMstType;
      begin
         v          := r;
         m          := LAN9254STRM_MST_INIT_C;
         m.ben      := "01";
         m.data     := x"00" & fifoDo(7 downto 0);
         m.last     := fifoDo(LST_C);
         m.valid    := r.vld;

         if ( ( r.vld and strmRdyOb) = '1' ) then
            -- output register is consumed
            v.vld := '0';
         end if;

         if ( (fullSlots > 0) and ( v.vld = '0' ) ) then
            -- if there is data and the output register will
            -- become available then enable a read cycle and
            -- mark the next output register valid
            fifoRe <= '1';
            v.vld  := '1';
         else
            -- either no data or output register full; stop
            -- reading.
            fifoRe <= '0';
         end if;

         strmMstOb <= m;
         rin       <= v;
      end process P_COMB;

      P_SEQ : process ( clk ) is
      begin
         if ( rising_edge( clk ) ) then
            if ( fifoRstExt = '1' ) then
               r <= REG_INIT_C;
            else
               r <= rin;
            end if;
         end if;
      end process P_SEQ;

   end block B_READ;

   B_WRITE : block is
      type RegType is record
         -- keep a temp buffer; we need to keep the last non-empty
         -- item around so that we can attach the 'last' flag in case
         -- the last beat has ben="00"!
         buf   : Lan9254StrmMstType;
         rdy   : std_logic;
      end record;

      constant REG_INIT_C : RegType := (
         buf   => LAN9254STRM_MST_INIT_C,
         rdy   => '0'
      );

      signal r          : RegType := REG_INIT_C;
      signal rin        : RegType;
   begin

      P_COMB : process ( r, availLoc, strmMstIb  ) is
         variable v         : RegType;
      begin
         v                  := r;

         fifoWe             <= '0';
         -- default mux setting for fifoDi
         fifoDi(LST_C)      <= r.buf.last;
         fifoDi(7 downto 0) <= r.buf.data(7 downto 0);

         -- see if we transfer data from the temp buffer
         if ( ( r.buf.valid = '1' ) and (availLoc > 0 ) ) then
            if ( ( r.buf.ben = "11" ) ) then
               -- safe to ship one item
               fifoWe             <= '1';
               fifoDi(LST_C)      <= '0';
               v.buf.ben          := "10";
            elsif ( r.buf.last = '1' ) then
               -- may ship the last item
               fifoWe             <= '1';
               if ( r.buf.ben = "10" ) then
                  fifoDi(7 downto 0) <= r.buf.data(15 downto 8);
               end if;
               v.buf.valid        := '0';
            elsif ( (strmMstIb.valid = '1') and (strmMstIb.last = '1' or strmMstIb.ben /= "00" ) ) then
               -- if we have new data coming in then we may transfer
               fifoWe             <= '1';
               if ( r.buf.ben = "10" ) then
                  fifoDi(7 downto 0) <= r.buf.data(15 downto 8);
               end if;
               if ( (strmMstIb.last = '1') and (strmMstIb.ben = "00") ) then
                  -- empty beat; attach the last flag to *this* beat
                  fifoDi(LST_C) <= '1';
               end if;
               v.buf.valid      := '0';
            end if;
         end if;

         -- consume an item from the stream
         strmRdyIb  <= not v.buf.valid;

         if ( (strmMstIb.valid and not v.buf.valid) = '1' ) then
            if ( strmMstIb.ben = "00" ) then
               -- drop empty beat; if it carries a LAST flag then
               -- we handled that above
            else
               v.buf := strmMstIb;
            end if;
         end if;

         rin        <= v;
         tst <= v.buf.valid;
      end process P_COMB;
 
      P_SEQ : process ( clk ) is
      begin
         if ( rising_edge( clk ) ) then
            if ( fifoRstExt = '1' ) then
               r <= REG_INIT_C;
            else
               r <= rin;
            end if;
         end if;
      end process P_SEQ;

   end block B_WRITE;

   fifoRst    <= fifoRstExt;
   emptySlots <= availLoc;

end architecture rtl;
