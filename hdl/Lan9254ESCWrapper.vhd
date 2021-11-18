library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.Lan9254Pkg.all;
use work.Lan9254ESCPkg.all;
use work.ESCMbxPkg.all;
use work.MicroUDPPkg.all;
use work.IPAddrConfigPkg.all;
use work.IlaWrappersPkg.all;
use work.Udp2BusPkg.all;
use work.Lan9254UdpBusPkg.all;

entity Lan9254ESCWrapper is
   generic (
      CLOCK_FREQ_G            : real;
      DISABLE_RXPDO_G         : boolean := false;
      DISABLE_TXPDO_G         : boolean := false;
      ENABLE_VOE_G            : boolean := false;
      ENABLE_EOE_G            : boolean := true;
      TXPDO_MAX_UPDATE_FREQ_G : real    := 5.0E3;
      REG_IO_TEST_ENABLE_G    : boolean := true;
      GEN_EOE_ILA_G           : boolean := true;
      NUM_EXT_HBI_MASTERS_G   : natural := 1;
      EXT_HBI_MASTERS_PRI_G   : integer := 0;
      NUM_BUS_SUBS_G          : natural range 0 to 4 := 0;
      NUM_BUS_MSTS_G          : natural := 0;
      DEFAULT_MAC_ADDR_G      : std_logic_vector(47 downto 0) := x"f106a98e0200";  -- 00:02:8e:a9:06:f1
      DEFAULT_IP4_ADDR_G      : std_logic_vector(31 downto 0) := x"0A0A0A0A";      -- 10.10.10.10
      DEFAULT_UDP_PORT_G      : std_logic_vector(15 downto 0) := x"0010";          -- 4096
      -- disable some things to just run the TXMBX test
      TXMBX_TEST_G            : boolean := false
   );
   port (

      clk                     : in  std_logic;
      rst                     : in  std_logic;

      -- HBI access output; connects to Lan9254 HBI
      req                     : out Lan9254ReqType;
      rep                     : in  Lan9254RepType    := LAN9254REP_INIT_C;

      -- interrupt from Lan9254
      irq                     : in  std_logic         := '1'; -- default to polled-mode

      -- TXPDO
      txPDOMst                : in  Lan9254PDOMstType := LAN9254PDO_MST_INIT_C;
      txPDORdy                : out std_logic;

      -- RXDO
      rxPDOMst                : out Lan9254PDOMstType := LAN9254PDO_MST_INIT_C;
      rxPDORdy                : in  std_logic         := '1';

      -- mac, ip and port in network-byte order!
      myAddr                  : in  IPAddrConfigType    := makeIpAddrConfig;
      myAddrAck               : out IPAddrConfigAckType := IP_ADDR_CONFIG_ACK_ASSERT_C;

      -- HBI access by an external agent
      extHBIReq               : in  Lan9254ReqArray(NUM_EXT_HBI_MASTERS_G - 1 + EXT_HBI_MASTERS_PRI_G downto EXT_HBI_MASTERS_PRI_G)  := (others => LAN9254REQ_INIT_C);
      extHBIRep               : out Lan9254RepArray(NUM_EXT_HBI_MASTERS_G - 1 + EXT_HBI_MASTERS_PRI_G downto EXT_HBI_MASTERS_PRI_G)  := (others => LAN9254REP_INIT_C);

      -- Register access via UDP
       -- external masters
      busMstReq               : in  Udp2BusReqArray(NUM_BUS_MSTS_G - 1 downto 0) := (others => UDP2BUSREQ_INIT_C);
      busMstRep               : out Udp2BusRepArray(NUM_BUS_MSTS_G - 1 downto 0) := (others => UDP2BUSREP_ERROR_C);
        -- external subordinates
      busSubReq               : out Udp2BusReqArray(NUM_BUS_SUBS_G - 1 downto 0) := (others => UDP2BUSREQ_INIT_C);
      busSubRep               : in  Udp2BusRepArray(NUM_BUS_SUBS_G - 1 downto 0) := (others => UDP2BUSREP_ERROR_C);


      -- debugging
      escState                : out ESCStateType;
      debug                   : out std_logic_vector(23 downto 0);

      stats                   : out StatCounterArray(21 downto 0) := (others => STAT_COUNTER_INIT_C);
      testFailed              : out std_logic_vector( 4 downto 0)
   );
end entity Lan9254ESCWrapper;

-- Top-level wrapper for ESC and helper/protocol modules.

architecture rtl of Lan9254ESCWrapper is

   function ite(c: boolean; a,b: natural) return natural is
   begin
      if ( c ) then return a; else return b; end if;
   end function ite;

   function ite(c: boolean; a,b: unsigned) return unsigned is
   begin
      if ( c ) then return a; else return b; end if;
   end function ite;


   constant NUM_MBX_ERRS_C    : natural := 1;

   constant NUM_RXMBX_PROTO_C : natural := 1;

   constant GEN_RXMBX_MUX_C   : boolean := ( NUM_RXMBX_PROTO_C > 1 );

   constant EOE_RX_STRM_IDX_C : natural := 0;

   constant NUM_TXMBX_PROTO_C : natural := 3;
   constant ERR_TX_STRM_IDX_C : natural := 0;
   constant EOE_RP_STRM_IDX_C : natural := 1;
   constant EOE_TX_STRM_IDX_C : natural := 2;

   constant NUM_HBI_MASTERS_C : natural := NUM_EXT_HBI_MASTERS_G + ite( ENABLE_EOE_G, 1, 0 );
   constant HBI_MASTERS_R_C   : integer := EXT_HBI_MASTERS_PRI_G;
   constant EXT_HBI_MST_L_C   : integer := NUM_EXT_HBI_MASTERS_G + HBI_MASTERS_R_C - 1;
   constant HBI_MASTERS_L_C   : integer := NUM_HBI_MASTERS_C + HBI_MASTERS_R_C - 1;

   constant NUM_ILAS_C        : natural := 3;

   constant NUM_ADDR_CFGS_C   : natural := 2;
   constant EXT_CFG_IDX_C     : natural := 0;
   constant EOE_CFG_IDX_C     : natural := 1;

   signal   txMbxMst          : Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
   signal   txMbxRdy          : std_logic;
   signal   rxMbxMst          : Lan9254StrmMstType;
   signal   rxMbxRdy          : std_logic          := '1';

   signal   errMst            : MbxErrorArray   (NUM_MBX_ERRS_C - 1 downto 0) := (others => MBX_ERROR_INIT_C );
   signal   errRdy            : std_logic_vector(NUM_MBX_ERRS_C - 1 downto 0) := (others => '1'              );

   signal   txStmMst          : Lan9254StrmMstArray(NUM_TXMBX_PROTO_C - 1 downto 0) := (others => LAN9254STRM_MST_INIT_C);
   signal   txStmRdy          : std_logic_vector(NUM_TXMBX_PROTO_C - 1 downto 0)    := (others => '1'                   );

   signal   rxStmMst          : Lan9254StrmMstArray(NUM_RXMBX_PROTO_C - 1 downto 0) := (others => LAN9254STRM_MST_INIT_C);
   signal   rxStmRdy          : std_logic_vector(NUM_RXMBX_PROTO_C - 1 downto 0)    := (others => '1'                   );

   signal   ilaTrg            : std_logic_vector(NUM_ILAS_C - 1 downto 0) := (others => '0');
   signal   ilaAck            : std_logic_vector(NUM_ILAS_C - 1 downto 0) := (others => '1');

   signal   reqLoc            : Lan9254ReqType;

   signal   locHBIReq         : Lan9254ReqArray(HBI_MASTERS_L_C downto HBI_MASTERS_R_C)  := (others => LAN9254REQ_INIT_C);
   signal   locHBIRep         : Lan9254RepArray(HBI_MASTERS_L_C downto HBI_MASTERS_R_C);

   signal   statsLoc          : StatCounterArray(stats'range) := (others => STAT_COUNTER_INIT_C);

   signal   myAddrLoc         : IPAddrConfigType              := myAddr;

begin

   locHBIReq(EXT_HBI_MST_L_C downto HBI_MASTERS_R_C) <= extHBIReq;
   extHBIRep                                         <= locHBIRep(EXT_HBI_MST_L_C downto HBI_MASTERS_R_C);

   U_ESC : entity work.Lan9254ESC
      generic map (
         CLK_FREQ_G              => CLOCK_FREQ_G,
         DISABLE_RXPDO_G         => DISABLE_RXPDO_G,
         DISABLE_TXPDO_G         => DISABLE_TXPDO_G,
         ENABLE_VOE_G            => ENABLE_VOE_G,
         ENABLE_EOE_G            => ENABLE_EOE_G,
         TXPDO_MAX_UPDATE_FREQ_G => TXPDO_MAX_UPDATE_FREQ_G,
         REG_IO_TEST_ENABLE_G    => REG_IO_TEST_ENABLE_G,
         NUM_EXT_HBI_MASTERS_G   => NUM_HBI_MASTERS_C,
         EXT_HBI_MASTERS_PRI_G   => EXT_HBI_MASTERS_PRI_G,
         TXMBX_TEST_G            => TXMBX_TEST_G
      )
      port map (
         clk         => clk,
         rst         => rst,

         req         => reqLoc,
         rep         => rep,

         irq         => irq,

         rxPDOMst    => rxPDOMst,
         rxPDORdy    => rxPDORdy,

         txPDOMst    => txPDOMst,
         txPDORdy    => txPDORdy,

         txMBXMst    => txMbxMst,
         txMBXRdy    => txMbxRdy,

         rxMBXMst    => rxMbxMst,
         rxMBXRdy    => rxMbxRdy,


         mbxErrMst   => errMst(0),
         mbxErrRdy   => errRdy(0),

         extHBIReq   => locHBIReq,
         extHBIRep   => locHBIRep,

         escState    => escState,
         debug       => debug(23 downto 0),

         testFailed  => testFailed,
         stats       => statsLoc(1 downto 0),

         ilaTrigOb   => ilaTrg(0),
         ilaTackOb   => ilaAck(0),

         ilaTrigIb   => ilaTrg(NUM_ILAS_C - 1),
         ilaTackIb   => ilaAck(NUM_ILAS_C - 1)
      );

      req <= reqLoc;

   -- Mailbox multiplexers

   U_TXMBX_MUX : entity work.ESCTxMbxMux
      generic map (
         NUM_STREAMS_G    => NUM_TXMBX_PROTO_C
      )
      port map (
         clk              => clk,
         rst              => rst,

         mbxIb            => txStmMst,
         rdyIb            => txStmRdy,

         mbxOb            => txMbxMst,
         rdyOb            => txMbxRdy
      );

   GEN_RXMBX_MUX : if ( GEN_RXMBX_MUX_C ) generate
   U_RXMBX_MUX : entity work.ESCRxMbxMux
      generic map (
         STREAM_CONFIG_G  => (EOE_RX_STRM_IDX_C => MBX_TYP_EOE_C)
      )
      port map (
         clk              => clk,
         rst              => rst,

         mbxIb            => rxMbxMst,
         rdyIb            => rxMbxRdy,

         mbxOb            => rxStmMst,
         rdyOb            => rxStmRdy
      );
   end generate GEN_RXMBX_MUX;

   GEN_NO_RXMBX_MUX : if ( not GEN_RXMBX_MUX_C ) generate
      rxStmMst(EOE_RX_STRM_IDX_C) <= rxMbxMst;
      rxMbxRdy                    <= rxStmRdy(EOE_RX_STRM_IDX_C);
   end generate GEN_NO_RXMBX_MUX;

   -- Error mailbox stream
   U_ERR : entity work.ESCTxMbxErr
      generic map (
         NUM_ERROR_SRCS_G => NUM_MBX_ERRS_C
      )
      port map (
         clk              => clk,
         rst              => rst,

         errIb            => errMst,
         rdyIb            => errRdy,

         mbxOb            => txStmMst(ERR_TX_STRM_IDX_C),
         rdyOb            => txStmRdy(ERR_TX_STRM_IDX_C)
      );

   GEN_EOE : if ( ENABLE_EOE_G ) generate

      type     StateType is ( IDLE, FWD_ICMP, FWD_UDP );

      type     RegType  is record
         state          : StateType;
      end record RegType;

      constant REG_INIT_C        : RegType := (
         state                 => IDLE
      );

      constant MAX_UDP_SIZE_C    : natural   :=
         EOE_MAX_FRAME_SIZE_C - MAC_HDR_SIZE_C - IP4_HDR_SIZE_C - UDP_HDR_SIZE_C;

      constant NUM_BUS_SUBS_C    : natural   := 8;
      constant NUM_BUS_MSTS_C    : natural   := NUM_BUS_MSTS_G + 1;

      constant UDP_IDX_ESC_C     : natural   := 7;
      constant UDP_IDX_LOC_C     : natural   := 6;

      signal   r                 : RegType   := REG_INIT_C;
      signal   rin               : RegType;

      signal   eoeMstOb          : Lan9254StrmMstType;
      signal   eoeRdyOb          : std_logic := '1';
      signal   eoeErrOb          : std_logic;
      signal   eoeMstIb          : Lan9254StrmMstType;
      signal   eoeRdyIb          : std_logic := '1';

      signal   ipPldRxMst        : Lan9254StrmMstType;
      signal   ipPldRxRdy        : std_logic := '0';

      signal   ipPldTxMst        : Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      signal   ipPldTxRdy        : std_logic;

      signal   txReq             : EthTxReqType := ETH_TX_REQ_INIT_C;
      signal   txRdy             : std_logic    := '0';

      signal   rxReq             : EthTxReqType := ETH_TX_REQ_INIT_C;
      signal   rxRdy             : std_logic    := '0';

      signal   probe0            : std_logic_vector(63 downto 0) := (others => '0');
      signal   probe1            : std_logic_vector(63 downto 0) := (others => '0');
      signal   probe2            : std_logic_vector(63 downto 0) := (others => '0');
      signal   probe3            : std_logic_vector(63 downto 0) := (others => '0');

      signal   eoeTxDbg          : std_logic_vector(31 downto 0);
      signal   eoeRxDbg          : std_logic_vector(15 downto 0);
      signal   uUDPDbg           : std_logic_vector(15 downto 0);

      signal   udpMuxState       : std_logic_vector( 1 downto 0);
      signal   udpMuxDebug       : std_logic_vector( 7 downto 0);

      -- UDP stream I/O
      signal   udpRxMst          : UdpStrmMstType := UDP_STRM_MST_INIT_C;
      signal   udpRxRdy          : std_logic      := '1';

      signal   udpTxMst          : UdpStrmMstType := UDP_STRM_MST_INIT_C;
      signal   udpTxRdy          : std_logic      := '1';

      signal   udpFrameSize      : unsigned(10 downto 0);

      signal   udp2BusReqIb      : Udp2BusReqArray(NUM_BUS_MSTS_C - 1 downto 0);
      signal   udp2BusRepIb      : Udp2BusRepArray(NUM_BUS_MSTS_C - 1 downto 0);

      signal   udp2BusReqOb      : Udp2BusReqArray(NUM_BUS_SUBS_C - 1 downto 0)         := (others => UDP2BUSREQ_INIT_C);
      signal   udp2BusRepOb      : Udp2BusRepArray(NUM_BUS_SUBS_C - 1 downto 0)         := (others => UDP2BUSREP_ERROR_C);

      signal   addrCfgs          : IPAddrConfigArray   (NUM_ADDR_CFGS_C - 1 downto 0);
      signal   addrCfgAcks       : IPAddrConfigAckArray(NUM_ADDR_CFGS_C - 1 downto 0);

   begin

      GEN_ILA : if ( GEN_EOE_ILA_G ) generate
         U_ILA : component Ila_256
            port map (
               clk          => clk,
               probe0       => probe0,
               probe1       => probe1,
               probe2       => probe2,
               probe3       => probe3,
               trig_out     => ilaTrg(1),
               trig_out_ack => ilaAck(1),
               trig_in      => ilaTrg(0),
               trig_in_ack  => ilaAck(0)
            );
      end generate GEN_ILA;

      GEN_NO_ILA : if ( not GEN_EOE_ILA_G ) generate
         ilaTrg(1) <= ilaTrg(0);
         ilaAck(0) <= ilaAck(1);
      end generate GEN_NO_ILA;

      probe0( 15 downto  0 ) <= rxStmMst(EOE_RX_STRM_IDX_C).data;
      probe0( 16           ) <= rxStmMst(EOE_RX_STRM_IDX_C).valid;
      probe0( 17           ) <= rxStmRdy(EOE_RX_STRM_IDX_C);
      probe0( 18           ) <= rxStmMst(EOE_RX_STRM_IDX_C).last;
      probe0( 19 downto 19 ) <= udpMuxState(0 downto 0);
      probe0( 20           ) <= rxMbxMst.valid;
      probe0( 21           ) <= rxMbxRdy;
      probe0( 23 downto 22 ) <= rxMbxMst.ben;
      probe0( 26 downto 24 ) <= uUDPDbg(14 downto 12);
      probe0( 30 downto 27 ) <= reqLoc.be;
      probe0( 31 downto 31 ) <= udpMuxState(1 downto 1);
      probe0( 47 downto 32 ) <= eoeMstOb.data;
      probe0( 48           ) <= eoeMstOb.valid;
      probe0( 49           ) <= eoeRdyOb;
      probe0( 50           ) <= eoeMstOb.last;
      probe0( 51           ) <= eoeErrOb;
      probe0( 53 downto 52 ) <= eoeMstOb.ben;
      probe0( 63 downto 54 ) <= uUDPDbg(9 downto 0);

      probe1( 15 downto  0 ) <= txStmMst(EOE_TX_STRM_IDX_C).data;
      probe1( 16           ) <= txStmMst(EOE_TX_STRM_IDX_C).valid;
      probe1( 17           ) <= txStmRdy(EOE_TX_STRM_IDX_C);
      probe1( 18           ) <= txStmMst(EOE_TX_STRM_IDX_C).last;
      probe1( 19 downto 19 ) <= (others => '0');
      probe1( 20           ) <= txMbxMst.valid;
      probe1( 21           ) <= txMbxRdy;
      probe1( 23 downto 22 ) <= txMbxMst.ben;
      probe1( 31 downto 24 ) <= (others => '0');
      probe1( 47 downto 32 ) <= eoeMstIb.data;
      probe1( 48           ) <= eoeMstIb.valid;
      probe1( 49           ) <= eoeRdyIb;
      probe1( 50           ) <= eoeMstIb.last;
      probe1( 51           ) <= reqLoc.valid;
      probe1( 53 downto 52 ) <= eoeMstIb.ben;
      probe1( 63 downto 54 ) <= std_logic_vector(reqLoc.addr(9 downto 0));

      probe2( 15 downto  0 ) <= std_logic_vector(rxReq.length);
      probe2( 16           ) <= rxReq.valid;
      probe2( 17           ) <= rxRdy;
      probe2( 19 downto 18 ) <= std_logic_vector(to_unsigned(EthPktType'pos(rxReq.typ), 2));
      probe2( 31 downto 20 ) <= rxReq.dstMac(47 downto 36);
      probe2( 47 downto 32 ) <= rxReq.protoData;
      probe2( 63 downto 48 ) <= eoeRxDbg;

      probe3( 15 downto  0 ) <= std_logic_vector(txReq.length);
      probe3( 16           ) <= txReq.valid;
      probe3( 17           ) <= txRdy;
      probe3( 19 downto 18 ) <= std_logic_vector(to_unsigned(EthPktType'pos(txReq.typ), 2));
      probe3( 31 downto 20 ) <= txReq.dstMac(47 downto 36);
      probe3( 63 downto 32 ) <= eoeTxDbg;

      U_EOE_RX: entity work.ESCEoERx
         generic map (
            CLOCK_FREQ_G     => CLOCK_FREQ_G,
            STORE_AND_FWD_G  => true
         )
         port map (
            clk         => clk,
            rst         => rst,

            mbxMstIb    => rxStmMst(EOE_RX_STRM_IDX_C),
            mbxRdyIb    => rxStmRdy(EOE_RX_STRM_IDX_C),

            mbxMstOb    => txStmMst(EOE_RP_STRM_IDX_C),
            mbxRdyOb    => txStmRdy(EOE_RP_STRM_IDX_C),

            eoeMstOb    => eoeMstOb,
            eoeRdyOb    => eoeRdyOb,
            eoeErrOb    => eoeErrOb,

            addrCfg     => addrCfgs   (EOE_CFG_IDX_C),
            addrCfgAck  => addrCfgAcks(EOE_CFG_IDX_C),

            debug       => eoeRxDbg,
            stats       => statsLoc(4 downto 2)
         );

      U_EOE_TX: entity work.ESCEoETx
         generic map (
            MAX_FRAGMENT_SIZE_G => to_integer(unsigned(ESC_SM1_LEN_C) - MBX_HDR_SIZE_C),
            STORE_AND_FWD_G     => false
         )
         port map (
            clk         => clk,
            rst         => rst,

            eoeMstIb    => eoeMstIb,
            eoeRdyIb    => eoeRdyIb,
            eoeFrameSz  => txReq.length(10 downto 0),

            mbxMstOb    => txStmMst(EOE_TX_STRM_IDX_C),
            mbxRdyOb    => txStmRdy(EOE_TX_STRM_IDX_C),

            debug       => eoeTxDbg
         );

      U_IP_RX : entity work.MicroUDPRx
         port map (
            clk              => clk,
            rst              => rst,

            myAddr           => myAddrLoc,

            mstIb            => eoeMstOb,
            errIb            => eoeErrOb,
            rdyIb            => eoeRdyOb,

            txReq            => rxReq,
            txRdy            => rxRdy,

            pldMstOb         => ipPldRxMst,
            pldRdyOb         => ipPldRxRdy,

            debug            => uUDPDbg,
            stats            => statsLoc(21 downto 5)
         );

      U_IP_TX : entity work.MicroUDPTx
         port map (
            clk              => clk,
            rst              => rst,

            myAddr           => myAddrLoc,

            mstOb            => eoeMstIb,
            rdyOb            => eoeRdyIb,

            txReq            => txReq,
            txRdy            => txRdy,

            pldMstIb         => ipPldTxMst,
            pldRdyIb         => ipPldTxRdy
         );

      addrCfgs( EXT_CFG_IDX_C ) <= myAddr;
      myAddrAck                 <= addrCfgAcks( EXT_CFG_IDX_C );

      U_GEN_ADDR : entity work.AddressGenerator
         generic map (
            DEFAULT_MAC_ADDR_G => DEFAULT_MAC_ADDR_G,
            DEFAULT_IP4_ADDR_G => DEFAULT_IP4_ADDR_G,
            DEFAULT_UDP_PORT_G => DEFAULT_UDP_PORT_G,
            NUM_CONFIGS_G      => addrCfgs'length
         )
         port map (
            clk              => clk,
            rst              => rst,

            configs          => addrCfgs,
            configAcks       => addrCfgAcks,

            addrOut          => myAddrLoc
         );

      -- for simulation/testing
      GEN_EOE_MON : if ( false ) generate
         P_MON_EOE : process ( clk ) is
         begin
            if ( rising_edge( clk ) ) then
               if ( ( eoeMstOb.valid and eoeRdyOb and '0' ) = '1' ) then
                  report  "EOE: " & toString(eoeMstOb.data)
                        & " L " & std_logic'image(eoeMstOb.last)
                        & " E " & std_logic'image(eoeErrOb);
               end if;
            end if;
         end process P_MON_EOE;
      end generate GEN_EOE_MON;

      U_UDP_ICMP_MUX : entity work.MicroUDPIPMux
         port map (
            clk               => clk,
            rst               => rst,

            ipRxMst           => ipPldRxMst,
            ipRxRdy           => ipPldRxRdy,
            ipRxReq           => rxReq,
            ipRxAck           => rxRdy,

            ipTxMst           => ipPldTxMst,
            ipTxRdy           => ipPldTxRdy,
            ipTxReq           => txReq,
            ipTxAck           => txRdy,

            udpRxMst          => udpRxMst,
            udpRxRdy          => udpRxRdy,

            udpTxMst          => udpTxMst,
            udpTxRdy          => udpTxRdy,

            debug             => udpMuxDebug
         );

      udpMuxState      <= udpMuxDebug(1 downto 0);

      udpTxMst.addr    <= udpRxMst.addr;

      udpTxMst.length  <= resize( udpFrameSize, udpTxMst.length'length ) + MAC_HDR_SIZE_C + IP4_HDR_SIZE_C + UDP_HDR_SIZE_C;

      -- external subordinates
      udp2BusRepOb(busSubRep'range)  <= busSubRep;
      busSubReq                      <= udp2BusReqOb( busSubReq'range );

      -- local subordinates
      udp2BusRepOb(UDP_IDX_ESC_C   ) <= to_Udp2BusRepType( locHBIRep(HBI_MASTERS_L_C)  );
      locHBIReq   (HBI_MASTERS_L_C ) <= to_Lan9254ReqType( udp2BusReqOb(UDP_IDX_ESC_C) );

      -- external masters
      udp2BusReqIb(NUM_BUS_MSTS_G - 1 downto 0) <= busMstReq;
      busMstRep                                 <= udp2BusRepIb(NUM_BUS_MSTS_G - 1 downto 0);

      U_BUS_MUX : entity work.Udp2BusMux
         generic map (
            NUM_SUBS_G        => NUM_BUS_SUBS_C,
            NUM_MSTS_G        => NUM_BUS_MSTS_C
         )
         port map (
            clk               => clk,
            rst               => rst,

            reqIb             => udp2BusReqIb,
            repIb             => udp2BusRepIb,

            reqOb             => udp2BusReqOb,
            repOb             => udp2BusRepOb
         );

      U_BUS_MST : entity work.Udp2Bus
         generic map (
            MAX_FRAME_SIZE_G  => MAX_UDP_SIZE_C
         )
         port map (
            clk               => clk,
            rst               => rst,

            req               => udp2BusReqIb(udp2BusReqIb'left),
            rep               => udp2BusRepIb(udp2BusRepIb'left),

            strmMstIb         => udpRxMst.strm,
            strmRdyIb         => udpRxRdy,

            strmMstOb         => udpTxMst.strm,
            strmRdyOb         => udpTxRdy,

            frameSize         => udpFrameSize,

            ilaTrgOb          => ilaTrg(2),
            ilaAckOb          => ilaAck(2),

            ilaTrgIb          => ilaTrg(1),
            ilaAckIb          => ilaAck(1)
         );

      P_LOC_STAT_REGS : process ( udp2BusReqOb( UDP_IDX_LOC_C ), statsLoc ) is
         variable idx : natural range 0 to 31;
      begin
         udp2BusRepOb( UDP_IDX_LOC_C ) <= UDP2BUSREP_ERROR_C;
         if ( ( udp2BusReqOb(UDP_IDX_LOC_C).valid and udp2BusReqOb(UDP_IDX_LOC_C).rdnwr ) = '1' ) then
            idx := to_integer( unsigned( udp2BusReqOb( UDP_IDX_LOC_C ).dwaddr(4 downto 0) ) );
            if ( idx <= statsLoc'high ) then
               udp2BusRepOb(UDP_IDX_LOC_C).rdata                        <= (others => '0');
               udp2BusRepOb(UDP_IDX_LOC_C).rdata( statsLoc(idx)'range ) <= std_logic_vector( statsLoc(idx) );
               udp2BusRepOb(UDP_IDX_LOC_C).berr                         <= '0';
            end if;
         end if;
      end process P_LOC_STAT_REGS;

   end generate GEN_EOE;

   NO_GEN_EOE : if ( not ENABLE_EOE_G ) generate

      txStmMst(EOE_TX_STRM_IDX_C) <= LAN9254STRM_MST_INIT_C;
      rxStmRdy(EOE_RX_STRM_IDX_C) <= '1';

   end generate;

   stats <= statsLoc;

end architecture rtl;
