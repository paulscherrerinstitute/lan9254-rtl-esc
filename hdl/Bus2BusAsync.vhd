-- bus transfer across asynchronous clock domains
library ieee;
use     ieee.std_logic_1164.all;
use     work.Udp2BusPkg.all;

-- if the resets are going to be used then additional logic is required
-- to ensure both sides of the bridge are reset.
entity Bus2BusAsync is
   generic (
      SYNC_STAGES_G : positive := 2
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

   signal tglMstNxt   : std_logic;
   signal tglMst      : std_logic := '0';
   signal tglSub      : std_logic := '0';
   signal tglSubNxt   : std_logic;
   signal monMst      : std_logic;
   signal monSub      : std_logic;
   signal wrkMst      : std_logic := '0'; -- master side working
   signal wrkMstNxt   : std_logic;

begin

   P_MST_COMB : process ( reqMst, repSub, wrkMst, tglMst, monSub ) is 
   begin
      repMst       <= repSub;
      repMst.valid <= '0';
      wrkMstNxt    <= wrkMst;
      tglMstNxt    <= tglMst;

      if ( (  wrkMst and (tglMst xnor monSub) ) = '1' ) then
         -- the sub has acked and it has arrived on the master side (tglMst == monSub)
         repMst.valid <= '1';
         -- reset the 'working' flag
         wrkMstNxt    <= '0';
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
         else
            tglMst    <= tglMstNxt;
            wrkMst    <= wrkMstNxt;
         end if;
      end if;
   end process P_MST_SEQ;

   P_SUB_COMB : process ( reqMst, repSub, tglSub, monMst ) is
   begin
      tglSubNxt    <= tglSub;
      reqSub       <= reqMst;
      reqSub.valid <= monMst xor tglSub;
      if ( repSub.valid = '1' ) then
         -- the sub has acked; propagate the token back to the
         -- master side; note that this also withdraws reqSub.valid
         -- during the following sycle (monMst xor tglSub will be false)
         tglSubNxt <= monMst;
      end if;
   end process P_SUB_COMB;

   P_SUB_SEQ  : process ( clkSub ) is
   begin
      if ( rising_edge( clkSub ) ) then
         if ( rstSub = '1' ) then
            tglSub    <= '0';
         else
            tglSub    <= tglSubNxt;
         end if;
      end if;
   end process P_SUB_SEQ;


   U_SYNC_TGL_M2S : entity work.SynchronizerBit
      generic map (
         STAGES_G   => SYNC_STAGES_G
      )
      port map (
         clk        => clkSub,
         rst        => rstSub,
         datInp(0)  => tglMstNxt,
         datOut(0)  => monMst
      );

   U_SYNC_TGL_S2M : entity work.SynchronizerBit
      generic map (
         STAGES_G  => SYNC_STAGES_G
      )
      port map (
         clk       => clkMst,
         rst       => rstMst,
         datInp(0) => tglSubNxt,
         datOut(0) => monSub
      );

end architecture Impl;
