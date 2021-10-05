library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

package MicroUDPPkg is

   constant MAC_HDR_SIZE_C : natural := 14;
   constant IP4_HDR_SIZE_C : natural := 20;
   constant UDP_HDR_SIZE_C : natural := 8;


   type EthPktType is (ARP_REP, PING_REP, UDP);

   type EthTxReqType is record
      valid     : std_logic;
      dstMac    : std_logic_vector(47 downto 0); -- network-byte-order
      dstIp     : std_logic_vector(31 downto 0); -- network-byte-order
      protoData : std_logic_vector(15 downto 0); -- network-byte-order
      length    : unsigned        (15 downto 0);
      typ       : EthPktType;
   end record EthTxReqType;

   constant ETH_TX_REQ_INIT_C : EthTxReqType := (
      valid     => '0',
      dstMac    => (others => '0'),
      dstIp     => (others => '0'),
      protoData => (others => '0'),
      length    => (others => '0'),
      typ       => UDP
   );

end package MicroUDPPkg;
