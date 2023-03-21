-- bus transfer across asynchronous clock domains
library ieee;
use     ieee.std_logic_1164.all;
use     work.Udp2BusPkg.all;

-- if the resets are going to be used then additional logic is required
-- to ensure both sides of the bridge are reset.
entity Bus2BusAsyncTb is
end entity Bus2BusAsyncTb;

architecture Impl of Bus2BusAsyncTb is

   signal clkMst       : std_logic := '0';

   signal reqMst       : Udp2BusReqType;
   signal repMst       : Udp2BusRepType;

   signal clkSub       : std_logic := '0';

   signal reqSub       : Udp2BusReqType := UDP2BUSREQ_INIT_C;
   signal repSub       : Udp2BusRepType := UDP2BUSREP_INIT_C;
 
   signal run          : boolean := true;

   procedure tickm is begin
      wait until rising_edge( clkMst );
   end procedure tickm;

   procedure ticks is begin
      wait until rising_edge( clkSub );
   end procedure ticks;

begin
   process is begin
      if ( run ) then wait for 10 ns ; clkMst <= not clkMst; else wait; end if;
   end process;

   process is begin
      if ( run ) then wait for 22 ns ; clkSub <= not clkSub; else wait; end if;
   end process;

   process is begin
      tickm;
      reqMst.rdnwr  <= '0';
      reqMst.be     <= "0110";
      reqMst.data   <= x"deadcafe";
      reqMst.valid  <= '1';
      reqMst.dwaddr <= (others => '0');
      tickm;
      while ( repMst.valid = '0' ) loop
         tickm;
      end loop;
      reqMst.dwaddr(3 downto 0) <= "0001";
      reqMst.data  <= x"feedbeef";
      tickm;
      while ( repMst.valid = '0' ) loop
         tickm;
      end loop;
      reqMst.valid <= '0';
      tickm;
      tickm;
      reqMst.valid <= '1';
      reqMst.rdnwr <= '1';
      reqMst.dwaddr(3 downto 0) <= "0000";
      while ( repMst.valid = '0' ) loop
         tickm;
      end loop;
      assert repMst.berr  = '0'         severity failure;
      assert repMst.rdata = x"12345678" severity failure;
      reqMst.valid <= '0';
      tickm;
      reqMst.valid              <= '1';
      reqMst.dwaddr(3 downto 0) <= "0001";
      tickm;
      while ( repMst.valid = '0' ) loop
         tickm;
      end loop;
      assert repMst.berr  = '1'         severity failure;
      assert repMst.rdata = x"abcdef00" severity failure;
      reqMst.valid <= '0';
      tickm;
      run <= false;
      report "TEST PASSED";
      wait;
   end process;

   process ( clkSub ) is begin
      if ( rising_edge( clkSub ) ) then
         repSub.valid <= '0';
         if ( ( not repSub.valid and reqSub.valid ) = '1' ) then
            if ( reqSub.dwaddr = "00" & x"000_0000" ) then
               if ( reqSub.rdnwr = '1' ) then
                  repSub.rdata  <= x"1234_5678";
                  repSub.berr   <= '0';
                  repSub.valid  <= '1';
               else
                  assert reqSub.be   = "0110"      severity failure;
                  assert reqSub.data = x"deadcafe" severity failure;
                  repSub.valid <= '1';
               end if;
            elsif ( reqSub.dwaddr = "00" & x"000_0001" ) then
               if ( reqSub.rdnwr = '1' ) then
                  repSub.rdata <= x"abcd_ef00";
                  repSub.berr  <= '1';
                  repSub.valid <= '1';
               else
                  assert reqSub.be   = "0110"      severity failure;
                  assert reqSub.data = x"feedbeef" severity failure;
                  repSub.valid <= '1';
               end if;
            else
               report "Illegal Address" severity failure;
            end if;
         end if;
      end if;
   end process;

   U_DUT : entity work.Bus2BusAsync
      port map (
         clkMst       => clkMst,

         reqMst       => reqMst,
         repMst       => repMst,

         clkSub       => clkSub,

         reqSub       => reqSub,
         repSub       => repSub
      );


end architecture Impl;
