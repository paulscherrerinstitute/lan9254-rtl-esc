library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.Lan9254Pkg.all;
use work.Lan9254ESCPkg.all;
use work.ESCMbxPkg.all;
use work.MicroUDPPkg.all;

entity Lan9254ESCrun is
end entity Lan9254ESCrun;

-- Simulation environment for Lan9254ESC. Run a simulation
-- of the ESC and let it talk to real LAN9254 hardware (e.g.
-- from a ZYNQ CPU).

architecture rtl of Lan9254ESCrun is

   constant NUM_ERRS_C        : natural := 1;

   constant NUM_TXMBX_PROTO_C : natural := 2;
   constant NUM_RXMBX_PROTO_C : natural := 1;

   constant EOE_RX_STRM_IDX_C : natural := 0;

   signal clk      : std_logic := '0';
   signal rst      : std_logic := '0';
   signal run      : boolean   := true;

   signal req      : Lan9254ReqType := LAN9254REQ_INIT_C;
   signal rep      : Lan9254RepType := LAN9254REP_INIT_C;

   signal al       : std_logic_vector(31 downto 0) := x"0000_0002";
   signal as       : std_logic_vector(31 downto 0) := x"0000_0001";

   signal cnt      : integer := 0;

   signal rxPDOMst : Lan9254PDOMstType;
   signal rxPDORdy : std_logic;

   signal eoeMstOb : Lan9254StrmMstType;
   signal eoeRdyOb : std_logic := '1';
   signal eoeErrOb : std_logic;
   signal eoeMstIb : Lan9254StrmMstType;
   signal eoeRdyIb : std_logic := '1';

   signal txPDOMst : Lan9254PDOMstType := LAN9254PDO_MST_INIT_C;
   signal txPDORdy : std_logic;

   signal txStmMst : Lan9254StrmMstArray(NUM_TXMBX_PROTO_C - 1 downto 0) := (others => LAN9254STRM_MST_INIT_C);
   signal txStmRdy : std_logic_vector(NUM_TXMBX_PROTO_C - 1 downto 0);

   signal rxStmMst : Lan9254StrmMstArray(NUM_RXMBX_PROTO_C - 1 downto 0) := (others => LAN9254STRM_MST_INIT_C);
   signal rxStmRdy : std_logic_vector(NUM_RXMBX_PROTO_C - 1 downto 0)    := (others => '1');

   signal decim    : natural := 1000;

   signal irq      : std_logic := not EC_IRQ_ACT_C;

   signal rstDrv   : std_logic := '1';

   function pollIRQ_C return integer;

   attribute foreign of pollIRQ_C : function is "VHPIDIRECT pollIRQ_C";

   function pollIRQ_C return integer is
   begin
      assert false report "pollIRQ_C should be foreign" severity failure;
   end function pollIRQ_C;

   signal   errMst          : MbxErrorArray   (NUM_ERRS_C - 1 downto 0) := (others => MBX_ERROR_INIT_C );
   signal   errRdy          : std_logic_vector(NUM_ERRS_C - 1 downto 0);

   signal   txMbxMst        : Lan9254StrmMstType;
   signal   txMbxRdy        : std_logic;
   signal   rxMbxMst        : Lan9254StrmMstType;
   signal   rxMbxRdy        : std_logic;
   signal   ipPldMst        : Lan9254StrmMstType;
   signal   ipPldRdy        : std_logic;

   signal   txReq           : EthTxReqType;
   signal   txRdy           : std_logic;

begin

   process is begin
      if ( run ) then
         wait for 10 us;
         clk <= not clk;
      else
         wait;
      end if;
   end process;

   txPDOMst.ben   <= "11";

   process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rstDrv = '1' ) then
            txPDOMst.wrdAddr <= (others => '0');
            decim            <= 0;
            txPDOMst.valid   <= '0';
            rstDrv           <= '0';
         else
            if ( txPDOMst.valid = '0' ) then
               if ( decim = 0 ) then
                  txPDOMst.valid   <= '1';
                  decim            <= 1000;
               else
                  decim <= decim - 1;
               end if;
            elsif ( txPDORdy = '1' ) then
               cnt              <= cnt + 1;
               txPDOMst.wrdAddr <= txPDOMst.wrdAddr + 1;
               if ( txPDOMst.wrdAddr >= SM3_WADDR_END_C ) then
                  txPDOMst.wrdAddr <= (others => '0');
                  txPDOMst.valid   <= '0';
               end if;
            end if;
         end if;
      end if;
   end process;

   process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         -- just reflect the level here; we don't know
         -- which one is active...
         if ( pollIRQ_C /= 0 ) then
            irq <= '1';
         else
            irq <= '0';
         end if;
      end if;
   end process;

   txPDOMst.data <= std_logic_vector(to_unsigned(cnt, txPDOMst.data'length));

   U_DUT : entity work.Lan9254ESC
      generic map (
         CLK_FREQ_G  => 10.0E4,
         ENABLE_EOE_G => true
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

         irq         => irq
      );

   U_HBI : entity work.Lan9254Hbi
      generic map (
         CLOCK_FREQ_G => 12.0E6
      )
      port map (
         clk         => clk,
         rst         => rst,
         req         => req,
         rep         => rep
      );

   U_RXPDO : entity work.RxPDOSoft
      port map (
         clk         => clk,
         rst         => rst,

         rxPdoMst    => rxPDOMst,
         rxPdoRdy    => rxPDORdy

      );

   U_EOE_RX: entity work.ESCEoERx
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

         mbxMstOb    => txStmMst(1),
         mbxRdyOb    => txStmRdy(1)
      );

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


   U_ERR : entity work.ESCTxMbxErr
      generic map (
         NUM_ERROR_SRCS_G => NUM_ERRS_C
      )
      port map (
         clk              => clk,
         rst              => rst,

         errIb            => errMst,
         rdyIb            => errRdy,

         mbxOb            => txStmMst(0),
         rdyOb            => txStmRdy(0)
      );

   U_IP_RX : entity work.MicroUDPRx
      port map (
         clk              => clk,
         rst              => rst,

         mstIb            => eoeMstOb,
         errIb            => eoeErrOb,
         rdyIb            => eoeRdyOb,

         txReq            => txReq,
         txRdy            => txRdy,

         pldMstOb         => ipPldMst,
         pldRdyOb         => ipPldRdy
      );

   U_IP_TX : entity work.MicroUDPTx
      port map (
         clk              => clk,
         rst              => rst,

         mstOb            => eoeMstIb,
         rdyOb            => eoeRdyIb,

         txReq            => txReq,
         txRdy            => txRdy,

         pldMstIb         => ipPldMst,
         pldRdyIb         => ipPldRdy
      );


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

end architecture rtl;
