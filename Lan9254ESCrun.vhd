library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.Lan9254Pkg.all;

entity Lan9254ESCTb is
end entity Lan9254ESCTb;

architecture rtl of Lan9254ESCTb is
   signal clk : std_logic := '0';
   signal rst : std_logic := '0';
   signal run : boolean   := true;

   signal req : Lan9254ReqType := LAN9254REQ_INIT_C;
   signal rep : Lan9254RepType := LAN9254REP_INIT_C;

   signal al  : std_logic_vector(31 downto 0) := x"0000_0002";
   signal as  : std_logic_vector(31 downto 0) := x"0000_0001";

   signal cnt : integer := 0;

begin

   process is begin
      if ( run ) then
         wait for 10 us;
         clk <= not clk;
      else
         wait;
      end if;
   end process;

--   process ( clk ) is
--   begin
--      if ( rising_edge( clk ) ) then
--         cnt <= cnt + 1;
--         if ( cnt = 10000 ) then
--            run <= false;
--         end if;
--      end if;
--   end process;

   U_DUT : entity work.Lan9254ESC
      port map (
         clk         => clk,
         rst         => rst,

         req         => req,
         rep         => rep
      );

   U_HBI : entity work.Lan9254Hbi
      generic map (
         CLOCK_FREQ_G => 12.0E6
      )
      port map (
         clk         => clk,
         rst         => rst,
         req         => req,
         rep         => rep
      );

end architecture rtl;
