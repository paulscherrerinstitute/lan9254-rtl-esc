library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.Lan9254Pkg.all;
use work.Lan9254ESCPkg.all;
use work.ESCMbxPkg.all;
use work.MicroUDPPkg.all;
use work.IlaWrappersPkg.all;

entity Lan9254ESCWrapper is
   generic (
      CLOCK_FREQ_G            : real;
      DISABLE_RXPDO_G         : boolean := false;
      ENABLE_VOE_G            : boolean := false;
      ENABLE_EOE_G            : boolean := true;
      TXPDO_MAX_UPDATE_FREQ_G : real    := 5.0E3;
      REG_IO_TEST_ENABLE_G    : boolean := true;
      GEN_EOE_ILA_G           : boolean := true;
      -- disable some things to just run the TXMBX test
      TXMBX_TEST_G            : boolean := false
   );
   port (

      clk                     : in  std_logic;
      rst                     : in  std_logic;

      req                     : out Lan9254ReqType;
      rep                     : in  Lan9254RepType    := LAN9254REP_INIT_C;

      txPDOMst                : in  Lan9254PDOMstType := LAN9254PDO_MST_INIT_C;
      txPDORdy                : out std_logic;

      rxPDOMst                : out Lan9254PDOMstType := LAN9254PDO_MST_INIT_C;
      rxPDORdy                : in  std_logic         := '1';

      irq                     : in  std_logic         := '1'; -- default to polled-mode

      -- mac, ip and port in network-byte order!
      myMac                   : in  std_logic_vector(47 downto 0) := x"f106a98e0200";
      myIp                    : in  std_logic_vector(31 downto 0) := x"0a0a0a0a";
      myPort                  : in  std_logic_vector(15 downto 0) := x"6688";

      rxUDPHdr                : out EthTxReqType := ETH_TX_REQ_INIT_C;
      rxUDPHdrAck             : in  std_logic    := '1';
      rxUDPMst                : out Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      rxUDPRdy                : in  std_logic    := '1';

      txUDPHdr                : in  EthTxReqType := ETH_TX_REQ_INIT_C;
      txUDPHdrAck             : out std_logic    := '1';
      txUDPMst                : in  Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      txUDPRdy                : out std_logic    := '1';

      escState                : out ESCStateType;
      debug                   : out std_logic_vector(23 downto 0);

      testFailed              : out std_logic_vector(4 downto 0)
   );
end entity Lan9254ESCWrapper;

-- Top-level wrapper for ESC and helper/protocol modules.

architecture rtl of Lan9254ESCWrapper is

   function ite(c: boolean; a,b: natural) return natural is
   begin
      if ( c ) then return a; else return b; end if;
   end function ite;

   constant NUM_MBX_ERRS_C    : natural := 1;

   constant NUM_MBX_ERRS_C    : natural := 1;

   constant NUM_RXMBX_PROTO_C : natural := 1;

   constant GEN_RXMBX_MUX_C   : boolean := ( NUM_RXMBX_PROTO_C > 1 );

   constant EOE_RX_STRM_IDX_C : natural := 0;

   constant NUM_TXMBX_PROTO_C : natural := 2;
   constant EOE_TX_STRM_IDX_C : natural := 0;
   constant ERR_TX_STRM_IDX_C : natural := 1;


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

begin

   U_ESC : entity work.Lan9254ESC
      generic map (
         CLK_FREQ_G              => CLOCK_FREQ_G,
         DISABLE_RXPDO_G         => DISABLE_RXPDO_G,
         ENABLE_VOE_G            => ENABLE_VOE_G,
         ENABLE_EOE_G            => ENABLE_EOE_G,
         TXPDO_MAX_UPDATE_FREQ_G => TXPDO_MAX_UPDATE_FREQ_G,
         REG_IO_TEST_ENABLE_G    => REG_IO_TEST_ENABLE_G,
         TXMBX_TEST_G            => TXMBX_TEST_G
      )
      port map (
         clk         => clk,
         rst         => rst,

         req         => req,
         rep         => rep,

         rxPDOMst    => rxPDOMst,
         rxPDORdy    => rxPDORdy,

         txPDOMst    => txPDOMst,
         txPDORdy    => txPDORdy,

         txMBXMst    => txMbxMst,
         txMBXRdy    => txMbxRdy,

         rxMBXMst    => rxMBXMst,
         rxMBXRdy    => rxMBXRdy,

     
         mbxErrMst   => errMst(0),
         mbxErrRdy   => errRdy(0),

         irq         => irq,

         escState    => escState,
         debug       => debug(23 downto 0),

         testFailed  => testFailed
      );

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

      constant REG_INIT_C      : RegType := (
         state                 => IDLE
      );

      signal   r               : RegType   := REG_INIT_C;
      signal   rin             : RegType;

      signal   eoeMstOb        : Lan9254StrmMstType;
      signal   eoeRdyOb        : std_logic := '1';
      signal   eoeErrOb        : std_logic;
      signal   eoeMstIb        : Lan9254StrmMstType;
      signal   eoeRdyIb        : std_logic := '1';

      signal   ipPldRxMst      : Lan9254StrmMstType;
      signal   ipPldRxRdy      : std_logic := '0';

      signal   ipPldTxMst      : Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      signal   ipPldTxRdy      : std_logic;

      signal   txReq           : EthTxReqType := ETH_TX_REQ_INIT_C;
      signal   txRdy           : std_logic    := '0';

      signal   rxReq           : EthTxReqType := ETH_TX_REQ_INIT_C;
      signal   rxRdy           : std_logic    := '0';

      signal   probe0          : std_logic_vector(63 downto 0) := (others => '0');
      signal   probe1          : std_logic_vector(63 downto 0) := (others => '0');
      signal   probe2          : std_logic_vector(63 downto 0) := (others => '0');
      signal   probe3          : std_logic_vector(63 downto 0) := (others => '0');

   begin

      GEN_ILA : if ( GEN_EOE_ILA_G ) generate
         U_ILA : component Ila_256
            port map (
               clk      => clk,
               probe0   => probe0,
               probe1   => probe1,
               probe2   => probe2,
               probe3   => probe3
            );
      end generate GEN_ILA;

      probe0( 15 downto  0 ) <= rxStmMst(EOE_RX_STRM_IDX_C).data;
      probe0( 16           ) <= rxStmMst(EOE_RX_STRM_IDX_C).valid;
      probe0( 17           ) <= rxStmRdy(EOE_RX_STRM_IDX_C);
      probe0( 18           ) <= rxStmMst(EOE_RX_STRM_IDX_C).last;
      probe0( 31 downto 19 ) <= (others => '0');
      probe0( 47 downto 32 ) <= eoeMstOb.data;
      probe0( 48           ) <= eoeMstOb.valid;
      probe0( 49           ) <= eoeRdyOb;
      probe0( 50           ) <= eoeMstOb.last;
      probe0( 51           ) <= eoeErrOb;
      probe0( 63 downto 52 ) <= (others => '0');

      probe1( 15 downto  0 ) <= txStmMst(EOE_RX_STRM_IDX_C).data;
      probe1( 16           ) <= txStmMst(EOE_RX_STRM_IDX_C).valid;
      probe1( 17           ) <= txStmRdy(EOE_RX_STRM_IDX_C);
      probe1( 18           ) <= txStmMst(EOE_RX_STRM_IDX_C).last;
      probe1( 31 downto 19 ) <= (others => '0');
      probe1( 47 downto 32 ) <= eoeMstIb.data;
      probe1( 48           ) <= eoeMstIb.valid;
      probe1( 49           ) <= eoeRdyIb;
      probe1( 50           ) <= eoeMstIb.last;
      probe1( 51           ) <= '0';
      probe1( 63 downto 52 ) <= (others => '0');

      probe2( 15 downto  0 ) <= std_logic_vector(rxReq.length);
      probe2( 16           ) <= rxReq.valid;
      probe2( 17           ) <= rxRdy;
      probe2( 19 downto 18 ) <= std_logic_vector(to_unsigned(EthPktType'pos(rxReq.typ), 2));
      probe2( 31 downto 20 ) <= rxReq.dstMac(47 downto 36);
      probe2( 47 downto 32 ) <= rxReq.protoData;
      probe2( 63 downto 48 ) <= rxReq.dstIp(31 downto 16);

      probe3( 15 downto  0 ) <= std_logic_vector(txReq.length);
      probe3( 16           ) <= txReq.valid;
      probe3( 17           ) <= txRdy;
      probe3( 19 downto 18 ) <= std_logic_vector(to_unsigned(EthPktType'pos(txReq.typ), 2));
      probe3( 31 downto 20 ) <= txReq.dstMac(47 downto 36);
      probe3( 47 downto 32 ) <= txReq.protoData;
      probe3( 63 downto 48 ) <= txReq.dstIp(31 downto 16);

      U_EOE_RX: entity work.ESCEoERx
         generic map (
            CLOCK_FREQ_G     => CLOCK_FREQ_G
         )
         port map (
            clk         => clk,
            rst         => rst,
   
            mbxMstIb    => rxStmMst(EOE_RX_STRM_IDX_C),
            mbxRdyIb    => rxStmRdy(EOE_RX_STRM_IDX_C),
   
   
            eoeMstOb    => eoeMstOb,
            eoeRdyOb    => eoeRdyOb,
            eoeErrOb    => eoeErrOb
         );

      U_EOE_TX: entity work.ESCEoETx
         generic map (
            MAX_FRAGMENT_SIZE_G => to_integer(unsigned(ESC_SM1_LEN_C) - MBX_HDR_SIZE_C),
            STORE_AND_FWD_G     => true
         )
         port map (
            clk         => clk,
            rst         => rst,
   
            eoeMstIb    => eoeMstIb,
            eoeRdyIb    => eoeRdyIb,
            eoeFrameSz  => txReq.length(10 downto 0),
   
            mbxMstOb    => txStmMst(EOE_TX_STRM_IDX_C),
            mbxRdyOb    => txStmRdy(EOE_TX_STRM_IDX_C)
         );
   
      U_IP_RX : entity work.MicroUDPRx
         port map (
            clk              => clk,
            rst              => rst,

            myMac            => myMac,
            myIp             => myIp,
            myPort           => myPort,
   
            mstIb            => eoeMstOb,
            errIb            => eoeErrOb,
            rdyIb            => eoeRdyOb,
   
            txReq            => rxReq,
            txRdy            => rxRdy,
   
            pldMstOb         => ipPldRxMst,
            pldRdyOb         => ipPldRxRdy
         );
   
      U_IP_TX : entity work.MicroUDPTx
         port map (
            clk              => clk,
            rst              => rst,

            myMac            => myMac,
            myIp             => myIp,
            myPort           => myPort,
    
            mstOb            => eoeMstIb,
            rdyOb            => eoeRdyIb,
   
            txReq            => txReq,
            txRdy            => txRdy,
   
            pldMstIb         => ipPldTxMst,
            pldRdyIb         => ipPldTxRdy
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


      -- FIXME: must mux/splice UDP in
      ipPldTxMst <= ipPldRxMst;
      ipPldRxRdy <= ipPldTxRdy;

      txReq      <= rxReq;
      rxRdy      <= txRdy;

   end generate GEN_EOE;

   NO_GEN_EOE : if ( not ENABLE_EOE_G ) generate

      txStmMst(EOE_TX_STRM_IDX_C) <= LAN9254STRM_MST_INIT_C;
      rxStmRdy(EOE_RX_STRM_IDX_C) <= '1';

   end generate;

end architecture rtl;
