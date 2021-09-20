library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.EEPROMContentPkg.all;

package EEEMulPkg is

   procedure writeEEPROMEmul(
      signal   eep   : inout EEPromArray;
      constant addr  : in   std_logic_vector(31 downto 0);
      constant val   : in   std_logic_vector(31 downto 0)
   );

   procedure readEEPROMEmul(
      signal   eep   : in   EEPROMArray;
      constant addr  : in   std_logic_vector(31 downto 0);
      variable loval : out  std_logic_vector(31 downto 0);
      variable hival : out  std_logic_vector(31 downto 0)
   );

end package EEEMulPkg;

package body EEEMulPkg is


   procedure writeEEPROMEmul(
      signal   eep   : inout EEPromArray;
      constant addr  : in    std_logic_vector(31 downto 0);
      constant val   : in    std_logic_vector(31 downto 0)
   )
   is
   begin
      eep( to_integer( unsigned( addr ) ) ) <= val(15 downto 0);
   end procedure writeEEPROMEmul;

   procedure readEEPROMEmul(
      signal   eep   : in    EEPromArray;
      constant addr  : in    std_logic_vector(31 downto 0);
      variable loval : out   std_logic_vector(31 downto 0);
      variable hival : out   std_logic_vector(31 downto 0)
   ) is
      variable val : std_logic_vector(63 downto 0);
   begin
--report "EEPROM READ @ " & integer'image(to_integer(unsigned(addr(15 downto 0))));
      for w in 0 to 3 loop
--report "    " &  integer'image(to_integer(unsigned(eeprom( to_integer(unsigned(addr(15 downto 0))) + w ))));
         val(w*16 + 15 downto w*16) := eep( to_integer(unsigned(addr(15 downto 0))) + w );
      end loop;
      hival := val(63 downto 32);
      loval := val(31 downto  0);
   end procedure readEEPROMEmul;

end package body EEEMulPkg;
