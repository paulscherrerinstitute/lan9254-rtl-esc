library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Udp2BusPkg.all;

entity Udp2BusMux is
   generic (
      ADDR_MSB_G    : natural := 19;
      ADDR_LSB_G    : natural := 17;
      NUM_SUBS_G    : natural
   );
   port (
      clk         : in  std_logic;
      rst         : in  std_logic;

      reqIb       : in  Udp2BusReqType                           := UDP2BUSREQ_INIT_C;
      repIb       : out Udp2BusRepType;

      reqOb       : out Udp2BusReqArray(NUM_SUBS_G - 1 downto 0) := (others => UDP2BUSREQ_INIT_C);
      repOb       : in  Udp2BusRepArray(NUM_SUBS_G - 1 downto 0) := (others => UDP2BUSREP_ERROR_C)
   );
end entity Udp2BusMux;

architecture rtl of Udp2BusMux is
begin

   assert NUM_SUBS_G <= 2**(ADDR_MSB_G - ADDR_LSB_G + 1);

   P_MUX  : process (reqIb, repOb) is
      variable sel : natural range 0 to 2**(ADDR_MSB_G - ADDR_LSB_G + 1) - 1;
   begin
      reqOb       <= (others => reqIb);
      repIb       <= UDP2BUSREP_ERROR_C;
      for i in reqOb'range loop
         reqOb(i).valid <= '0';
      end loop;
      sel := to_integer(unsigned(reqIb.dwaddr(ADDR_MSB_G downto ADDR_LSB_G)));
      if ( sel < NUM_SUBS_G ) then
         reqOb(sel).valid <= reqIb.valid;
         repIb            <= repOb(sel);
      end if;
   end process P_MUX;

end architecture rtl;
