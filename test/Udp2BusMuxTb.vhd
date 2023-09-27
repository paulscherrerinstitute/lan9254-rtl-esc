------------------------------------------------------------------------------
--      Copyright (c) 2022-2023 by Paul Scherrer Institute, Switzerland
--      All rights reserved.
--  Authors: Till Straumann
--  License: PSI HDL Library License, Version 2.0 (see License.txt)
------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Udp2BusPkg.all;


entity Udp2BusMuxTb is
end entity Udp2BusMuxTb;

architecture sim of Udp2BusMuxTb is

   constant NUM_MSTS_C   : natural := 2;
   constant NUM_SUBS_C   : natural := 2;

   signal clk            : std_logic := '0';
   signal rst            : std_logic := '0';
   signal run            : unsigned(NUM_MSTS_C - 1 downto 0) := (others => '1');

   signal reqIb          : Udp2BusReqArray( NUM_MSTS_C - 1 downto 0);
   signal repIb          : Udp2BusRepArray( NUM_MSTS_C - 1 downto 0);

   signal reqOb          : Udp2BusReqArray( NUM_SUBS_C - 1 downto 0);
   signal repOb          : Udp2BusRepArray( NUM_SUBS_C - 1 downto 0);

begin

   P_CLK : process is
   begin
      if ( run /= 0 ) then
         wait for 5 us;
         clk <= not clk;
      else
         wait;
      end if;
   end process P_CLK;

   G_SUBS : for i in 0 to NUM_SUBS_C - 1 generate
      type RegsType is array(1 downto 0) of std_logic_vector(31 downto 0);

      signal r : RegsType := (
         0 => (others => '0'),
         1 => std_logic_vector( to_unsigned( i, 32 ) )
      );

      signal rep : Udp2BusRepType := UDP2BUSREP_INIT_C;
      signal vld : std_logic;
      signal dly : integer        := -1;

   begin

      P_RD  : process (reqOb, rep, r, vld) is
      begin
         repOb(i)       <= rep;
         repOb(i).valid <= vld;
         repOb(i).rdata <= (others => 'X');
         repOb(i).berr  <= '1';
         if ( ( reqOb(i).valid and reqOb(i).rdnwr and vld ) = '1' ) then
            repOb(i).rdata <= r(to_integer(unsigned(reqOb(i).dwaddr(0 downto 0))));
            repOb(i).berr  <= '0';
         end if;
      end process P_RD;

      G_NO_DLY : if ( i = 0 ) generate
         vld <= reqOb(i).valid;
      end generate G_NO_DLY;

      G_DLY : if ( i /= 0 ) generate
         vld <= '1' when dly = 0 else '0';
      end generate G_DLY;

      P_SUB : process ( clk ) is
      begin
         if ( rising_edge( clk ) ) then
            if ( dly >= 0 ) then
               dly <= dly - 1;
            end if;
            if ( reqOb(i).valid = '1' ) then
               if ( dly < 0 ) then
                  dly <= i - 1;
               end if;
               if ( reqOb(i).rdnwr = '0' ) then
                  for j in reqOb(i).be'range loop
                     if ( reqOb(i).be(j) = '1' ) then
                        r( to_integer(unsigned(reqOb(i).dwaddr(0 downto 0))) )(7 + 8*j downto 8*j) <= reqOb(i).data(7 + 8*j downto 8*j);
                     end if;
                  end loop;
               end if;
            end if;
         end if;
      end process P_SUB;
   end generate G_SUBS;

   G_MST : for i in 0 to NUM_MSTS_C - 1 generate
      signal req  : Udp2BusReqType := UDP2BUSREQ_INIT_C;
      signal phas : natural        := 0; 
      constant pre : signed(31 downto 0) := x"0dead000";
   begin
      reqIb(i) <= req;

      P_MST : process ( clk ) is
      begin
         if ( rising_edge ( clk ) ) then
            if ( phas = 0 and req.valid = '0' ) then
               req.be        <= "1111";
               req.valid     <= '1';
               req.rdnwr     <= '1';
               req.dwaddr    <= (0 => '1', others => '0');
               if ( i = 1 ) then
                  req.dwaddr(1) <= '1';
               end if;
            end if;
               
            if ( ( repIb(i).valid and req.valid ) = '1' ) then
               assert unsigned(req.dwaddr(req.dwaddr'left downto 2)) = 0 report "dwaddr unexpected" severity failure;
               if ( req.rdnwr = '1' ) then
                  if ( req.dwaddr(0) = '1' ) then
                     assert repIb(i).berr = '0' and to_integer(unsigned(repIb(i).rdata)) = to_integer(unsigned(req.dwaddr(1 downto 1))) report "readback mismatch" severity failure;
                  else
                     assert repIb(i).berr = '0' and to_integer(unsigned(repIb(i).rdata)) = to_integer(pre) + i report "readback mismatch" severity failure;
                  end if;
                  report "Readback master " & integer'image(i) & " PASSED";
               end if;
               phas <= phas + 1;
               if ( phas = 0 ) then
                  req.dwaddr(0) <= '0';
                  req.rdnwr     <= '0';
                  req.data      <= std_logic_vector(pre + i);
               elsif ( phas = 1 ) then
                  req.rdnwr     <= '1';
                  req.data      <= (others => 'X');
               else
                  req.valid     <= '0';  
                  run(i)        <= '0';
               end if;
            end if;
         end if;
      end process P_MST;

   end generate G_MST;

   U_DUT : entity work.Udp2BusMux
      generic map (
         ADDR_MSB_G       => 1,
         ADDR_LSB_G       => 1,
         NUM_MSTS_G       => NUM_MSTS_C,
         NUM_SUBS_G       => NUM_SUBS_C
      )
      port map (
         clk       => clk,
         rst       => rst,

         reqIb     => reqIb,
         repIb     => repIb,

         reqOb     => reqOb,
         repOb     => repOb
      );
end architecture sim;
