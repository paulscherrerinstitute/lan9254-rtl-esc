------------------------------------------------------------------------------
--      Copyright (c) 2022-2023 by Paul Scherrer Institute, Switzerland
--      All rights reserved.
--  Authors: Till Straumann
--  License: PSI HDL Library License, Version 2.0 (see License.txt)
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.ESCBasicTypesPkg.all;
use work.Lan9254Pkg.all;
use work.ESCMbxPkg.all;

entity EoETb is
end entity EoETb;

architecture sim of EoETb is

   signal    clk : std_logic := '0';
   signal    rst : std_logic := '0';

   signal eoeMstIb : Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
   signal eoeRdyIb : std_logic          := '1';
   signal eoeMstOb : Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
   signal eoeRdyOb : std_logic          := '1';

   signal mbxMstOb : Lan9254StrmMstType;
   signal mbxMstIb : Lan9254StrmMstType;
   signal mbxRdy   : std_logic;

   signal frameSz  : unsigned(10 downto 0) := to_unsigned(59, 11);

   signal cnt      : unsigned(10 downto 0) := (others => '0');
   signal run      : boolean               := true;

begin

   P_CLK : process is
   begin
      if ( run ) then
         clk <= not clk;
         wait for 5 us;
      else
         wait;
      end if;
   end process P_CLK;


   P_LST  : process ( frameSz, cnt ) is
   begin
      eoeMstIb.last <= '0';
      eoeMstIb.ben  <= "11";
      if ( cnt + 2  >= frameSz ) then
         eoeMstIb.last <= '1';
         if ( frameSz(0) = '1' ) then
            eoeMstIb.ben(1) <= '0';
         end if;
      end if;
   end process P_LST;

   eoeMstIb.data  <= std_logic_vector(resize(cnt, 16));

   P_FEED : process is
   begin
      wait until rising_edge( clk );
      wait until rising_edge( clk );
      wait until rising_edge( clk );
      while ( cnt + 2 < frameSz ) loop
         wait until rising_edge(clk);
         eoeMstIb.valid <= '1';
         if ( ( eoeMstIb.valid and eoeRdyIb ) = '1' ) then
            cnt <= cnt + 2;
         end if;
      end loop;
      eoeMstIb.valid <= '0';
      for i in 1 to 200 loop
         wait until rising_edge( clk );
      end loop;
      wait;
   end process P_FEED;

   U_DUT_TX : entity work.ESCEoETx
      generic map (
         MAX_FRAGMENT_SIZE_G => 40,
         STORE_AND_FWD_G     => false,
         TEST_TIME_APPEND_G  => '1'
      )
      port map (
         clk                 => clk,
         rst                 => rst,

         eoeFrameSz          => frameSz,
         eoeMstIb            => eoeMstIb,
         eoeRdyIb            => eoeRdyIb,

         mbxMstOb            => mbxMstOb,
         mbxRdyOb            => mbxRdy
      );

   U_DUT_RX : entity work.ESCEoERx
      generic map (
         CLOCK_FREQ_G        => 100.0E3,
         STORE_AND_FWD_G     => true
      )
      port map (
         clk                 => clk,
         rst                 => rst,

         mbxMstIb            => mbxMstIb,
         mbxRdyIb            => mbxRdy,

         eoeMstOb            => eoeMstOb,
         eoeRdyOb            => eoeRdyOb
      );

   B_CHECK : block is
      signal got : unsigned(15 downto 0) := (others => '0');
      signal don : std_logic_vector(3 downto 0) := (others => '0');
   begin

   P_CHECK : process ( clk ) is
      variable len : unsigned(15 downto 0);
   begin
      if ( rising_edge( clk ) ) then
         if ( don(0) /= '0' ) then
            assert eoeMstOb.valid = '0' report "eoeMstOb.valid = 1 after frame" severity failure;
            assert mbxMstOb.valid = '0' report "mbxMstOb.valid = 1 after frame" severity failure;
            don <= don(don'left - 1 downto 0) & '1';
            if ( don(don'left) = '1' ) then
               report "TEST PASSED";
               run <= false;
            end if;
         elsif ( ( eoeMstOb.valid and eoeRdyOb ) = '1' ) then
            if ( eoeMstOb.last = '1' and eoeMstOb.ben(1) = '0' ) then
               assert got(7 downto 0) = unsigned(eoeMstOb.data(7 downto 0)) report "Data mismatch " & toString(eoeMstOb.data) severity failure;
            else
               assert got = unsigned(eoeMstOb.data) report "Data mismatch " & toString(eoeMstOb.data) severity failure;
            end if;
            if ( eoeMstOb.last = '1' ) then
               len := got;
               if ( eoeMstOb.ben(0) = '1' ) then
                  len := len + 1;
               end if;
               if ( eoeMstOb.ben(1) = '1' ) then
                  len := len + 1;
               end if;
               assert len = frameSz report "Final frame size mismatch" severity failure;
               don(0) <= '1';
            else
               assert eoeMstOb.ben = "11" report "BEN mismatch" severity failure;
            end if;
            got <= got + 2;
         end if;
      end if;
   end process P_CHECK;

   end block B_CHECK;

   mbxMstIb.valid <= mbxMstOb.valid;
   mbxMstIb.data  <= mbxMstOb.data;
   mbxMstIb.ben   <= mbxMstOb.ben ;
   mbxMstIb.last  <= mbxMstOb.last;

end architecture sim;
