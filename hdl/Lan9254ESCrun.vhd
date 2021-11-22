library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.Lan9254Pkg.all;
use work.Lan9254ESCPkg.all;
use work.ESCMbxPkg.all;
use work.MicroUDPPkg.all;
use work.Udp2BusPkg.all;

entity Lan9254ESCrun is
   generic (
      EVR_TXPDO_G : boolean := true
   );
end entity Lan9254ESCrun;

-- Simulation environment for Lan9254ESC. Run a simulation
-- of the ESC and let it talk to real LAN9254 hardware (e.g.
-- from a ZYNQ CPU).

architecture rtl of Lan9254ESCrun is
   constant N_HBI_M_C : natural := 1;
   constant PRI_C     : integer := -1;
   constant HBI_R_C   : integer := PRI_C;
   constant HBI_L_C   : integer := HBI_R_C + N_HBI_M_C - 1;

   constant N_BUS_M_C : natural := 1;
   constant N_BUS_S_C : natural := 1;

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

   signal txPDOMst : Lan9254PDOMstType := LAN9254PDO_MST_INIT_C;
   signal txPDORdy : std_logic;

   signal decim    : natural := 1000;

   signal irq      : std_logic := not EC_IRQ_ACT_C;

   signal rstDrv   : std_logic := '1';

   signal hbiReq   : Lan9254ReqArray(HBI_L_C downto HBI_R_C)  := (others => LAN9254REQ_INIT_C);
   signal hbiRep   : Lan9254RepArray(HBI_L_C downto HBI_R_C);

   signal busMstReq: Udp2BusReqArray(N_BUS_M_C - 1 downto 0)  := (others => UDP2BUSREQ_INIT_C);
   signal busMstRep: Udp2BusRepArray(N_BUS_M_C - 1 downto 0)  := (others => UDP2BUSREP_INIT_C);

   signal busSubReq: Udp2BusReqArray(N_BUS_S_C - 1 downto 0)  := (others => UDP2BUSREQ_INIT_C);
   signal busSubRep: Udp2BusRepArray(N_BUS_S_C - 1 downto 0)  := (others => UDP2BUSREP_INIT_C);

   signal pdoTrg   : std_logic                    := '0';
   signal eventCod : std_logic_vector(7 downto 0) := x"22";
   signal eventVld : std_logic                    := '1';


   function pollIRQ_C return integer;

   attribute foreign of pollIRQ_C : function is "VHPIDIRECT pollIRQ_C";

   function pollIRQ_C return integer is
   begin
      assert false report "pollIRQ_C should be foreign" severity failure;
   end function pollIRQ_C;

   constant MEM_BASE_ADDR_C : unsigned(31 downto 0) := x"48c00000";

   component EvrTxPDOSimWrapper is
      generic (
         NUM_EVENT_DWORDS_G : natural range 0 to 8  := 8;
         MEM_BASE_ADDR_G    : unsigned(31 downto 0) := (others => '0');
         TXPDO_ADDR_G       : unsigned(15 downto 0)
      );
      port (
         evrClk              : in  std_logic;
         evrRst              : in  std_logic;

         -- triggers update of the PDO
         pdoTrg              : in  std_logic;
         tsHi                : in  std_logic_vector(31 downto  0);
         tsLo                : in  std_logic_vector(31 downto  0);
         eventCode           : in  std_logic_vector( 7 downto  0);
         eventCodeVld        : in  std_logic;
         eventMapClr         : in  std_logic_vector( 7 downto  0);

         busClk              : in  std_logic;
         busRst              : in  std_logic;

         hasTs               : in  std_logic := '1';
         hasEventCodes       : in  std_logic := '1';
         hasLatch0P          : in  std_logic := '1';
         hasLatch0N          : in  std_logic := '1';
         hasLatch1P          : in  std_logic := '1';
         hasLatch1N          : in  std_logic := '1';

         -- LAN9254 HBI bus master IF
         lanReq              : out Lan9254ReqType := LAN9254REQ_INIT_C;
         lanRep              : in  Lan9254RepType := LAN9254REP_INIT_C;

         busMstReq           : out Udp2BusReqType := UDP2BUSREQ_INIT_C;
         busMstRep           : in  Udp2BusRepType := UDP2BUSREP_INIT_C;

         busSubReq           : in  Udp2BusReqType := UDP2BUSREQ_INIT_C;
         busSubRep           : out Udp2BusRepType := UDP2BUSREP_INIT_C
      );
   end component EvrTxPDOSimWrapper;


begin

   process is begin
      if ( run ) then
         wait for 10 us;
         clk <= not clk;
      else
         wait;
      end if;
   end process;

   GEN_TXPDO : if ( not EVR_TXPDO_G ) generate

   begin

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
                  if ( txPDOMst.wrdAddr >= resize( shift_right( unsigned( ESC_SM3_LEN_C ) - 1, 1 ), txPDOMst.wrdAddr'length ) ) then
                     txPDOMst.wrdAddr <= (others => '0');
                     txPDOMst.valid   <= '0';
                  end if;
               end if;
            end if;
         end if;
      end process;

      txPDOMst.data <= std_logic_vector(to_unsigned(cnt, txPDOMst.data'length));

   end generate GEN_TXPDO;


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

   process ( clk ) is
      variable v : signed(31 downto 0);
   begin
      if ( rising_edge( clk ) ) then
         -- just reflect the irq level here; we don't know
         -- which one is active...
         v := to_signed( pollIRQ_C, v'length );
         irq    <= v(0);
         pdoTrg <= v(12);
      end if;
   end process;

   U_DUT : entity work.Lan9254ESCWrapper
      generic map (
         CLOCK_FREQ_G          => 10.0E4,
         ENABLE_EOE_G          => true,
         DISABLE_TXPDO_G       => EVR_TXPDO_G,
         NUM_EXT_HBI_MASTERS_G => N_HBI_M_C,
         EXT_HBI_MASTERS_PRI_G => HBI_R_C,
         NUM_BUS_MSTS_G        => N_BUS_M_C,
         NUM_BUS_SUBS_G        => N_BUS_S_C
      )
      port map (
         clk         => clk,
         rst         => rst,

         req         => req,
         rep         => rep,

         extHBIReq   => hbiReq,
         extHBIRep   => hbiRep,

         busMstReq   => busMstReq,
         busMstRep   => busMstRep,

         busSubReq   => busSubReq,
         busSubRep   => busSubRep,

         rxPDOMst    => rxPDOMst,
         rxPDORdy    => rxPDORdy,

         txPDOMst    => txPDOMst,
         txPDORdy    => txPDORdy,

         irq         => irq
      );

   GEN_EVR_TXPDO : if ( EVR_TXPDO_G ) generate
   begin
      U_EVR : component EvrTxPDOSimWrapper
         generic map (
            TXPDO_ADDR_G        => x"1180",
            MEM_BASE_ADDR_G     => MEM_BASE_ADDR_C,
            NUM_EVENT_DWORDS_G  => 2
         )
         port map (
            evrClk              => clk,
            evrRst              => rst,

            -- triggers update of the PDO
            pdoTrg              => pdoTrg,
            tsHi                => x"12345678",
            tsLo                => x"abcdef00",
            eventCode           => eventCod,
            eventCodeVld        => eventVld,
            eventMapClr         => x"00",

            busClk              => clk,
            busRst              => rst,

            hasTs               => '1',
            hasEventCodes       => '1',
            hasLatch0P          => '1',
            hasLatch0N          => '0',
            hasLatch1P          => '1',
            hasLatch1N          => '0',

            -- LAN9254 HBI bus master IF
            lanReq              => hbiReq(HBI_L_C),
            lanRep              => hbiRep(HBI_L_C),

            -- EVR/UDP bus master IF (for accessing the EVR data buffer)
            busMstReq           => busMstReq(0),
            busMstRep           => busMstRep(0),

            busSubReq           => busSubReq(0),
            busSubRep           => busSubRep(0)
         );
   end generate GEN_EVR_TXPDO;

end architecture rtl;
