library ieee;
use     ieee.std_logic_1164.all;

package IlaWrappersPkg is

   component Ila_256 is
      port (
         clk    : in std_logic;
         probe0 : in std_logic_vector(63 downto 0);
         probe1 : in std_logic_vector(63 downto 0);
         probe2 : in std_logic_vector(63 downto 0);
         probe3 : in std_logic_vector(63 downto 0)
      );
   end component Ila_256;

end package IlaWrappersPkg;
