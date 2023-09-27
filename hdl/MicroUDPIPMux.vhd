------------------------------------------------------------------------------
--      Copyright (c) 2022-2023 by Paul Scherrer Institute, Switzerland
--      All rights reserved.
--  Authors: Till Straumann
--  License: PSI HDL Library License, Version 2.0 (see License.txt)
------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Lan9254Pkg.all;
use     work.MicroUDPPkg.all;

-- mux to arbitrate access to 'ipTx' between ICMP (when
-- received on ipRxMst) and UDP (from user/udpTxMst).

entity MicroUDPIPMux is
   port (
      clk        : in  std_logic;
      rst        : in  std_logic;
      
      ipRxMst    : in  Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      ipRxRdy    : out std_logic;
      ipRxReq    : in  EthTxReqType       := ETH_TX_REQ_INIT_C;
      ipRxAck    : out std_logic;

      ipTxMst    : out Lan9254StrmMstType;
      ipTxRdy    : in  std_logic          := '1';
      ipTxReq    : out EthTxReqType       := ETH_TX_REQ_INIT_C;
      ipTxAck    : in  std_logic          := '1';

      udpRxMst   : out UdpStrmMstType;
      udpRxRdy   : in  std_logic          := '1';

      udpTxMst   : in  UdpStrmMstType     := UDP_STRM_MST_INIT_C;
      udpTxRdy   : out std_logic;

      debug      : out std_logic_vector(7 downto 0)
   );
end entity MicroUDPIPMux;

architecture rtl of MicroUDPIPMux is

   type StateType is ( IDLE, RCV_UDP, LOOPBACK );

   type RegType is record
      state           : StateType;
      udpTxInProgress : boolean;
      udpTxReqVld     : std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state           => IDLE,
      udpTxInProgress => false,
      udpTxReqVld     => '0'
   );

   signal   r         : RegType := REG_INIT_C;
   signal   rin       : RegType;

begin

   P_COMB : process ( r,
                      ipRxMst, ipRxReq,
                      ipTxRdy, ipTxAck,
                      udpRxRdy,
                      udpTxMst ) is
      variable v      : RegType;
   begin

      v  := r;

      udpRxMst            <= toUdpStrmMst( ipRxReq, ipRxMst );
      udpRxMst.strm.valid <= '0';
      ipRxRdy             <= '0';
      ipRxAck             <= '0';

      -- by default switch the UDP TX stream through
      ipTxMst             <= udpTxMst.strm;
      udpTxRdy            <= ipTxRdy;

      -- track the state of the UDP TX channel
      if ( udpTxMst.strm.valid = '1' ) then
         -- potentially start
         if ( not v.udpTxInProgress ) then
            -- mark the TxReq valid (maybe acked and reset before the TX ends)
            v.udpTxReqVld := '1';
         end if;
         v.udpTxInProgress := true;

         if ( ( ipTxRdy and udpTxMst.strm.last ) = '1' ) then
            v.udpTxInProgress := false;
         end if;
      end if;

      ipTxReq             <= toEthTxReq( udpTxMst );
      ipTxReq.valid       <= v.udpTxReqVld;

      if ( ( r.udpTxReqVld and ipTxAck ) = '1' ) then
         v.udpTxReqVld := '0';
      end if;

      case ( r.state ) is
         when IDLE =>
            if ( ipRxReq.valid = '1' ) then
               if ( ( ipRxReq.typ = PING_REP ) or ( ipRxReq.typ = ARP_REP ) ) then
                  -- wait for an ongoing transmission to end
                  if ( not v.udpTxInProgress or not r.udpTxInProgress ) then
                     -- make sure they didn't just try to start
                     udpTxRdy          <= '0';
                     ipTxMst.valid     <= '0';
                     ipTxReq.valid     <= '0';
                     v.udpTxReqVld     := '0';
                     v.udpTxInProgress := false;
                     v.state           := LOOPBACK;
                  end if;
               else
                  v.state := RCV_UDP;
               end if;
            end if;

         when LOOPBACK =>
            udpTxRdy            <= '0';   -- stop the UDP TX channel
            v.udpTxInProgress   := false; -- in case they just attempted to start
            v.udpTxReqVld       := '0';
            ipTxMst             <= ipRxMst;
            ipRxRdy             <= ipTxRdy;
            ipTxReq             <= ipRxReq;
            ipRxAck             <= ipTxAck;
            v.udpTxInProgress   := false;
            v.udpTxReqVld       := '0';
            if ( (ipTxAck and ipRxReq.valid ) = '1' ) then
               v.state := IDLE;
            end if;

         when RCV_UDP =>
            udpRxMst.strm.valid <= ipRxMst.valid;
            ipRxRdy             <= udpRxRdy;
            ipRxAck             <= ipRxMst.valid and ipRxMst.last and udpRxRdy;
            if ( ( ipRxMst.valid and ipRxMst.last and udpRxRdy ) = '1' ) then
               v.state := IDLE;
            end if;
      end case;
      
      rin <= v;
   end process P_COMB;

   P_SEQ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

   debug(1 downto 0) <= std_logic_vector( to_unsigned( StateType'pos( r.state ), 2 ) );
   debug(7 downto 2) <= (others => '0');

end architecture rtl;
