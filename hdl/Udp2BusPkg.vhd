library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

package Udp2BusPkg is
   type Udp2BusReqType is record
      valid  : std_logic;
      dwaddr : std_logic_vector(29 downto 0); -- double-word address
      data   : std_logic_vector(31 downto 0);
      be     : std_logic_vector( 3 downto 0);
      rdnwr  : std_logic;
   end record Udp2BusReqType;

   constant UDP2BUSREQ_INIT_C : Udp2BusReqType := (
      valid  => '0',
      dwaddr => (others => '0'),
      data   => (others => '0'),
      be     => (others => '0'),
      rdnwr  => '1'
   );

   type Udp2BusRepType is record
      valid  : std_logic;
      rdata  : std_logic_vector(31 downto 0);
      berr   : std_logic;
   end record Udp2BusRepType;

   constant UDP2BUSREP_INIT_C : Udp2BusRepType := (
      valid  => '0',
      rdata  => (others => '0'),
      berr   => '0'
   );

   constant UDP2BUSREP_ERROR_C : Udp2BusRepType := (
      valid  => '1',
      rdata  => x"deadbeef",
      berr   => '1'
   );


   type Udp2BusReqArray is array ( natural range <> ) of Udp2BusReqType;
   type Udp2BusRepArray is array ( natural range <> ) of Udp2BusRepType;

end package Udp2BusPkg;
