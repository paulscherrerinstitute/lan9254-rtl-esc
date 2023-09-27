------------------------------------------------------------------------------
--      Copyright (c) 2022-2023 by Paul Scherrer Institute, Switzerland
--      All rights reserved.
--  Authors: Till Straumann
--  License: PSI HDL Library License, Version 2.0 (see License.txt)
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

-- EEPROM emulation support helpers for Lan9254 ESC;
-- the functions in this package marshal eeprom
-- contents into words of the required size (16-bit
-- for writing, 64-bit for reading).

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
      eep                                   <= eep;
      eep( to_integer( unsigned( addr ) ) ) <= val(15 downto 0);
   end procedure writeEEPROMEmul;

   procedure readEEPROMEmul(
      signal   eep   : in    EEPromArray;
      constant addr  : in    std_logic_vector(31 downto 0);
      variable loval : out   std_logic_vector(31 downto 0);
      variable hival : out   std_logic_vector(31 downto 0)
   ) is
      variable val : std_logic_vector(63 downto 0);
      variable idx : integer;
      variable v16 : std_logic_vector(15 downto 0);
   begin
--report "EEPROM READ @ " & integer'image(to_integer(unsigned(addr(15 downto 0))));
      for w in 0 to 3 loop
--report "    " &  integer'image(to_integer(unsigned(eeprom( to_integer(unsigned(addr(15 downto 0))) + w ))));
         idx := to_integer(unsigned(addr(15 downto 0))) + w;
         if ( idx <= eep'high ) then
            v16 := eep( idx );
         else
            v16 := (others => '0');
         end if;
         val(w*16 + 15 downto w*16) := v16;
      end loop;
      hival := val(63 downto 32);
      loval := val(31 downto  0);
   end procedure readEEPROMEmul;

end package body EEEMulPkg;
