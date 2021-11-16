library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Lan9254Pkg.all;
use     work.IPAddrConfigPkg.all;

package MicroUDPPkg is

   constant MAC_HDR_SIZE_C : natural := 14;
   constant IP4_HDR_SIZE_C : natural := 20;
   constant UDP_HDR_SIZE_C : natural := 8;

   type EthPktType is (ARP_REP, PING_REP, UDP);

   type EthTxReqType is record
      valid     : std_logic;
      dstMac    : std_logic_vector(47 downto 0); -- network-byte order
      dstIp     : std_logic_vector(31 downto 0); -- network-byte order
      protoData : std_logic_vector(15 downto 0); -- network-byte order
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

   type UdpStrmMstType is record
      -- data is stable once 'stream.valid' is asserted and remain stable
      -- until 'valid and last and ready'.
      addr      : IPAddrConfigType;
      -- length includes all headers and goes into IP and UPD headers
      -- processing of the stream relies on the 'last' flag though
      length    : unsigned        (15 downto 0); -- host-byte order
      strm      : Lan9254StrmMstType;
   end record UdpStrmMstType;

   constant UDP_STRM_MST_INIT_C : UdpStrmMstType := (
      addr      => makeIPAddrConfig,
      -- length includes all headers and goes into IP and UPD headers
      -- processing of the stream relies on the 'last' flag though
      length    => (others => '0'),
      strm      => LAN9254STRM_MST_INIT_C
   );

   function toUdpStrmMst(
      constant t : in  EthTxReqType;
      constant s : in  Lan9254StrmMstType
   ) return UdpStrmMstType;

   function toEthTxReq(
      constant u : in  UdpStrmMstType
   ) return EthTxReqType;

end package MicroUDPPkg;

package body MicroUDPPkg is

   function toUdpStrmMst(
      constant t : in  EthTxReqType;
      constant s : in  Lan9254StrmMstType
   ) return UdpStrmMstType is
      variable v : UdpStrmMstType;
   begin
      v         := UDP_STRM_MST_INIT_C;
      v.addr    := makeIPAddrConfig(t.dstMac, t.dstIp, t.protoData);
      v.length  := t.length;
      v.strm    := s;
      return v;
   end function toUdpStrmMst;

   function toEthTxReq(
      constant u : in  UdpStrmMstType
   ) return EthTxReqType is
      variable rv : EthTxReqType;
   begin
      rv           := ETH_TX_REQ_INIT_C;
      rv.dstMac    := u.addr.macAddr;
      rv.dstIp     := u.addr.ip4Addr;
      rv.protoData := u.addr.udpPort;
      rv.length    := u.length;
      rv.typ       := UDP;
      rv.valid     := '0';
      return rv;
   end function toEthTxReq;

end package body MicroUDPPkg;
