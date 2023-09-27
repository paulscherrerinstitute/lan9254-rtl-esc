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
use work.ESCMbxPkg.all;

entity StrmFrameBufTb is
end entity StrmFrameBufTb;

architecture sim of StrmFrameBufTb is

   signal    clk    : std_logic := '0';
   signal    rst    : std_logic := '0';

   signal strmMstIb : Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
   signal strmRdyIb : std_logic          := '1';
   signal strmMstOb : Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
   signal strmRdyOb : std_logic          := '1';

   signal frameSz   : unsigned(10 downto 0);

   signal cnt       : unsigned(10 downto 0) := (others => '0');
   signal run       : boolean               := true;

   signal rframno   : natural               := 0;
   signal rwrdno    : natural               := 0;

   signal tframno   : natural               := 0;
   signal twrdno    : natural               := 0;

   signal rdylo     : natural               := 0;
   signal restore   : std_logic_vector(2 downto 0) := "000";

   type   FramType  is array (natural range 0 to 8) of std_logic_vector(18 downto 0);
   type   FramArray is array (natural range <>) of FramType;

   constant tstvec  : FramArray := (
      0 => (
         0 => "011" & x"0001",
         1 => "011" & x"0002",
         2 => "111" & x"0003",
         others => (others => '0')
      ),
      1 => (
         0 => "011" & x"0008",
         1 => "011" & x"0009",
         2 => "011" & x"000a",
         3 => "101" & x"000b",
         others => (others => '0')
      ),
      2 => (
         0 => "011" & x"0018",
         1 => "011" & x"0019",
         2 => "011" & x"001a",
         3 => "101" & x"001b",
         others => (others => '0')
      ),
      3 => (
         0 => "011" & x"0028",
         1 => "011" & x"0029",
         2 => "011" & x"002a",
         3 => "111" & x"002b",
         others => (others => '0')
      )
   );


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

   strmMstIb.data  <= tstvec(tframno)(twrdno)(15 downto  0);
   strmMstIb.ben   <= tstvec(tframno)(twrdno)(17 downto 16);
   strmMstIb.last  <= tstvec(tframno)(twrdno)(18);

   P_FEED : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( tframno = 0 and twrdno = 0 ) then
            strmMstIb.valid <= '1';
         end if;
         if ( ( strmMstIb.valid and strmRdyIb ) = '1' ) then
            if ( strmMstIb.last = '1' ) then
               if ( tframno = tstvec'high ) then
                  strmMstIb.valid <= '0';
               else
                  tframno         <= tframno + 1;
                  twrdno          <= 0;
               end if;
            else
               twrdno             <= twrdno + 1;
            end if;
         end if;
      end if;
   end process P_FEED;

   U_DUT : entity work.StrmFrameBuf
      port map (
         clk                 => clk,
         rst                 => rst,

         restore             => restore(0),

         strmMstIb           => strmMstIb,
         strmRdyIb           => strmRdyIb,

         frameSize           => frameSz,
         strmMstOb           => strmMstOb,
         strmRdyOb           => strmRdyOb
      );

   P_CMP : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         -- delay pipeline for restore
         restore <= restore(1) & restore(0) & restore(0);
         if ( ( strmMstOb.valid and strmRdyOb ) = '1' ) then
            assert strmMstOb.data = tstvec(rframno)(rwrdno)(15 downto  0) 
               report "data mismatch @ frame " & integer'image(rframno) & "[" & integer'image(rwrdno) & "]"
               severity failure;
            assert strmMstOb.ben  = tstvec(rframno)(rwrdno)(17 downto 16) 
               report "BE   mismatch @ frame " & integer'image(rframno) & "[" & integer'image(rwrdno) & "]"
               severity failure;
            assert strmMstOb.last = tstvec(rframno)(rwrdno)(18)
               report "LAST mismatch @ frame " & integer'image(rframno) & "[" & integer'image(rwrdno) & "]"
               severity failure;
            if ( strmMstOb.last = '1' ) then
               assert to_integer(frameSz) = 2*rwrdno + 1 + to_integer(unsigned(strmMstOb.ben(1 downto 1)))
                  report "size mismatch @ frame " & integer'image(rframno) & "[" & integer'image(rwrdno) & "]"
                  severity failure;
               if ( rframno = tstvec'high ) then
                  if ( restore(0) = '1' ) then
                     restore <= "000";
                     report "TEST PASSED";
                     run    <= false;
                  else
                     restore(0) <= '1';
                     rwrdno     <= 0;
                  end if;
               else
                  rframno <= rframno + 1;
                  rwrdno  <= 0;
               end if;
            else
               rwrdno  <= rwrdno + 1;
            end if;
         end if;
      end if;
   end process P_CMP;

   P_RDY : process ( rdylo, restore ) is
   begin
      if ( rdylo /= 0 or ( restore /= "000" and restore /= "111" ) ) then
         strmRdyOb <= '0';
      else
         strmRdyOb <= '1';
      end if;
   end process P_RDY;


   P_RDYFLASH : process ( clk ) is
   begin
      if ( rising_edge ( clk ) ) then
         if ( rdylo /= 0 ) then
            rdylo <= rdylo - 1;
         else
            if ( rframno = 1 and rwrdno = 1 ) then
               rdylo <= 1;
            end if;
            if ( rframno = 0 and rwrdno = 1 ) then
               rdylo <= 2;
            end if;
            if ( rframno = 1 and ( strmMstOb.valid = '1' ) ) then
               rdylo <= 3;
            end if;
         end if;
      end if;
   end process P_RDYFLASH;

end architecture sim;
