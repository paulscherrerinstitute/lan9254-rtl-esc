library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

package IPAddrConfigPkg is

   type IPAddrConfigType is record
      macAddr    : std_logic_vector(47 downto 0); -- network byte order
      macAddrVld : std_logic;
      ip4Addr    : std_logic_vector(31 downto 0); -- network byte order
      ip4AddrVld : std_logic;
      udpPort    : std_logic_vector(15 downto 0); -- network byte order
      udpPortVld : std_logic;
   end record IPAddrConfigType;

   type IPAddrConfigAckType is record
      macAddrAck : std_logic;
      ip4AddrAck : std_logic;
      udpPortAck : std_logic;
   end record IPAddrConfigAckType;

   constant IP_ADDR_CONFIG_ACK_INIT_C : IPAddrConfigAckType := (
      macAddrAck => '0',
      ip4AddrAck => '0',
      udpPortAck => '0'
   );

   constant IP_ADDR_CONFIG_ACK_ASSERT_C : IPAddrConfigAckType := (
      macAddrAck => '1',
      ip4AddrAck => '1',
      udpPortAck => '1'
   );

   type IPAddrConfigArray    is array (natural range <>) of IPAddrConfigType;
   type IPAddrConfigAckArray is array (natural range <>) of IPAddrConfigAckType;

   function makeIPAddrConfig(
      constant macAddr : std_logic_vector := "";
      constant ip4Addr : std_logic_vector := "";
      constant udpPort : std_logic_vector := ""
   ) return IPAddrConfigType;

end package IPAddrConfigPkg;

package body IPAddrConfigPkg is

   function makeIPAddrConfig(
      constant macAddr : std_logic_vector := "";
      constant ip4Addr : std_logic_vector := "";
      constant udpPort : std_logic_vector := ""
   ) return IPAddrConfigType is
      variable v : IPAddrConfigType;
   begin
      v.macAddr    := (others => '0');
      v.macAddrVld := '0';
      v.ip4Addr    := (others => '0');
      v.ip4AddrVld := '0';
      v.udpPort    := (others => '0');
      v.udpPortVld := '0';
      if ( macAddr'length > 0 ) then
         v.macAddr(macAddr'range) := macAddr;
         v.macAddrVld             := '1';
      end if;
      if ( ip4Addr'length > 0 ) then
         v.ip4Addr(ip4Addr'range) := ip4Addr;
         v.ip4AddrVld             := '1';
      end if;
      if ( udpPort'length > 0 ) then
         v.udpPort(udpPort'range) := udpPort;
         v.udpPortVld             := '1';
      end if;
      return v;
   end function makeIPAddrConfig;

end package body IPAddrConfigPkg;
