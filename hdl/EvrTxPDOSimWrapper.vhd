library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.Lan9254Pkg.all;
use work.Udp2BusPkg.all;
use work.EvrTxPDOPkg.all;

-- wrapper to encapsulate the EvrTxPDO module -- which is not part of the ESC support
-- this allows Lan9254ESCrun to be compiled even if the EvrTxPDO module is not present
-- as hides the EvrTxPDOPkg.
entity EvrTxPDOSimWrapper is
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
end entity EvrTxPDOSimWrapper;

-- Simulation environment for Lan9254ESC. Run a simulation
-- of the ESC and let it talk to real LAN9254 hardware (e.g.
-- from a ZYNQ CPU).

architecture sim of EvrTxPDOSimWrapper is

   type Slv32Array is array ( natural range <> ) of std_logic_vector(31 downto 0);

   signal memData : Slv32Array(1 downto 0) := (
      0 => x"aabbccdd",
      1 => x"10203040"
   );

   constant MEM_XFERS_C : MemXferArray := (
      0 => ( off => x"0000", num => to_unsigned( 1, 10 ), swp => 2 ),
      1 => ( off => x"0004", num => to_unsigned( 1, 10 ), swp => 4 ),
      2 => ( off => x"0000", num => to_unsigned( 2, 10 ), swp => 0 )
   );

   signal busRepLoc          : Udp2BusRepType := UDP2BUSREP_INIT_C;

begin

   U_EVR : entity work.EvrTxPDO
      generic map (
         TXPDO_ADDR_G        => x"1180",
         MEM_XFERS_G         => MEM_XFERS_C,
         MEM_BASE_ADDR_G     => MEM_BASE_ADDR_G,
         NUM_EVENT_DWORDS_G  => 2
      )
      port map (
         evrClk              => evrClk,
         evrRst              => evrRst,

         pdoTrg              => pdoTrg,
         tsHi                => tsHi,
         tsLo                => tsLo,
         eventCode           => eventCode,
         eventCodeVld        => eventCodeVld,
         eventMapClr         => eventMapClr,

         busClk              => busClk,
         busRst              => busRst,

         hasTs               => hasTs,
         hasEventCodes       => hasEventCodes,
         hasLatch0P          => hasLatch0P,
         hasLatch0N          => hasLatch0N,
         hasLatch1P          => hasLatch1P,
         hasLatch1N          => hasLatch1N,

         -- LAN9254 HBI bus master IF
         lanReq              => lanReq,
         lanRep              => lanRep,

         -- EVR/UDP bus master IF (for accessing the EVR data buffer)
         busReq              => busMstReq,
         busRep              => busMstRep
      );

   P_MEM : process ( busClk ) is
      constant B_C : unsigned(busSubReq.dwaddr'range) :=
         resize( shift_right( MEM_BASE_ADDR_G, 2 ), busSubReq.dwaddr'length );
   begin
      if ( rising_edge ( busClk ) ) then
         if ( busSubReq.valid = '1' ) then
            busRepLoc.valid <= not busRepLoc.valid; -- = 1 cycle delay
            if ( unsigned(busSubReq.dwaddr) - B_C >= memData'length ) then
               busRepLoc.berr <= '1';
            else
               busRepLoc.berr <= '0';
               if ( busSubReq.rdnwr = '1' ) then
                  busRepLoc.rdata <= memData( to_integer( unsigned(busSubReq.dwaddr) - B_C ) );
               else
                  memData( to_integer( unsigned(busSubReq.dwaddr) - B_C ) ) <= busSubReq.data;
               end if;
            end if;
         end if;
      end if;
   end process P_MEM;

   busSubRep <= busRepLoc;

end architecture sim;
