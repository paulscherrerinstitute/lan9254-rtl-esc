------------------------------------------------------------------------------
--      Copyright (c) 2022-2023 by Paul Scherrer Institute, Switzerland
--      All rights reserved.
--  Authors: Till Straumann
--  License: PSI HDL Library License, Version 2.0 (see License.txt)
------------------------------------------------------------------------------

-- (slow) bus transfer across asynchronous clock domains. A transfer
-- takes several clock cycles (on both sides of the bridge) to complete.

-- NOTE: proper constraints should constrain the datapath delays as well
--       as declare false paths through the bit-synchronizers.
library ieee;
use     ieee.std_logic_1164.all;
use     work.Udp2BusPkg.all;
use     work.ESCBasicTypesPkg.all;
use     work.IlaWrappersPkg.all;

-- if the resets are going to be used then additional logic is required
-- to ensure both sides of the bridge are reset.
entity Bus2BusAsync is
   generic (
      -- set 'KEEP' = "TRUE" on clock-crossing signals to help writing constraints
      KEEP_XSIGNALS_G     : boolean  := true;
      SYNC_STAGES_M2S_G   : positive := 2;
      SYNC_STAGES_S2M_G   : positive := 2;
      GEN_MST_ILA_G       : boolean  := false;
      GEN_SUB_ILA_G       : boolean  := false
   );
   port (
      clkMst       : in  std_logic;
      rstMst       : in  std_logic := '0'; -- reset master side (only)

      reqMst       : in  Udp2BusReqType;
      repMst       : out Udp2BusRepType;

      clkSub       : in  std_logic;
      rstSub       : in  std_logic := '0'; -- reset subordinate side (only)

      reqSub       : out Udp2BusReqType;
      repSub       : in  Udp2BusRepType
   );
end entity Bus2BusAsync;

architecture Impl of Bus2BusAsync is

   attribute KEEP     : string;

   signal tglMstNxt   : std_logic;
   signal tglMst      : std_logic := '0';
   signal tglSub      : std_logic := '0';
   signal tglSubNxt   : std_logic;
   signal monMst      : std_logic;
   signal monSub      : std_logic;
   signal wrkMst      : std_logic := '0'; -- master side working
   signal wrkMstNxt   : std_logic;
   signal reqSubNxt   : Udp2BusReqType := UDP2BUSREQ_INIT_C;
   signal reqSubLoc   : Udp2BusReqType := UDP2BUSREQ_INIT_C;
   signal repMstNxt   : Udp2BusRepType := UDP2BUSREP_INIT_C;
   signal repMstLoc   : Udp2BusRepType := UDP2BUSREP_INIT_C;
   signal repSubNxt   : Udp2BusRepType := UDP2BUSREP_INIT_C;

   signal reqMstLoc   : Udp2BusReqType;
   signal repSubLoc   : Udp2BusRepType := UDP2BUSREP_INIT_C;

   -- may set KEEP on domain-crossing signals
   attribute KEEP    of reqMstLoc : signal is toString( KEEP_XSIGNALS_G );
   attribute KEEP    of repSubLoc : signal is toString( KEEP_XSIGNALS_G );

begin

   reqMstLoc <= reqMst;

   G_MST_ILA : if ( GEN_MST_ILA_G ) generate
      U_ILA : Ila_256
         port map (
            clk                  => clkMst,

            probe0(31 downto  0) => reqMstLoc.data,
            probe0(61 downto 32) => reqMstLoc.dwaddr,
            probe0(62          ) => reqMstLoc.valid,
            probe0(63          ) => reqMstLoc.rdnwr,

            probe1( 3 downto  0) => reqMstLoc.be,
            probe1(63 downto  4) => (others => '0'),

            probe2(31 downto  0) => repMstLoc.rdata,
            probe2(61 downto 32) => (others => '0'),
            probe2(62          ) => repMstLoc.valid,
            probe2(63          ) => repMstLoc.berr,

            probe3               => (others => '0')
         );
   end generate;

   P_MST_COMB : process ( reqMst, repMstLoc, repSubLoc, wrkMst, tglMst, monSub ) is 
   begin
      repMstNxt       <= repMstLoc;
      repMstNxt.valid <= '0';
      wrkMstNxt       <= wrkMst;
      tglMstNxt       <= tglMst;

      if ( (  wrkMst and (tglMst xnor monSub) ) = '1' ) then
         -- we remain for two cycles in this state; first we latch data and assert
         -- 'valid' then we reset and end the cycle.
         if ( repMstLoc.valid = '0' ) then
            -- the sub has acked and it has arrived on the master side (tglMst == monSub)
            repMstNxt       <= repSubLoc;
            repMstNxt.valid <= '1';
         else
            repMstNxt.valid <= '0';
            -- reset the 'working' flag
            wrkMstNxt       <= '0';
         end if;
      end if;
      if ( ( not wrkMst and reqMst.valid ) = '1' ) then
         wrkMstNxt <= '1';        -- start new cycle
         tglMstNxt <= not monSub; -- signal to the sub-side
      end if;
   end process P_MST_COMB;

   P_MST_SEQ  : process ( clkMst ) is
   begin
      if ( rising_edge( clkMst ) ) then
         if ( rstMst = '1' ) then
            wrkMst    <= '0';
            tglMst    <= '0';
            repMstLoc <= UDP2BUSREP_INIT_C;
         else
            tglMst    <= tglMstNxt;
            wrkMst    <= wrkMstNxt;
            repMstLoc <= repMstNxt;
         end if;
      end if;
   end process P_MST_SEQ;

   repMst <= repMstLoc;

   P_SUB_COMB : process ( reqMstLoc, reqSubLoc, repSubLoc, repSub, tglSub, monMst ) is
   begin
      tglSubNxt       <= tglSub;
      reqSubNxt       <= reqSubLoc;
      repSubNxt       <= repSubLoc;
      reqSubNxt.valid <= '0';

      if ( ( monMst xor tglSub ) = '1' ) then
         reqSubNxt       <= reqMstLoc;
         reqSubNxt.valid <= '1';
      end if;
      if ( repSub.valid = '1' ) then
         -- the sub has acked; propagate the token back to the
         -- master side;
         tglSubNxt       <= monMst;
         reqSubNxt.valid <= '0';
         -- register the reply; the sub-side may not hold after
         -- the 'valid' cycle
         repSubNxt       <= repSub;
      end if;
      repSubNxt.valid    <= '0'; -- unused; the 'valid' flag is handled separately
   end process P_SUB_COMB;

   P_SUB_SEQ  : process ( clkSub ) is
   begin
      if ( rising_edge( clkSub ) ) then
         if ( rstSub = '1' ) then
            tglSub    <= '0';
            reqSubLoc <= UDP2BUSREQ_INIT_C;
            repSubLoc <= UDP2BUSREP_INIT_C;
         else
            tglSub    <= tglSubNxt;
            reqSubLoc <= reqSubNxt;
            repSubLoc <= repSubNxt;
         end if;
      end if;
   end process P_SUB_SEQ;

   reqSub <= reqSubLoc;

   U_SYNC_TGL_M2S : entity work.SynchronizerBit
      generic map (
         STAGES_G   => SYNC_STAGES_M2S_G
      )
      port map (
         clk        => clkSub,
         rst        => rstSub,
         datInp(0)  => tglMstNxt,
         datOut(0)  => monMst
      );

   U_SYNC_TGL_S2M : entity work.SynchronizerBit
      generic map (
         STAGES_G  => SYNC_STAGES_S2M_G
      )
      port map (
         clk       => clkMst,
         rst       => rstMst,
         datInp(0) => tglSubNxt,
         datOut(0) => monSub
      );

end architecture Impl;
