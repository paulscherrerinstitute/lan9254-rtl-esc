------------------------------------------------------------------------------
--      Copyright (c) 2022-2023 by Paul Scherrer Institute, Switzerland
--      All rights reserved.
--  Authors: Till Straumann
--  License: PSI HDL Library License, Version 2.0 (see License.txt)
------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Lan9254Pkg.all;
use     work.Udp2BusPkg.all;


entity Udp2BusTb is
end entity Udp2BusTb;

architecture sim of Udp2BusTb is

   type TstArray is array (natural range <>) of std_logic_vector(16 downto 0);
   type ExpArray is array (natural range <>) of std_logic_vector(17 downto 0);
   type DatArray is array (natural range <>) of std_logic_vector(31 downto 0);


   signal clk            : std_logic := '0';
   signal rst            : std_logic := '0';
   signal run            : boolean   := true;

   signal strmMstIb      : Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
   signal strmRdyIb      : std_logic;
   signal strmMstOb      : Lan9254StrmMstType;
   signal strmRdyOb      : std_logic          := '0';

   signal req            : Udp2BusReqType;
   signal rep            : Udp2BusRepType     := UDP2BUSREP_INIT_C;

   constant tstVec       : TstArray := (
      -- invalid command
        "0" & x"0000"
      , "1" & x"0000"
      -- version with payload
      , "0" & x"0012"
      , "0" & x"cafe"
      , "1" & x"beef"
      -- read commands
      , "0" & x"0121"
      , "0" & x"0000"
      , "0" & x"8000"
      , "0" & x"0000"
      , "0" & x"9000"
      , "0" & x"0000"
      , "0" & x"a000"
      , "0" & x"0000"
      , "0" & x"b000"
      , "0" & x"0001"
      , "0" & x"c000"
      , "0" & x"0001"
      , "0" & x"d000"
      , "0" & x"0002"
      , "1" & x"f000"
      -- read with error
      , "0" & x"0221"
      , "0" & x"0000"
      , "0" & x"8000"
      , "0" & x"1000"
      , "0" & x"9000"
      , "0" & x"0000"
      , "0" & x"a000"
      , "0" & x"0000"
      , "1" & x"b000"
      -- replay read with error
      , "0" & x"0221"
      , "0" & x"0000"
      , "0" & x"8000"
      , "0" & x"1000"
      , "0" & x"9000"
      , "0" & x"0000"
      , "0" & x"a000"
      , "0" & x"0000"
      , "1" & x"b000"
      -- read with incomplete command
      , "0" & x"0321"
      , "1" & x"0000"
      -- exercise write commands
      , "0" & x"0421"
      , "0" & x"0000"
      , "0" & x"0000"
      , "0" & x"00a0"
      , "0" & x"0001"
      , "0" & x"1000"
      , "0" & x"00b0"
      , "0" & x"0002"
      , "0" & x"2000"
      , "0" & x"00C0"
      , "0" & x"0003"
      , "0" & x"3000"
      , "0" & x"00D0"
      , "0" & x"0004"
      , "0" & x"4000"
      , "0" & x"4321"
      , "0" & x"0005"
      , "0" & x"5000"
      , "0" & x"8765"
      , "0" & x"0006"
      , "0" & x"6000"
      , "0" & x"cafe"
      , "1" & x"affe"
      -- try bursts
      -- read burst
      , "0" & x"0521"
      , "0" & x"0000"
      , "1" & x"8020"
      -- write bursts
      , "0" & x"0621"
      , "0" & x"0008"
      , "0" & x"5030"
      , "0" & x"aaaa"
      , "0" & x"bbbb"
      , "0" & x"cccc"
      , "0" & x"dddd"
      , "0" & x"000C"
      , "0" & x"6010"
      , "0" & x"fafa"
      , "0" & x"caca"
      , "0" & x"bebe"
      , "0" & x"feef"
      , "0" & x"0008"
      , "0" & x"0010"
      , "0" & x"FF02"
      , "0" & x"FF01"
      , "0" & x"000A"
      , "0" & x"2030"
      , "0" & x"FF04"
      , "0" & x"FF03"
      , "0" & x"FF08"
      , "1" & x"FF07"
);

   constant expVec       : ExpArray := (
        "1" & x"0001" & "0"
      , "1" & x"0011" & "0"
      , "0" & x"0121" & "0"
      , "0" & x"0004" & "1" -- '1' flags that we only compare LSByte
      , "0" & x"0003" & "1"
      , "0" & x"0002" & "1"
      , "0" & x"0001" & "1"
      , "0" & x"ccdd" & "0"
      , "0" & x"aabb" & "0"
      , "0" & x"0708" & "0"
      , "0" & x"0506" & "0"
      , "1" & x"0007" & "0"
      , "0" & x"0221" & "0"
      , "0" & x"0004" & "1"
      , "1" & x"8001" & "0"
      , "0" & x"0221" & "0"
      , "0" & x"0004" & "1"
      , "1" & x"8001" & "0"
      , "0" & x"0321" & "0"
      , "1" & x"8000" & "0"
      , "0" & x"0421" & "0"
      , "1" & x"0007" & "0"
      , "0" & x"0521" & "0"
      , "0" & x"00A0" & "1"
      , "0" & x"0003" & "1"
      , "0" & x"0002" & "1"
      , "1" & x"0003" & "0"
      , "0" & x"0621" & "0"
      , "1" & x"000c" & "0"
   );

   signal wrIdx          : natural := 0;
   signal rdIdx          : natural := 0;

   signal datVec         : DatArray(0 to 15) := (
      x"01020304",
      x"aabbccdd",
      x"05060708",
      x"eeff0011",
      x"090a0b0c",
      x"deadbeef",
      x"0d0e0f10",
      others => (others => '0')
   );

   constant datExp       : DatArray := (
        x"010203A0"
      , x"aabbB0dd"
      , x"05C00708"
      , x"D0ff0011"
      , x"090a4321"
      , x"8765beef"
      , x"affecafe"

      , x"00000000"

      , x"aaaa0102"
      , x"ccccbbbb"
      , x"0304dddd"
      , x"00000708"
      , x"cacafafa"
      , x"feefbebe"
   );

begin
   P_CLK : process is
   begin
      if ( run ) then
         wait for 5 us;
         clk <= not clk;
      else
         wait;
      end if;
   end process P_CLK;

   strmMstIb.ben  <= "11";
   strmMstIb.data <= tstVec(wrIdx)(15 downto 0) when wrIdx < tstVec'length else (others => 'X');
   strmMstIb.last <= tstVec(wrIdx)(16)          when wrIdx < tstVec'length else 'X';

   P_PLAY : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( strmMstIb.valid = '0' and wrIdx < tstVec'length ) then
            strmMstIb.valid <= '1';
         elsif ( ( strmMstIb.valid and strmRdyIb ) = '1' ) then
            strmMstIb.valid <= '0';
            wrIdx           <= wrIdx + 1;
         end if;
      end if;
   end process P_PLAY;

   P_CHECK_STRM : process ( clk ) is
      variable d : std_logic_vector(15 downto 0);
   begin
      if ( rising_edge( clk ) ) then
         strmRdyOb <= '1';
         if ( ( strmMstOb.valid and strmRdyOb ) = '1' ) then
            if ( expVec(rdIdx)(0) = '1' ) then
               d := x"00" & strmMstOb.data(7 downto 0);
            else
               d := strmMstOb.data;
            end if;
            assert d              = expVec(rdIdx)(16 downto 1) report "stream data mismatch" severity failure;
            assert strmMstOb.last = expVec(rdIdx)(         17) report "stream last mismatch" severity failure;
            assert strmMstOb.ben  = "11"                       report "stream ben  mismatch" severity failure;
            if ( rdIdx = expVec'high ) then
               run   <= false;
               for i in datExp'range loop
                  assert datVec(i) = datExp(i) report "write data mismatch @ word " & integer'image(i) severity failure;
               end loop;
               report "Test PASSED";
            else
               rdIdx <= rdIdx + 1;
            end if;
         end if;
      end if;
   end process P_CHECK_STRM;


   P_MEM : process ( clk ) is
      variable a : natural;
      variable m : std_logic_vector(31 downto 0);
      variable x : std_logic_vector(31 downto 0);
      variable b : std_logic;
   begin
      if ( rising_edge( clk ) ) then
         rep.valid <= '0';
         if ( ( req.valid = '1' ) and ( rep.valid = '0' ) ) then
            a := to_integer( unsigned( req.dwaddr ) );
            x := (others => 'X');
            for i in req.be'range loop
               m( (i+1)*8 - 1 downto i*8 ) := (others => req.be(i));
            end loop;
            if ( a >= datVec'length ) then
               rep.berr <= '1';
            else
               rep.berr <= '0';
               if ( req.rdnwr = '1' ) then
                  rep.rdata <= (datVec(a) and m) or (x and not m);
               else
                  datVec(a) <= (req.data and m) or (datVec(a) and not m);
               end if;
            end if;
            rep.valid <= '1';
         end if;
      end if;
   end process P_MEM;

   U_DUT : entity work.Udp2Bus
      generic map (
         MAX_FRAME_SIZE_G => 128
      )
      port map (
         clk       => clk,
         rst       => rst,

         req       => req,
         rep       => rep,

         strmMstIb => strmMstIb,
         strmRdyIb => strmRdyIb,

         strmMstOb => strmMstOb,
         strmRdyOb => strmRdyOb,

         frameSize => open
      );
end architecture sim;
