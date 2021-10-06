library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.Lan9254Pkg.all;
use work.ESCMbxPkg.all;

-- RX Mailbox de-multiplexer

entity ESCRxMbxMux is
   generic (
      -- tags of the streams to demux
      STREAM_CONFIG_G : ESCMbxArray
   );
   port (
      clk     : in  std_logic;
      rst     : in  std_logic;

      mbxIb   : in  Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      rdyIb   : out std_logic          := '1';

      mbxOb   : out Lan9254StrmMstArray(STREAM_CONFIG_G'length - 1 downto 0) := (others => LAN9254STRM_MST_INIT_C);
      rdyOb   : in  std_logic_vector   (STREAM_CONFIG_G'length - 1 downto 0) := (others => '1')
   );
end entity ESCRxMbxMux;

architecture rtl of ESCRxMbxMux is

   type StateType is ( SEL, FWD );

   constant NUM_STREAMS_C : natural := STREAM_CONFIG_G'length;

   type RegType   is record
      state    : StateType;
      sel      : natural range 0 to NUM_STREAMS_C - 1;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state    => SEL,
      sel      => 0
   );

   signal   r        : RegType                       := REG_INIT_C;
   signal   rin      : RegType;
begin

   P_COMB : process ( r, mbxIb, rdyOb ) is
      variable   v : RegType;
      variable   m : Lan9254StrmMstArray(NUM_STREAMS_C - 1 downto 0);
   begin

      v := r;
      m := (others => mbxIb);
      for i in m'range loop
         m(i).valid := '0';
      end loop;

      rdyIb <= '0';

      case ( r.state ) is
         when SEL =>
            FOR_SEL : for i in 0 to NUM_STREAMS_C - 1 loop
               if ( STREAM_CONFIG_G(i) = mbxIb.usr(3 downto 0) ) then
                  v.sel      := i;
                  m(i).valid := mbxIb.valid;
                  rdyIb      <= rdyOb(i);
                  if ( rdyOb(i) = '1' ) then
                     if ( mbxIb.last = '0' ) then
                        v.state := FWD;
                     end if;
                  end if;
                  exit FOR_SEL;
               end if;
            end loop FOR_SEL;

         when FWD   =>
            m(r.sel).valid := mbxIb.valid;
            rdyIb          <= rdyOb(r.sel);
            if ( ( mbxIb.valid and rdyOb(r.sel) and mbxIb.last ) = '1' ) then
               v.state := SEL;
            end if;
      end case;

      rin   <= v;
      mbxOb <= m;
   end process P_COMB;

   P_SEQ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;
end architecture rtl;
