library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.Lan9254Pkg.all;

-- HBI in single-cycle, 16-bit wide multiplexed mode
entity Lan9254HBI is

   generic (
      -- could use these generics to implement different modes
      DATA_WIDTH_G   : positive range 16   to 16   := 16;
      ADDR_WIDTH_G   : positive range 16   to 16   := 16;
      MUXED_MODE_G   : boolean  range true to true := true;
      CLOCK_FREQ_G   : real
   );
   port (
      clk            : in  std_logic;
      cen            : in  std_logic := '1';
      rst            : in  std_logic := '0';

      -- upstream interface
      req            : in  Lan9254ReqType;
      rep            : out Lan9254RepType    := LAN9254REP_INIT_C;

      -- HBI interface to LAN9254 chip
      hbiOut         : out Lan9254HBIOutType := LAN9254HBIOUT_INIT_C;
      hbiInp         : in  Lan9254HBIInpType
   );

end entity Lan9254HBI;

architecture rtl of Lan9254HBI is

   -- Bus Timing (wait-ack: not WAITb_ACK_C -> WAIT, WAITb_ACK_C -> ACK)
   --
   -- Read data cycle (after address):
   --    assert RS 
   --    must wait until wait_ack indicates the internal machinery is crunching (twadv)
   --    wait until wait_ack indicates internal read has completed (-> until '1')
   --    latch data and deassert RS
   --    NOTE: wait_ack is asynchronous; sync stages must be taken into account when
   --          calculating the timing!
   --
   -- READ timing
   --
   -- twale  (ALE pulse width          > 10ns)
   -- tadrs  (address setup time       > 10ns) (to ALE negedge)
   -- tadrh  (address hold time        >  5ns) (from ALE negedge)
   -- talerd (ALE release to RD        >  5ns)
   -- trdale (rd deassert to next ALE  > 13ns)
   -- trdwa  (rd assert to waitack lo  < 10ns)
   -- twadv  (waitack hi to data valid < 5 ns) 'normal' wait-ack (=> valid data after WAIT_ACK = '1')
   -- tdvwa  (data valid to waitack hi > 15ns) 'delayed' wait-ack (=> valid data AFTER wait-ack = '1')
   -- 
   -- POSTED WRITE timing
   -- talewr (ALE release to WR        >  5ns)  => matches read timing
   -- twr    (WR pulse width           > 32ns)  (stretched by waitb-ack)
   -- tds    (data setup to WR inact.  > 10ns)  => easy/implicit
   -- twawr  (waitb-ack to WR inact    >  0ns)  => easy
   -- tdwrh  (write-data hold from WR  >  5ns)
   constant SYNC_STAGES_C          : positive := 2;

   constant MARGIN_C               : real := 5.0E-9;

   constant TWALE_C                : real := 10.0E-9 + MARGIN_C;
   constant TADRS_C                : real := 10.0E-9 + MARGIN_C;
   constant TADRH_C                : real :=  5.0E-9 + MARGIN_C;
   constant TALER_C                : real :=  5.0E-9 + MARGIN_C;
   constant TRDAL_C                : real := 13.0E-9 + MARGIN_C;
   constant TRDWA_C                : real := 10.0E-9 + MARGIN_C;
   constant TWR_C                  : real := 32.0E-9 + MARGIN_C;
   constant TDWRH_C                : real :=  5.0E-9 + MARGIN_C;
   -- add a timeout for wait/ack in case it is not configured
   constant TWAK_TIMEO_C           : real := 600.0E-9;


   constant TWALE_CNT_C            : natural := initCnt(TWALE_C*CLOCK_FREQ_G);
   constant TADRS_CNT_C            : natural := initCnt(TADRS_C*CLOCK_FREQ_G);
   constant TADRH_CNT_C            : natural := initCnt(TADRH_C*CLOCK_FREQ_G);
   constant TALER_CNT_C            : natural := initCnt(TADRH_C*CLOCK_FREQ_G);
   constant TRDAL_CNT_C            : natural := initCnt(TRDAL_C*CLOCK_FREQ_G);
   constant TRDWA_CNT_C            : natural := initCnt(TRDWA_C*CLOCK_FREQ_G) + SYNC_STAGES_C;
   constant TWR_CNT_C              : natural := initCnt(TWR_C  *CLOCK_FREQ_G);
   constant TDWRH_CNT_C            : natural := initCnt(TDWRH_C*CLOCK_FREQ_G);
   constant TWAK_TIMEO_CNT_C       : natural := initCnt(TWAK_TIMEO_C*CLOCK_FREQ_G);


   constant MAX_DELAY_C            : natural := max(
      (
      TWALE_CNT_C,
      TADRS_CNT_C,
      TADRH_CNT_C,
      TALER_CNT_C,
      TRDAL_CNT_C,
      TRDWA_CNT_C,
      TWR_CNT_C,
      TDWRH_CNT_C
      )
   );

   type    StateType is ( IDLE, ADDR, AWAIT, READ, WRITE, HSHK );

   subtype DelayType is natural range 0 to MAX_DELAY_C;

   subtype TimeoType is natural range 0 to TWAK_TIMEO_CNT_C;

   type RegType is record
      hbiOut         : Lan9254HBIOutType;
      req            : Lan9254ReqType;
      rep            : Lan9254RepType;
      state          : StateType;
      nstate         : StateType;
      dly            : DelayType;
      timeo          : TimeoType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      rep            => LAN9254REP_INIT_C,
      req            => LAN9254REQ_INIT_C,
      hbiOut         => LAN9254HBIOUT_INIT_C,
      state          => IDLE,
      nstate         => IDLE,
      dly            => 0,
      timeo          => 0
   );

   signal r           : RegType := REG_INIT_C;
   signal rin         : RegType;

   signal waitAckSync : std_logic;
   signal waitAckDone : boolean;

   constant END_SEL_C : std_logic := '0';

begin

   assert DATA_WIDTH_G = 16 report "Only DATA_WIDTH_G = 16 implemented ATM, sorry" severity failure;
   assert ADDR_WIDTH_G = 16 report "Only ADDR_WIDTH_G = 16 implemented ATM, sorry" severity failure;
   assert MUXED_MODE_G      report "Only MUXED_MODE_G = true implemented ATM, sorry" severity failure;

   -- wait/ack is supplied asynchronously!
   U_WA_SYNC : entity work.SynchronizerBit
      generic map (
         STAGES_G   => SYNC_STAGES_C,
         RSTPOL_G   => (not WAITb_ACK_C)
      )
      port map (
         clk        => clk,
         rst        => rst,
         datInp(0)  => hbiInp.waitAck,
         datOut(0)  => waitAckSync
      );

   waitAckDone <= ( (r.timeo = 0) or ( (waitAckSync = WAITb_ACK_C) and (r.req.noAck = '0') ) );

   P_COMB : process( r, req, hbiInp, waitAckDone ) is
      variable v : RegType;

      constant BE_DEASS_C  : std_logic_vector(3 downto 0)          := (others => not HBI_BE_ACT_C);
      constant ALE_DEASS_C : std_logic_vector(r.hbiOut.ale'range)  := (others => not HBI_AL_ACT_C); 

      procedure DONE(
         variable vv: inout RegType;
         constant dl: in    DelayType := 0
      ) is
      begin
         vv.rep.valid := '1';
         vv.state     := HSHK;
      end procedure DONE;

   begin
      v := r;

      -- reply only valid for 1 cycle
      v.rep.valid := '0';

      if ( r.timeo /= 0 ) then
         v.timeo := r.timeo - 1;
      end if;

      -- delay counter
      B_DELAY : if ( r.dly /= 0 ) then
         v.dly := r.dly - 1;
      else
         -- only do work if no delay is pending

         case ( r.state ) is

            when IDLE =>
               v.rep    := LAN9254REP_INIT_C;
         
               -- latch request
               v.req    := req;
               -- reset reply and bus signals
               v.hbiOut := LAN9254HBIOUT_INIT_C;

               if ( req.valid = '1' ) then
                  v.state    := ADDR;
               end if;

            when HSHK =>
               -- handshake
               -- one cycle when req.valid = '1' and rep.valid = '1'
               v.rep.valid := '0';
               v.state     := IDLE;

            when ADDR =>
               if ( (r.req.addr(1 downto 0) = "00") and (r.req.be /= BE_DEASS_C)  ) then
                  v.hbiOut.cs              := HBI_CS_ACT_C;
                  v.hbiOut.ale(0)          := HBI_AL_ACT_C;
                  v.hbiOut.ad(13)          := END_SEL_C;
                  v.hbiOut.ad(12 downto 1) := r.req.addr(13 downto 2);
                  v.hbiOut.ad_t            := (others => '0');
                  if ( r.req.be(1 downto 0) /= BE_DEASS_C(1 downto 0) ) then
                     -- low-word transfer
                     v.hbiOut.be           := r.req.be(1 downto 0);
                     v.req.be(1 downto 0)  := BE_DEASS_C(1 downto 0);
                     v.hbiOut.ad(0)        := '0'; -- select lo-word
                  else
                     -- hi-word transfer (be(3:2) must be active; we tested all lines above
                     -- and just checked that be(1:0) are zero)
                     v.hbiOut.be           := r.req.be(3 downto 2);
                     v.req.be(3 downto 2)  := BE_DEASS_C(3 downto 2);
                     v.hbiOut.ad(0)        := '1'; -- select hi-word
                  end if;

                  v.dly                    := TWALE_CNT_C;
                  v.state                  := AWAIT;
               else
                  -- misaligned address or otherwise done
                  DONE( v );
               end if;

            when AWAIT =>
               if ( r.hbiOut.ale /= ALE_DEASS_C ) then
                  v.hbiOut.ale  := (others => not HBI_AL_ACT_C);
                  -- max(tadrh,talerd) but they are identical
                  v.dly         := TADRH_CNT_C;
               else
                  if ( v.req.rdnwr = '1' ) then
                     -- FIXME -- should we turn off the AD buffers before asserting RD ?
                     v.hbiOut.ad_t := (others => '1');
                     v.state       := READ;
                     v.hbiOut.rs   := HBI_RS_ACT_C;
                     v.dly         := TRDWA_CNT_C;
                  else
                     v.state       := WRITE;
                     v.hbiOut.ws   := HBI_WS_ACT_C;
                     v.dly         := TWR_CNT_C;
                     if ( r.hbiOut.ad(0) = '1' ) then
                        v.hbiOut.ad   := req.wdata(31 downto 16);
                     else
                        v.hbiOut.ad   := req.wdata(15 downto  0);
                     end if;
                  end if;
                  v.timeo := TWAK_TIMEO_CNT_C;
               end if;

            when READ =>
               if ( r.hbiOut.rs = HBI_RS_ACT_C ) then
                  -- wait ack
                  if ( waitAckDone ) then
                     v.timeo        := 0;
                     -- capture data
                     if ( r.hbiOut.ad(0) = '1' ) then -- hi-word selected
                        v.rep.rdata(31 downto 16) := hbiInp.ad;
                     else
                        v.rep.rdata(15 downto  0) := hbiInp.ad;
                     end if;
                     v.rep.berr  := (others => '0'); -- OK so far
                     v.hbiOut.rs := not HBI_RS_ACT_C;
                     if ( r.req.be = BE_DEASS_C ) then
                        -- no more work; deassert CS
                        v.hbiOut.cs := not HBI_CS_ACT_C;
                        DONE(v, TRDAL_CNT_C);
                     else
                        v.dly       := TRDAL_CNT_C;
                        v.state     := ADDR; -- a second cycle is necessary
                     end if;
                  end if;
               end if;

            when WRITE =>
               if ( r.hbiOut.ws = HBI_WS_ACT_C ) then
                  if ( waitAckDone ) then
                     v.timeo     := 0;
                     v.rep.berr  := (others => '0');
                     v.hbiOut.ws := not HBI_WS_ACT_C;
                     if ( r.req.be = BE_DEASS_C ) then
                        -- no more work; deassert CS
                        v.hbiOut.cs := not HBI_CS_ACT_C;
                        -- must hold data after deasserting ws/cs
                        v.dly       := TDWRH_CNT_C;
                     else
                        -- min. delay until second access
                        v.dly       := TRDAL_CNT_C;
                        v.state     := ADDR;
                     end if;
                  end if;
               else
                  -- only get here if be = BE_DEASS_C
                  -- high-Z the bus and wait for the rest trdale
                  v.hbiOut.ad_t := (others => '1');
                  DONE(v, TRDAL_CNT_C - TDWRH_CNT_C);
               end if;
         end case;
      end if B_DELAY;

      v.hbiOut.cs := '0';

      rin <= v;
   end process P_COMB;

   P_SEQ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= REG_INIT_C;
         elsif ( cen = '1' ) then
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

   hbiOut <= r.hbiOut;
   rep    <= r.rep;

end architecture rtl;
