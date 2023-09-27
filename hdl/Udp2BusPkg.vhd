------------------------------------------------------------------------------
--      Copyright (c) 2022-2023 by Paul Scherrer Institute, Switzerland
--      All rights reserved.
--  Authors: Till Straumann
--  License: PSI HDL Library License, Version 2.0 (see License.txt)
------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

package Udp2BusPkg is
   type Udp2BusReqType is record
      valid  : std_logic;
      dwaddr : std_logic_vector(29 downto 0); -- double-word address
      data   : std_logic_vector(31 downto 0);
      be     : std_logic_vector( 3 downto 0);
      rdnwr  : std_logic;
   end record Udp2BusReqType;

   constant UDP2BUSREQ_INIT_C : Udp2BusReqType := (
      valid  => '0',
      dwaddr => (others => '0'),
      data   => (others => '0'),
      be     => (others => '0'),
      rdnwr  => '1'
   );

   type Udp2BusRepType is record
      valid  : std_logic;
      rdata  : std_logic_vector(31 downto 0);
      berr   : std_logic;
   end record Udp2BusRepType;

   constant UDP2BUSREP_INIT_C : Udp2BusRepType := (
      valid  => '0',
      rdata  => (others => '0'),
      berr   => '0'
   );

   constant UDP2BUSREP_ERROR_C : Udp2BusRepType := (
      valid  => '1',
      rdata  => x"deadbeef",
      berr   => '1'
   );

   -- helper functions for byte-wide access

   -- returns value < 0 for an invalid combination of byte-enables
   subtype  Udp2BusAccessWidthType is integer range -1 to 4;

   function accessWidth(constant r : in Udp2BusReqType) return Udp2BusAccessWidthType;

   -- compute byte-address two least-significant bits based on 'be'.
   -- NOTE: this assumes a valid combination of byte-enables!
   function byteAddrLsbs(constant r : in Udp2BusReqType) return std_logic_vector;

   -- merge enabled lanes into a value
   -- (returns 'v' if not r.valid)
   procedure writeVal(
      variable v : inout std_logic_vector(31 downto 0);
      constant r : in    Udp2BusReqType
   );

   -- distribute readback value into register
   --
   procedure readVal(
      variable v      : inout std_logic_vector(31 downto 0);
      constant x      : in    std_logic_vector(15 downto 0)
   );

   procedure readVal(
      variable v      : inout std_logic_vector(31 downto 0);
      constant x      : in    std_logic_vector( 7 downto 0);
      constant hiOnly : in    boolean := false
   );

   type Udp2BusReqArray is array ( natural range <> ) of Udp2BusReqType;
   type Udp2BusRepArray is array ( natural range <> ) of Udp2BusRepType;

end package Udp2BusPkg;

package body Udp2BusPkg is

   -- merge enabled lanes into a value
   -- (returns 'v' if not r.valid)
   procedure writeVal(
      variable v : inout std_logic_vector(31 downto 0);
      constant r : in    Udp2BusReqType
   ) is
   begin
      v := v;
      for i in r.be'range loop
         if ( r.be(i) = '1' ) then
            v( 8*i + 7 downto 8*i ) := r.data( 8*i+7 downto 8*i );
         end if;
      end loop;
   end procedure writeVal;

   -- distribute readback value into register
   --
   procedure readVal(
      variable v      : inout std_logic_vector(31 downto 0);
      constant x      : in    std_logic_vector( 7 downto 0);
      constant hiOnly : in    boolean := false
   ) is
   begin
      v := v;
      if ( not hiOnly ) then
         v := x & x & x & x;
      else
         v(31 downto 24) := x;
         v(15 downto  8) := x;
      end if;
   end procedure readVal;

   procedure readVal(
      variable v      : inout std_logic_vector(31 downto 0);
      constant x      : in    std_logic_vector(15 downto 0)
   ) is
   begin
      v := x & x;
   end procedure readVal;

   function accessWidth(constant r : in Udp2BusReqType)
   return Udp2BusAccessWidthType is
   begin
      case ( r.be ) is
         when "0000"                            => return 0;
         when "0001" | "0010" | "0100" | "1000" => return 1;
         when "0011" | "1100"                   => return 2;
         when "1111"                            => return 4;
         when others                            => return -1;
      end case;
   end function accessWidth;

   function byteAddrLsbs(constant r : in Udp2BusReqType)
   return std_logic_vector is
   begin
      if    ( r.be(0) = '1' ) then
         return "00";
      elsif ( r.be(1) = '1' ) then
         return "01";
      elsif ( r.be(2) = '1' ) then
         return "10";
      elsif ( r.be(3) = '1' ) then
         return "11";
      else
         return "00";
      end if;
   end function byteAddrLsbs;

end package body Udp2BusPkg;
