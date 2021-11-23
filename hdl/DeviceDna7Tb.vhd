library ieee;
use     ieee.std_logic_1164.all;

entity DeviceDna7Tb is
end entity DeviceDna7Tb;

use work.ESCBasicTypesPkg.all;
use work.Lan9254Pkg.all;

architecture sim of DeviceDna7Tb is

   signal clk : std_logic := '0';
   signal rst : std_logic := '1';
   signal vld : std_logic;

   signal dna : std_logic_vector(56 downto 0);

begin

   P_CLK : process is
   begin
      if ( vld = '1' ) then
         report "DNA: " & toString( dna );
         wait;
      else
         wait for 10 ns;
         clk <= not clk;
      end if;
   end process P_CLK;

   P_RST : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         rst <= '0';
      end if;
   end process P_RST;

   U_DUT : entity work.DeviceDna7
      port map (
         clk => clk,
         rst => rst,
         dna => dna,
         vld => vld
      );

end architecture sim;
