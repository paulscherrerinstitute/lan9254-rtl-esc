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

entity StrmFifoSyncTb is
end entity StrmFifoSyncTb;

architecture Sim of StrmFifoSyncTb is
   signal clk : std_logic := '0';
   signal rst : std_logic := '0';
   signal run : boolean   := true;

   signal fifoRst     : std_logic;

   signal strmMstIb   : Lan9254StrmMstType    := LAN9254STRM_MST_INIT_C;
   signal strmRdyIb   : std_logic;
   signal emptySlots  : unsigned(12 downto 0);
   signal strmMstOb   : Lan9254StrmMstType;
   signal strmRdyOb   : std_logic := '0';

   signal cnt         : integer   := 0;
 begin

   process is
   begin
      if ( run ) then
         wait for 1 us;
         clk <= not clk ;
      else
         wait;
      end if;
   end process;

   assert ( cnt < 128 ) severity failure;
   strmMstIb.data <= std_logic_vector( to_unsigned( 256*(2*cnt + 1) + 2*cnt, 16 ) );

   process ( clk ) is
      variable got : integer := 0;
      -- test fifo-pointer wrap-around
      variable rep : integer := 1000;
   begin
      if ( rising_edge( clk ) ) then
         if ( fifoRst = '1' ) then
            cnt             <= 0;
            strmMstIb.valid <= '0';
         else
            if ( rep = 0 ) then
               run <= false;
            else
             
            if ( strmMstIb.valid = '0' or strmRdyIb = '1' ) then
               cnt <= cnt + 1;
            end if;

            strmMstIb.last <= '0';
            strmMstIb.ben  <= "11";
            case cnt is
               when 30  =>
                  assert got = 9 report "Expected 9, found " & integer'image(got) severity failure;
                  assert strmMstIb.valid = '0' severity failure;
                  rep := rep - 1;
                  got := 0;
                  cnt <= 0;
               when 1 =>
                  strmMstIb.valid <= '1';
               when 5 =>
                  if ( strmRdyIb = '1' ) then
                     strmMstIb.valid <= '0';
                  end if;

               when 8 =>
                  strmRdyOb       <= '1';
                  strmMstIb.valid <= '1';
                  strmMstIb.ben   <= "00";
                  strmMstIb.last  <= '1';
               when  9 | 12 =>
                  if ( strmRdyIb = '1' ) then
                     strmMstIb.valid <= '0';
                  end if;
                  strmRdyOb <= '0';
               when 11 =>
                  strmMstIb.valid <= '1';
                  strmMstIb.ben   <= "10";
                  strmMstIb.last  <= '1';
               when 13 | 23 =>
                  strmRdyOb <= '1';
               when others =>
            end case;

            if ( (strmMstOb.valid and strmRdyOb) = '1' ) then
               if ( got < 8 ) then
                  assert to_integer(unsigned(strmMstOb.data(7 downto 0))) = 2*2 + got severity failure;
                  if ( got = 7 ) then
                     assert strmMstOb.last = '1' severity failure;
                     strmRdyOb <= '0';
                  end if;
               else
                  assert to_integer(unsigned(strmMstOb.data(7 downto 0))) = 2*12 + 1 + (got - 8) severity failure;
                  if ( got = 8 ) then
                     assert strmMstOb.last = '1' severity failure;
                     strmRdyOb <= '0';
                  end if;
               end if;
               got := got + 1;
            end if;

            end if;
         end if;
      end if;
   end process;

   U_DUT : entity work.StrmFifoSync
      generic map (
         -- 18kb
         DEPTH_36kb  => false
      )
      port map (
         clk         => clk,
         rst         => rst,
         fifoRst     => fifoRst,

         strmMstIb   => strmMstIb,
         strmRdyIb   => strmRdyIb,

         emptySlots  => emptySlots,

         -- reformatted to *byte* stream; i.e., ben(1) is always '0'
         strmMstOb   => strmMstOb,
         strmRdyOb   => strmRdyOb
      );

end architecture Sim;

