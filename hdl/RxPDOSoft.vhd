library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

-- Wrapper module to provide a simulated RXPDO;
-- the RXPDO data is consumed by C-code (which
-- flashes LEDs on the development board).

use work.Lan9254Pkg.all;
use work.Lan9254ESCPkg.all;

entity RxPDOSoft is
   port (
      clk      : std_logic;
      rst      : std_logic;

      rxPDOMst : in  Lan9254PDOMstType;
      rxPDORdy : out std_logic
   );
end entity RxPDOSoft;

architecture rtl of RxPDOSoft is

   procedure writeRxPDO_C (
      constant wrdAddr : in  integer;
      constant wrdVal  : in  integer;
      constant be      : in  integer
   );

   attribute foreign of writeRxPDO_C : procedure is "VHPIDIRECT writeRxPDO_C";

   procedure writeRxPDO_C (
      constant wrdAddr : in  integer;
      constant wrdVal  : in  integer;
      constant be      : in  integer
   ) is
   begin
      assert false report "writeRXPDO_C (vhdl) should never be executed" severity failure;
   end procedure writeRxPDO_C;

   signal rxPDORdyLoc : std_logic := '1';

begin

   P_RX : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( ( rxPDORdyLoc and rxPDOMst.valid ) = '1' ) then
--report "RXPDO @" & toString(rxPDOMst.wrdAddr) & " BE " & toString(rxPDOMst.ben) & " :" & toString(rxPDOMst.data);
            writeRxPDO_C(
               to_integer( unsigned( rxPDOMst.wrdAddr ) ),
               to_integer( unsigned( rxPDOMst.data    ) ),
               to_integer( unsigned( rxPDOMst.ben     ) )
            );
         end if;
      end if;
   end process P_RX;

   rxPDORdyLoc <= '1';

   rxPDORdy    <= rxPDORdyLoc;

end architecture rtl;
