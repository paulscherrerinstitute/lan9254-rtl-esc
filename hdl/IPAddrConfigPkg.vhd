library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.ESCBasicTypesPkg.all;

package IPAddrConfigPkg is

   type IPAddrConfigType is record
      macAddr    : std_logic_vector(47 downto 0); -- network byte order
      macAddrVld : std_logic;
      ip4Addr    : std_logic_vector(31 downto 0); -- network byte order
      ip4AddrVld : std_logic;
      udpPort    : std_logic_vector(15 downto 0); -- network byte order
      udpPortVld : std_logic;
   end record IPAddrConfigType;

   -- serialize in the order elements appear in the array.
   -- Items are serialized in network-byte order. The 'valid'
   -- flags are omitted.
   function toSlv08Array(constant x : IPAddrConfigType) return Slv08Array;

   -- deserialize; valid flags are cleared
   function toIPAddrConfigType(constant x : Slv08Array) return IPAddrConfigType;

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

   -- serialize in the order elements appear in the array.
   -- Items are serialized in network-byte order. The 'valid'
   -- flags are omitted.
   function toSlv08Array(constant x : IPAddrConfigType) return Slv08Array is
      constant c : Slv08Array := (
         0 => x.macAddr( 7 downto  0),
         1 => x.macAddr(15 downto  8),
         2 => x.macAddr(23 downto 16),
         3 => x.macAddr(31 downto 24),
         4 => x.macAddr(47 downto 40),
         5 => x.macAddr(63 downto 48),

         6 => x.ip4Addr( 7 downto  0),
         7 => x.ip4Addr(15 downto  8),
         8 => x.ip4Addr(23 downto 16),
         9 => x.ip4Addr(31 downto 24),

        10 => x.udpPort( 7 downto  0),
        11 => x.udpPort(15 downto  8)
      );
   begin
      return c;
   end function toSlv08Array;

   -- deserialize; valid flags are cleared
   function toIPAddrConfigType(constant x : Slv08Array) return IPAddrConfigType is
      constant c : IPAddrConfigType := (
         macAddr    => x(5) & x(4) & x(3) & x(2) & x(1) & x(0),
         macAddrVld => '0',
         ip4Addr    =>               x(9) & x(8) & x(6) & x(6),
         ip4AddrVld => '0',
         udpPort    =>                            x(11) & x(10),
         udpPortVld => '0'
      );
   begin
      return c;
   end function toIPAddrConfigType;


end package body IPAddrConfigPkg;
