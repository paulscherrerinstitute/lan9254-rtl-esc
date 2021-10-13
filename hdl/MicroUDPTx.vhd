library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Lan9254Pkg.all;
use     work.MicroUDPPkg.all;
use     work.ESCMbxPkg.all;

entity MicroUdpTx is
   port (
      clk      : in  std_logic;
      rst      : in  std_logic;

      myMac    : in  std_logic_vector(47 downto 0) := x"f106a98e0200";
      myIp     : in  std_logic_vector(31 downto 0) := x"0a0a0a0a";
      myPort   : in  std_logic_vector(15 downto 0) := x"6688";

      mstOb    : out Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      rdyOb    : in  std_logic;

      txReq    : in  EthTxReqType       := ETH_TX_REQ_INIT_C;
      txRdy    : out std_logic;

      pldMstIb : in  Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      pldRdyIb : out std_logic := '1'

   );
end entity MicroUdpTx;

architecture rtl of MicroUdpTx is

   type StateType is (IDLE, MAC_HDR, IP_HDR, ARP_REP, ICMP_REP, UDP, FWD);

   type RegType   is record
      state       : StateType;
      cnt         : natural range 0 to 1500;
      txRdy       : std_logic;
      mstOb       : Lan9254StrmMstType;
      hdrCsumRst  : std_logic;
   end record RegType;

   -- use defaults but assert BEN and set EOE type
   function resetStreamMaster return Lan9254StrmMstType is
      variable v : Lan9254StrmMstType;
   begin
      v                 := LAN9254STRM_MST_INIT_C;
      v.ben             := "11";
      v.last            := '0';
      v.valid           := '0';
      v.usr(3 downto 0) := MBX_TYP_EOE_C;
      return v;
   end function resetStreamMaster;

   constant REG_INIT_C : RegType := (
      state       => IDLE,
      cnt         => 0,
      txRdy       => '0',
      mstOb       => resetStreamMaster,
      hdrCsumRst  => '1'
   );

   function bswap(constant x : unsigned(15 downto 0)) return std_logic_vector is
      variable v : std_logic_vector(15 downto 0);
   begin
      v( 15 downto 8 ) := std_logic_vector( x(  7 downto 0 ) );
      v(  7 downto 0 ) := std_logic_vector( x( 15 downto 8 ) );
      return v;
   end function bswap;

   procedure resetState(
      variable v : inout RegType
   ) is
   begin
      v                       := v;
      v.cnt                   := 0;
      v.state                 := IDLE;
      v.mstOb.ben             := "11";
      v.mstOb.last            := '0';
      v.mstOb.valid           := '0';
      v.mstOb.usr(3 downto 0) := MBX_TYP_EOE_C;
      v.cnt                   :=  0;
      v.txRdy                 := '0';
      v.hdrCsumRst            := '1';
   end procedure resetState;


   signal    r                : RegType := REG_INIT_C;
   signal    rin              : RegType;

   signal    v4HdrCsum        : std_logic_vector(15 downto 0);
   signal    v4HdrCsumMux     : std_logic_vector(15 downto 0);

begin

   P_COMB : process (r, myMac, myIp, myPort, rdyOb, txReq, pldMstIb, v4HdrCsum) is
      variable v  : RegType;
   begin
      v            := r;
      mstOb        <= r.mstOb;

      v4HdrCsumMux <= (others => '0');
      pldRdyIb     <= '0';

      v.txRdy      := '0';

      case ( r.state ) is
         when IDLE =>

            if ( txReq.valid = '1' ) then
               v.mstOb.data  := txReq.dstMac(15 downto 0);
               v.mstOb.valid := '1';
               v.state       := MAC_HDR;
               v.cnt         := r.cnt + 1;
               v.hdrCsumRst  := '0';
            end if;

         when MAC_HDR  =>
            if ( rdyOb = '1' ) then
               v.cnt := r.cnt + 1;
               case ( r.cnt ) is
                  when 1 => v.mstOb.data := txReq.dstMac(15 + 1*16 downto 1*16);
                            if ( txReq.typ = PING_REP ) then
                               v4HdrCsumMux <= x"0185";
                            else
                               v4HdrCsumMux <= x"1185";
                            end if;
                  when 2 => v.mstOb.data := txReq.dstMac(15 + 2*16 downto 2*16);
                            v4HdrCsumMux <= myIp(15 downto  0);
                  when 3 => v.mstOb.data := myMac       (15 + 0*16 downto 0*16);
                            v4HdrCsumMux <= myIp(31 downto 16);
                  when 4 => v.mstOb.data := myMac       (15 + 1*16 downto 1*16);
                            v4HdrCsumMux <= txReq.dstIp(15 downto  0);
                  when 5 => v.mstOb.data := myMac       (15 + 2*16 downto 2*16);
                            v4HdrCsumMux <= txReq.dstIp(31 downto 16);
                  when others =>
                    if ( txReq.typ = ARP_REP ) then
                       v.mstOb.data := x"0608";
                       v.state      := ARP_REP;
                    else
                       v.mstOb.data := x"0008";
                       v.state      := IP_HDR;
                    end if;
               end case;
            end if;

          when ARP_REP =>
            if ( rdyOb = '1' ) then
               v.cnt := r.cnt + 1;
               case ( r.cnt ) is
                  when  7 =>     v.mstOb.data := x"0100";
                  when  8 =>     v.mstOb.data := x"0008";
                  when  9 =>     v.mstOb.data := x"0406";
                  when 10 =>     v.mstOb.data := x"0200";
                  when 11 =>     v.mstOb.data := myMac(15 + 0*16 downto 0*16);
                  when 12 =>     v.mstOb.data := myMac(15 + 1*16 downto 1*16);
                  when 13 =>     v.mstOb.data := myMac(15 + 2*16 downto 2*16);
                  when 14 =>     v.mstOb.data := myIp (15 + 0*16 downto 0*16);
                  when 15 =>     v.mstOb.data := myIp (15 + 1*16 downto 1*16);
                  when 16 =>     v.mstOb.data := txReq.dstMac(15 + 0*16 downto 0*16);
                  when 17 =>     v.mstOb.data := txReq.dstMac(15 + 1*16 downto 1*16);
                  when 18 =>     v.mstOb.data := txReq.dstMac(15 + 2*16 downto 2*16);
                  when 19 =>     v.mstOb.data := txReq.dstIp (15 + 0*16 downto 0*16);
                  when 20 =>     v.mstOb.data := txReq.dstIp (15 + 1*16 downto 1*16);
                                 v.mstOb.last := '1';
                                 v.txRdy      := '1';
                  when others =>
report "Sent ARP REP";
                     resetState( v );
               end case;
            end if;

         when IP_HDR =>
            if ( rdyOb = '1' ) then
               v.cnt := r.cnt + 1;
               case ( r.cnt ) is
                  when  7 =>      v.mstOb.data := x"0045";
                  when  8 =>      v.mstOb.data := bswap(txReq.length - MAC_HDR_SIZE_C);
                                  v4HdrCsumMux <= v.mstOb.data;
                  when  9 | 10 => v.mstOb.data := x"0000"; -- id, flags, frag. offset
                  when 11 =>      if ( txReq.typ = PING_REP ) then
                                     v.mstOb.data := x"0140"; -- proto/TTL
                                  else
                                     v.mstOb.data := x"1140"; -- proto/TTL
                                  end if;
                                  -- checksum carry mop-up cycle
                  when 12 =>      v.mstOb.data := not v4HdrCsum;
                                  v.hdrCsumRst := '1'; -- reset checksum calculator for ICMP
                  when 13 =>      v.mstOb.data := myIp(15 downto  0);
                                  v.hdrCsumRst := '0';
                  when 14 =>      v.mstOb.data := myIp(31 downto 16);
                  when 15 =>      v.mstOb.data := txReq.dstIp(15 downto  0);
                                  v4HdrCsumMux <= not txReq.protoData;
                  when others =>  v.mstOb.data := txReq.dstIp(31 downto 16);
                    if ( txReq.typ = PING_REP ) then
                       v4HdrCsumMux <= x"fff7"; -- subtract 0x0008 (reply-type - request-type) in one's complement arith.
                       v.state      := ICMP_REP;
                    else
                       v.state      := UDP;
                    end if;
               end case;
            end if;

         when ICMP_REP =>
            if ( rdyOb = '1' ) then
               v.cnt := r.cnt + 1;
               case ( r.cnt ) is
                  when 17 => v.mstOb.data := x"0000"; -- echo reply
                             -- checksum carry mop-up cycle
                  when 18 =>
                             v.mstOb.data := not v4HdrCsum;
                             v.txRdy      := '1';
                  when others =>
                             v.state      := FWD;
               end case;
            end if;

         when UDP =>
            if ( rdyOb = '1' ) then
               v.cnt := r.cnt + 1;
               case ( r.cnt ) is
                  when 17 => v.mstOb.data := myPort;
                  when 18 => v.mstOb.data := txReq.protoData;
                  when 19 => v.mstOb.data := bswap(txReq.length - MAC_HDR_SIZE_C - IP4_HDR_SIZE_C);
                  when 20 => v.mstOb.data := x"0000"; -- no checksum
                             v.txRdy      := '1';
                  when others =>
                             v.state      := FWD;
               end case;
            end if;

         when FWD =>
            mstOb    <= pldMstIb;
            pldRdyIb <= rdyOb;
            if ( ( rdyOb and pldMstIb.valid and pldMstIb.last ) = '1' ) then
               resetState( v );
            end if;

      end case;

      rin <= v;
   end process P_COMB;

   txRdy <= r.txRdy;

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

   U_IPHDR_CHKSUM : entity work.IPV4ChkSum
      generic map (
         RESET_VAL_G => x"0000",
         BYTE_SWAP_G => true
      )
      port map (
         clk         => clk,
         rst         => r.hdrCsumRst,
         data        => v4HdrCsumMux,
         chkSum      => v4HdrCsum
      );

end architecture rtl;
