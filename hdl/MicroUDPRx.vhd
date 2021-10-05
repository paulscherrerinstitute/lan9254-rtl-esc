library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Lan9254Pkg.all;
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
      pldRdyOb : in  std_logic := '1'

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
   end record RegType;

   constant REG_INIT_C : RegType := (
      state       => IDLE,
      cnt         => 0,
      txReq       => ETH_TX_REQ_INIT_C,
      rdy         => '1',
      maybeBcst   => false
   );

   procedure matchMac(
      constant d : in    std_logic_vector(15 downto 0);
      variable v : inout RegType;
      variable r : out   boolean
   ) is
   begin
      if ( d = x"ffff" and ( ( v.cnt = 0 ) or v.maybeBcst ) ) then
         r           := true;
         v.maybeBcst := true;
      else
         case ( v.cnt ) is
            when 0 =>  r := ( d = myMac( 15 + 0*16 downto  0*16 ) );
            when 1 =>  r := ( d = myMac( 15 + 1*16 downto  1*16 ) );
            when 2 =>  r := ( d = myMac( 15 + 2*16 downto  2*16 ) );
            when others => r:= false;
         end case;
      end if;
   end procedure matchMac;

   procedure resetState(
      variable v : inout RegType
   ) is
   begin
      v.cnt       := 0;
      v.state     := IDLE;
      v.rdy       := '1';
      v.maybeBcst := false;
   end procedure resetState;


   signal    r    : RegType := REG_INIT_C;
   signal    rin  : RegType;

begin

   P_COMB : process (r, myMac, myIp, myPort, mstIb, txRdy, pldRdyOb) is
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
                  v.state := DROP;
               else
                  v.cnt   := r.cnt + 1;
                  v.state := MAC_HDR;
               end if;
            end if;
                  
         when MAC_HDR  =>

            if ( errIb = '1' ) then
               v.state := DROP;
            elsif ( mstIb.valid = '1' ) then
               if ( mstIb.last  = '1' ) then
                  v.state := DROP;
               else
                  if ( r.cnt < 3 ) then
                     matchMac( mstIb.data, v, ok );
                     if ( not ok ) then
                        v.state := DROP;
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
                          elsif ( mstIb.data = x"0008" ) then
                             v.state := IP_HDR;
                          else
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
               if ( mstIb.last  = '1' and ( r.cnt < IP4_HDR_SIZE_C ) ) then
report "ARP_REQ early last drop";
                  v.state := DROP;
               else
                  v.cnt := r.cnt + 1; -- resetState manipulates v.cnt; increment first
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
                           v.txReq.typ   := ARP_REP;
                           v.txReq.valid := '1';
report "ARP_REQ OK, L " & std_logic'image(mstIb.last);
                           if ( mstIb.last = '1' ) then
                              resetState( v );
                           else
                              v.state := DROP;
                           end if;
                        end if;
if ( v.state = DROP ) then
report "ARP_REQ drop @" & integer'image(r.cnt);
end if;
                  end case;
               end if;
            end if;

         when IP_HDR =>
            if ( errIb = '1' ) then
               v.state := DROP;
            elsif ( mstIb.valid = '1' ) then
               if ( ( mstIb.last  = '1' ) and ( r.cnt < 17 ) ) then
report "IP_HDR early last drop";
                  v.state := DROP;
               else
                  v.cnt := r.cnt + 1;
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
                             v.state := DROP;
                       end case;
                    when 12    => -- ignore checksum
                    when 13    =>
                       v.txReq.dstIp(15 downto  0) := mstIb.data;
                    when 14    =>
                       v.txReq.dstIp(31 downto 16) := mstIb.data;
                    when 15    =>
                       if ( myIp( 15 downto  0 ) /= mstIb.data ) then
                          v.state := DROP;
                       end if;
                    when others  =>
                       if ( myIp( 31 downto 16 ) /= mstIb.data ) then
                          v.state := DROP;
                       else
                          if ( r.txReq.typ = PING_REP ) then
                             v.state := ICMP_REQ;
report "IP HDR PASSED => ICMP";
                          else
report "IP HDR PASSED => UDP";
                             v.state := UDP;
                          end if;
                       end if;
                  end case;
               end if;
            end if;
if ( v.state = DROP ) then
report "IP_HDR drop @" & integer'image(r.cnt) & " " & toString(mstIb.data);
end if;

         when ICMP_REQ =>
            if ( errIb = '1' ) then
               v.state := DROP;
            elsif ( mstIb.valid = '1' ) then
               if ( mstIb.last  = '1' and ( r.cnt < 19 ) ) then
                 v.state := DROP;
               else
                  v.cnt := r.cnt + 1;
                  case ( r.cnt ) is
                     when     17 =>
                        if ( mstIb.data /= x"0008" ) then
                           v.state := DROP;
                        end if;
                     when others =>
                        v.state           := FWD;
                        v.txReq.valid     := '1';
                        -- record checksum; sender may adjust
                        v.txReq.protoData := mstIb.data;
                  end case;
               end if;
            end if;

         when UDP =>
            if ( errIb = '1' ) then
               v.state := DROP;
            elsif ( mstIb.valid = '1' ) then
               if ( mstIb.last  = '1' and ( r.cnt < 21 ) ) then
                 v.state := DROP;
               else
                  v.cnt := r.cnt + 1;
                  case ( r.cnt ) is
                     when 17 =>
                        v.txReq.protoData := mstIb.data;
                     when 18 =>
                        if ( mstIb.data /= myPort ) then
                           v.state := DROP;
                           -- should really send ICMP message
                        end if;
                     when 19 =>
                     when others =>
                        v.state       := FWD;
                        v.txReq.valid := '1';
                  end case;
               end if;
            end if;

         when DROP =>
            if ( ( ( mstIb.valid and mstIb.last ) or errIb ) = '1' ) then
               resetState( v );
            end if;

         when FWD =>
            rdyIb    <= pldRdyOb; 
            m.valid  := mstIb.valid;
            if ( ( (pldRdyOb and mstIb.valid and mstIb.last) or errIb ) = '1' ) then
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

end architecture rtl;
