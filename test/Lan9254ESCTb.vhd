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

use work.Lan9254Pkg.all;

entity Lan9254ESCTb is
end entity Lan9254ESCTb;

-- Test-bed for Lan9254ESC; this is a basic test bed.
-- More comprehensive testing is possible using Lan9254ESCrun.vhd
-- which implements a simulation that talks to the actual
-- LAN9254 hardware.

architecture rtl of Lan9254ESCTb is
   signal clk : std_logic := '0';
   signal rst : std_logic := '0';
   signal run : boolean   := true;

   signal req : Lan9254ReqType := LAN9254REQ_INIT_C;
   signal rep : Lan9254RepType := LAN9254REP_INIT_C;

   signal al  : std_logic_vector(31 downto 0) := x"0000_0002";
   signal as  : std_logic_vector(31 downto 0) := x"0000_0001";

   signal ereq : std_logic_vector(31 downto 0) := x"0000_0001"; -- signal initial control update request

begin

   process is begin
      if ( run ) then
         wait for 10 us;
         clk <= not clk;
      else
         wait;
      end if;
   end process;

   process ( clk ) is
      variable d : std_logic_vector(31 downto 0);
      variable a : std_logic_vector(15 downto 0);
   begin
      d := (others => '0');
      if ( rising_edge( clk ) ) then
         rep.valid <= '0';
         if ( req.valid = '1' ) then
            a := "00" & std_logic_vector( req.addr );
            rep.valid <= '1';
            if ( req.rdnwr = '1' ) then
               case ( a ) is
                  when x"0220" => rep.rdata <= ereq; -- AL EREQ
                                  ereq      <= (others => '0');
                  when x"3064" => rep.rdata <= x"87654321";
                  when x"3074" => rep.rdata <= (27 => '1', others => '0'); -- signal device ready
                  when x"0120" => rep.rdata <= al;

                                  -- that's as far as we go
                                  report "TEST PASSED";
                                  run       <= false;

                  when x"0500" => rep.rdata <= ( 21 => '1', others => '0'); -- eemu active (not supported anyways)
                  when others  => assert false report "unexpected register access" severity failure;
               end case;
            else
               case ( a ) is
                  when x"0130" => as <= req.data;
                                  assert req.data = x"00000001" report "unexpected AL_STAT" severity failure;
                  when x"0134" => assert req.data = x"00000000" report "unexpected AL_ERRO" severity failure;
                  when x"0204" =>  -- AL event mask; should we verify the contents?
                  when x"305C" =>  -- IRQ-ENA; should we verify ?
                  when x"3054" =>  -- IRQ-CFG; should we verify ?
                  when others  => assert false report "unexpected register access" severity failure;
               end case;
            end if;
         end if;
      end if;
   end process;

   U_DUT : entity work.Lan9254ESC
      generic map (
         CLK_FREQ_G           => 10.0E3,
         REG_IO_TEST_ENABLE_G => false
      )
      port map (
         clk         => clk,
         rst         => rst,

         req         => req,
         rep         => rep
      );

end architecture rtl;
