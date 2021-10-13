library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Lan9254Pkg.all;
use     work.Lan9254ESCPkg.all;
use     work.MicroUDPPkg.all;

entity MicroUdpRx is
   generic (
      MAX_FRAME_SIZE_G : natural := 1472
   );
   port (
      clk      : in  std_logic;
      rst      : in  std_logic;

      myMac    : in  std_logic_vector(47 downto 0) := x"f106a98e0200";
      myIp     : in  std_logic_vector(31 downto 0) := x"0a0a0a0a";
      myPort   : in  std_logic_vector(15 downto 0) := x"6688";

      mstIb    : in  Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      errIb    : in  std_logic;
      rdyIb    : out std_logic;

      txReq    : out EthTxReqType;
      txRdy    : in  std_logic := '1';

      pldMstOb : out Lan9254StrmMstType;
      pldRdyOb : in  std_logic := '1';

      debug    : out std_logic_vector(15 downto 0);
      stats    : out StatCounterArray(16 downto 0)
   );
end entity MicroUdpRx;

architecture rtl of MicroUdpRx is

   constant ARP_SIZE_C : natural := 28;

   type StateType is (IDLE, MAC_HDR, IP_HDR, ARP_REQ, ICMP_REQ, UDP, DROP, FWD);

   type RegType   is record
      state       : StateType;
      cnt         : natural range 0 to 1500;
      txReq       : EthTxReqType;
      rdy         : std_logic;
      maybeBcst   : boolean;
      maybeUcst   : boolean;
      nMacDrp     : StatCounterType;
      nShtDrp     : StatCounterType;
      nArpHdr     : StatCounterType;
      nIP4Hdr     : StatCounterType;
      nUnkHdr     : StatCounterType;
      nArpDrp     : StatCounterType;
      nArpReq     : StatCounterType;
      nIP4Drp     : StatCounterType;
      nPinReq     : StatCounterType;
      nUdpReq     : StatCounterType;
      nUnkIP4     : StatCounterType;
      nIP4Mis     : StatCounterType;
      nPinDrp     : StatCounterType;
      nPinHdr     : StatCounterType;
      nUdpMis     : StatCounterType;
      nUdpHdr     : StatCounterType;
      nPktFwd     : StatCounterType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state       => IDLE,
      cnt         => 0,
      txReq       => ETH_TX_REQ_INIT_C,
      rdy         => '1',
      maybeBcst   => false,
      maybeUcst   => false,
      nMacDrp     => STAT_COUNTER_INIT_C,
      nShtDrp     => STAT_COUNTER_INIT_C,
      nArpHdr     => STAT_COUNTER_INIT_C,
      nIP4Hdr     => STAT_COUNTER_INIT_C,
      nUnkHdr     => STAT_COUNTER_INIT_C,
      nArpDrp     => STAT_COUNTER_INIT_C,
      nArpReq     => STAT_COUNTER_INIT_C,
      nIP4Drp     => STAT_COUNTER_INIT_C,
      nPinReq     => STAT_COUNTER_INIT_C,
      nUdpReq     => STAT_COUNTER_INIT_C,
      nUnkIP4     => STAT_COUNTER_INIT_C,
      nIP4Mis     => STAT_COUNTER_INIT_C,
      nPinDrp     => STAT_COUNTER_INIT_C,
      nPinHdr     => STAT_COUNTER_INIT_C,
      nUdpMis     => STAT_COUNTER_INIT_C,
      nUdpHdr     => STAT_COUNTER_INIT_C,
      nPktFwd     => STAT_COUNTER_INIT_C
   );

   procedure matchMac(
      constant d : in    std_logic_vector(15 downto 0);
      variable v : inout RegType;
      variable r : out   boolean
   ) is
   begin
      v := v;
      case ( v.cnt ) is
         when 0 =>
            v.maybeBcst := (d = x"FFFF");
         when others =>
            if ( d /= x"FFFF" ) then
               v.maybeBcst := false;
            end if;
      end case;
      case ( v.cnt ) is
         when 0 =>
            v.maybeUcst := ( d  = myMac( 15 + 0*16 downto  0*16 ) );
         when 1 =>
            if ( d /= myMac( 15 + 1*16 downto  1*16 ) ) then
               v.maybeUcst := false;
            end if;
         when 2 =>
            if ( d /= myMac( 15 + 2*16 downto  2*16 ) ) then
               v.maybeUcst := false;
            end if;
         when others =>
            v.maybeUcst := false;
      end case;
      r := ( v.maybeUcst or v.maybeBcst );
   end procedure matchMac;

   procedure resetState(
      variable v : inout RegType
   ) is
   begin
      v           := v;
      v.cnt       := 0;
      v.state     := IDLE;
      v.rdy       := '1';
      v.maybeBcst := false;
   end procedure resetState;


   signal    r    : RegType := REG_INIT_C;
   signal    rin  : RegType;

begin

   P_COMB : process (r, myMac, myIp, myPort, mstIb, txRdy, pldRdyOb, errIb) is
      variable v  : RegType;
      variable ok : boolean;
      variable m  : Lan9254StrmMstType;
   begin
      v  := r;
      ok := false;

      rdyIb    <= r.rdy;
      m        := mstIb;
      m.valid  := '0';

      if ( ( r.txReq.valid and txRdy ) = '1' ) then
         v.txReq.valid := '0';
      end if;

      case ( r.state ) is
         when IDLE =>
            if ( ( mstIb.valid and not (errIb or mstIb.last) ) = '1' ) then
               if ( ( v.txReq.valid and not mstIb.last ) = '1' ) then
                  -- still have a pending TX Req. drop this message
                  v.state := DROP;
               end if;

               matchMac( mstIb.data, v, ok );
               if ( not ok ) then
                  v.state     := DROP;
                  v.nMacDrp   := r.nMacDrp + 1;
               else
                  v.cnt       := r.cnt + 1;
                  v.state     := MAC_HDR;
               end if;
            end if;
                  
         when MAC_HDR  =>

            if ( errIb = '1' ) then
               v.state := DROP;
            elsif ( mstIb.valid = '1' ) then
               if ( mstIb.last  = '1' ) then
                  v.state   := DROP;
                  v.nShtDrp := r.nShtDrp + 1;
               else
                  if ( r.cnt < 3 ) then
                     matchMac( mstIb.data, v, ok );
                     if ( not ok ) then
                        v.state     := DROP;
                        v.nMacDrp   := r.nMacDrp + 1;
                     end if;
                  else
report "MAC PASSED";
                     case ( r.cnt ) is
                        when 3 => v.txReq.dstMac(15 + 0*16 downto 0*16) := mstIb.data;
                        when 4 => v.txReq.dstMac(15 + 1*16 downto 1*16) := mstIb.data;
                        when 5 => v.txReq.dstMac(15 + 2*16 downto 2*16) := mstIb.data;
                        when others =>
                          if    ( mstIb.data = x"0608" ) then
                             v.state        := ARP_REQ;
                             v.txReq.length := to_unsigned( MAC_HDR_SIZE_C + ARP_SIZE_C, 16);
                             v.nArpHdr      := r.nArpHdr + 1;
                          elsif ( mstIb.data = x"0008" ) then
                             v.state        := IP_HDR;
                             v.nIP4Hdr      := r.nIP4Hdr + 1;
                          else
                             v.nUnkHdr      := r.nUnkHdr + 1;
                             v.state := DROP;
                          end if;
                     end case;
                  end if;
                  v.cnt := r.cnt + 1; -- matchMac evaluates v.cnt; increment last
               end if;
            end if;
                       
                  
         when ARP_REQ =>

            if ( errIb = '1' ) then
               v.state := DROP;
report "ARP_REQ error drop";
            elsif ( mstIb.valid = '1' ) then
               if ( ( mstIb.last  = '1' ) and ( r.cnt < 20 ) ) then
report "ARP_REQ early last drop";
                  v.nShtDrp   := r.nShtDrp + 1;
                  v.state     := DROP;
               else
                  v.cnt       := r.cnt + 1; -- resetState manipulates v.cnt; increment first
                  case ( r.cnt ) is
                     when  7 =>
                        if ( mstIb.data /= x"0100" ) then v.state := DROP; end if;
                     when  8 =>
                        if ( mstIb.data /= x"0008" ) then v.state := DROP; end if;
                     when  9 =>
                        if ( mstIb.data /= x"0406" ) then v.state := DROP; end if;
                     when 10 =>
                        if ( mstIb.data /= x"0100" ) then v.state := DROP; end if;
                     when 11 | 12 | 13 =>
                        -- use peer HWADDR from MAC header
                     when 14 =>
                        v.txReq.dstIp(15 downto  0) := mstIb.data;
                     when 15 =>
                        v.txReq.dstIp(31 downto 16) := mstIb.data;
                     when 16 | 17 | 18 =>
                     when 19     =>
                        if ( mstIb.data /= myIp(15 downto 0) ) then v.state := DROP; end if;
                     when others =>
                        if ( mstIb.data /= myIp(31 downto 16) ) then
                           v.state := DROP;
                        else
                           v.nArpReq     := r.nArpReq + 1;
                           v.txReq.typ   := ARP_REP;
                           v.txReq.valid := '1';
report "ARP_REQ OK, L " & std_logic'image(mstIb.last);
                           if ( mstIb.last = '1' ) then
                              resetState( v );
                           else
                              v.state   := DROP;
                           end if;
                        end if;
if ( v.state = DROP ) then
report "ARP_REQ drop @" & integer'image(r.cnt);
end if;
                  end case;
                  if ( v.state = DROP ) then
                     v.nArpDrp   := r.nArpDrp + 1;
                  end if;
               end if;
            end if;

         when IP_HDR =>
            if ( errIb = '1' ) then
               v.state := DROP;
            elsif ( mstIb.valid = '1' ) then
               if ( ( mstIb.last  = '1' ) ) then
report "IP_HDR early last drop";
                  v.state   := DROP;
                  v.nShtDrp := r.nShtDrp + 1;
               else
                  v.cnt     := r.cnt + 1;
                  case ( r.cnt ) is
                    when  7    =>
                       if ( mstIb.data(7 downto 0) /= x"45" ) then v.state := DROP; end if;
                    when  8    =>
                       v.txReq.length := unsigned( mstIb.data(7 downto 0) & mstIb.data(15 downto 8) ) + MAC_HDR_SIZE_C;
                       if ( v.txReq.length > MAX_FRAME_SIZE_G ) then
                          v.state := DROP;
                       end if;
                    when  9    =>
                    when 10    =>
                       if ( mstIb.data(7) = '1' ) then v.state := DROP; end if; -- MF
                    when 11    =>
                       case ( mstIb.data(15 downto 8) ) is
                          when x"01" =>
                             v.txReq.typ := PING_REP;
                          when x"11" =>
                             v.txReq.typ := UDP;
                          when others =>
                             v.nUnkIP4   := r.nUnkIP4 + 1;
                             v.state     := DROP;
                       end case;
                    when 12    => -- ignore checksum
                    when 13    =>
                       v.txReq.dstIp(15 downto  0) := mstIb.data;
                    when 14    =>
                       v.txReq.dstIp(31 downto 16) := mstIb.data;
                    when 15    =>
                       if ( myIp( 15 downto  0 ) /= mstIb.data ) then
                          v.nIP4Mis    := r.nIP4Mis + 1;
                          v.state      := DROP;
                       end if;
                    when others  =>
                       if ( myIp( 31 downto 16 ) /= mstIb.data ) then
                          v.nIP4Mis    := r.nIP4Mis + 1;
                          v.state      := DROP;
                       else
                          v.nIP4Hdr    := r.nIP4Hdr + 1;
                          if ( r.txReq.typ = PING_REP ) then
                             v.nPinReq := r.nPinReq + 1;
                             v.state   := ICMP_REQ;
report "IP HDR PASSED => ICMP";
                          else
report "IP HDR PASSED => UDP";
                             v.nUdpReq := r.nUdpReq + 1;
                             v.state   := UDP;
                          end if;
                       end if;
                  end case;
                  if ( v.state = DROP ) then
                     v.nIP4Drp := r.nIP4Drp + 1;
                  end if;
               end if;
            end if;
if ( v.state = DROP ) then
report "IP_HDR drop @" & integer'image(r.cnt) & " " & toString(mstIb.data);
end if;

         when ICMP_REQ =>
            if ( errIb = '1' ) then
               v.state := DROP;
            elsif ( mstIb.valid = '1' ) then
               if ( mstIb.last  = '1' ) then
                 v.state   := DROP;
                 v.nShtDrp := r.nShtDrp + 1;
               else
                  v.cnt := r.cnt + 1;
                  case ( r.cnt ) is
                     when     17 =>
                        if ( mstIb.data /= x"0008" ) then
                           v.state        := DROP;
                           v.nPinDrp      := r.nPinDrp + 1;
                        end if;
                     when others =>
                        v.state           := FWD;
                        v.txReq.valid     := '1';
                        v.nPinHdr         := r.nPinHdr + 1;
                        -- record checksum; sender may adjust
                        v.txReq.protoData := mstIb.data;
                  end case;
               end if;
            end if;

         when UDP =>
            if ( errIb = '1' ) then
               v.state := DROP;
            elsif ( mstIb.valid = '1' ) then
               if ( mstIb.last  = '1' ) then
                 v.state   := DROP;
                 v.nShtDrp := r.nShtDrp + 1;
               else
                  v.cnt := r.cnt + 1;
                  case ( r.cnt ) is
                     when 17 =>
                        v.txReq.protoData := mstIb.data;
                     when 18 =>
                        if ( mstIb.data /= myPort ) then
                           v.nUdpMis  := r.nUdpMis + 1;
                           v.state    := DROP;
                           -- should really send ICMP message
                        end if;
                     when 19 =>
                     when others =>
                        v.nUdpHdr     := r.nUdpHdr + 1;
                        v.state       := FWD;
                        v.txReq.valid := '1';
                  end case;
               end if;
            end if;

         when DROP =>
            if ( ( mstIb.valid = '1' ) ) then
               v.cnt := r.cnt + 1;
            end if;
            if ( ( ( mstIb.valid and mstIb.last ) or errIb ) = '1' ) then
               resetState( v );
            end if;

         when FWD =>
            rdyIb    <= pldRdyOb; 
            m.valid  := mstIb.valid;
            if ( errIb = '1' ) then
               m.last := '1';
            end if;
            if ( ( mstIb.valid and pldRdyOb ) = '1' ) then
               v.cnt := r.cnt + 1;
            end if;
            if ( (pldRdyOb and ( (mstIb.valid and mstIb.last) or errIb ) ) = '1' ) then
               v.nPktFwd := r.nPktFwd + 1;
               resetState( v );
            end if;

      end case;

      pldMstOb <= m;
      rin      <= v;
   end process P_COMB;

   txReq <= r.txReq;

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

   debug(10 downto  0) <= std_logic_vector( to_unsigned( r.cnt, 11 ) );
   debug(11          ) <= '0';
   debug(14 downto 12) <= std_logic_vector( to_unsigned( StateType'pos( r.state ), 3 ) );
   debug(15          ) <= '0';

   stats( 0) <= r.nMacDrp;
   stats( 1) <= r.nShtDrp;
   stats( 2) <= r.nArpHdr;
   stats( 3) <= r.nIP4Hdr;
   stats( 4) <= r.nUnkHdr;
   stats( 5) <= r.nArpDrp;
   stats( 6) <= r.nArpReq;
   stats( 7) <= r.nIP4Drp;
   stats( 8) <= r.nPinReq;
   stats( 9) <= r.nUdpReq;
   stats(10) <= r.nUnkIP4;
   stats(11) <= r.nIP4Mis;
   stats(12) <= r.nPinDrp;
   stats(13) <= r.nPinHdr;
   stats(14) <= r.nUdpMis;
   stats(15) <= r.nUdpHdr;
   stats(16) <= r.nPktFwd;

end architecture rtl;
