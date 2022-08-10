library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.ESCBasicTypesPkg.all;
use work.Lan9254Pkg.all;

-- Synchronous fifo buffer (usr bits are ignored!)

entity StrmFifoSync is
   generic (
      -- depth in bytes
      DEPTH_G     : positive
   );
   port (
      clk         : in  std_logic;
      rst         : in  std_logic;

      strmMstIb   : in  Lan9254StrmMstType    := LAN9254STRM_MST_INIT_C;
      strmRdyIb   : out std_logic;
      emptySlots  : out unsigned(numBits(DEPTH_G) - 1 downto 0);

      fullSlots   : out unsigned(numBits(DEPTH_G) - 1 downto 0);
      -- data available on cycle after rdEn is asserted
      dataOut     : out std_logic_vector(7 downto 0);
      rdEn        : in  std_logic             := '1'
   );
end entity StrmFifoSync;

architecture rtl of StrmFifoSync is

   subtype MemIdx is natural range 0 to DEPTH_G - 1;

   type MemArray is array (0 to DEPTH_G - 1) of std_logic_vector(7 downto 0);

   attribute RAM_STYLE        : string;


   signal   mem               : MemArray := (others => (others => '0'));
   attribute RAM_STYLE of mem : signal is "block";

   signal rdp                 : MemIdx := 0;
   signal wrp                 : MemIdx := 0;

   type RegType is record
      rdy        : std_logic;
      tmp        : std_logic_vector(7 downto 0);
      tmpVld     : std_logic;
      emptySlots : natural range 0 to DEPTH_G;
      fullSlots  : natural range 0 to DEPTH_G;
   end record;

   constant REG_INIT_C : RegType := (
      rdy        => '1',
      tmp        => (others => '0'),
      tmpVld     => '0',
      emptySlots => DEPTH_G,
      fullSlots  => 0
   );

   signal r      : RegType := REG_INIT_C;
   signal rin    : RegType;

   signal wrEn   : std_logic;
   signal wrData : std_logic_vector(7 downto 0);

begin

   P_RAMRD : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            rdp <= 0;
         elsif ( ( rdEn = '1' ) and (r.fullSlots > 0) ) then
            dataOut <= mem( rdp );
            if ( rdp = DEPTH_G - 1 ) then
               rdp <= 0;
            else
               rdp <= rdp + 1;
            end if;
         end if;
      end if;
   end process P_RAMRD;

   P_RAMWR : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            wrp <= 0;
         elsif ( wrEn = '1' ) then
            mem( wrp ) <= wrData;
            if ( wrp = DEPTH_G - 1 ) then
               wrp <= 0;
            else
               wrp <= wrp + 1;
            end if;
         end if;
      end if;
   end process P_RAMWR;

   P_RAMWR_COMB : process ( r, rdEn, strmMstIb ) is
      variable v   : RegType;
      variable inc : integer range -1 to 1;
   begin

      v := r;

      if ( (rdEn = '1') and (r.fullSlots /= 0) ) then
         inc := -1;
      else
         inc :=  0;
      end if;

      wrEn   <= '0';
      wrData <= r.tmp;

      if ( r.rdy = '1' ) then
         -- can absorb more data
         if ( strmMstIb.valid = '1' ) then
            if ( strmMstIb.ben /= "00" ) then
               inc := inc + 1;
               if ( strmMstIb.ben = "11" ) then
                  -- stop until we write hi-byte
                  v.rdy    := '0';
                  v.tmp    := strmMstIb.data(15 downto 8);
                  v.tmpVld := '1';
               end if;
               if ( strmMstIb.ben(0) = '1' ) then
                  wrData <= strmMstIb.data( 7 downto 0);
               else
                  wrData <= strmMstIb.data(15 downto 8);
               end if;
               wrEn <= '1';
            end if;
         end if;
      else
         if ( r.tmpVld = '1' ) then
            wrEn       <= '1';
            v.tmpVld   := '0';
            inc        := inc + 1;
         end if;
      end if;
      v.fullSlots  := r.fullSlots  + inc;
      v.emptySlots := r.emptySlots - inc;
      if ( v.tmpVld = '1' ) then
         -- must hold off for 1 cycle to store 2nd byte
         v.rdy := '0';
      elsif ( v.emptySlots >= 2 ) then
         -- can definitely accept more data
         v.rdy := '1';
      else
         if ( (r.rdy = '0') and (strmMstIb.valid = '1') ) then
            if ( strmMstIb.ben = "00" or (v.emptySlots = 1 and (strmMstIb.ben = "01" or strmMstIb.ben = "10") ) ) then
             -- we will be able to accommodate this one
               v.rdy := '1';
            end if;
         else
            v.rdy := '0';
         end if;
      end if;
      rin <= v;
   end process P_RAMWR_COMB;

   P_RAMWR_SEQ : process (clk) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_RAMWR_SEQ;

   strmRdyIb <= r.rdy;

   emptySlots <= to_unsigned(r.emptySlots, emptySlots'length);
   fullSlots  <= to_unsigned(r.fullSlots,  fullSlots'length);

end architecture rtl;
