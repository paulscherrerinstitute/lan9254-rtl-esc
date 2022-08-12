
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

-- some basic types and functions that are used in various places

package ESCBasicTypesPkg is

   type     IntArray     is array(integer range <>) of integer;

   subtype  ESCVal16Type is std_logic_vector(15 downto 0);
   subtype  ESCVal08Type is std_logic_vector( 7 downto 0);

   type     Slv08Array   is array (integer range <>) of std_logic_vector( 7 downto 0);
   type     Slv16Array   is array (integer range <>) of std_logic_vector(15 downto 0);
   type     Slv32Array   is array (integer range <>) of std_logic_vector(31 downto 0);

   function max    (constant a: IntArray) return integer;
   function numBits(constant x: integer ) return integer;
   function initCnt(constant p: real    ) return natural;

   function toString(constant x : std_logic_vector) return string;
   function toString(constant x : unsigned        ) return string;

   function toSl(constant a: boolean) return std_logic;

   function toSlv(constant x: integer; constant l : natural) return std_logic_vector;

   function bswap(constant x: unsigned)         return unsigned;
   function bswap(constant x: std_logic_vector) return std_logic_vector;

   function slv08ArrayLen(constant x: Slv08Array) return natural;

   function ite(
      constant c: in boolean;
      constant a: in integer;
      constant b: in integer
   ) return integer;

   function ite(
      constant c: in boolean;
      constant a: in string;
      constant b: in string
   ) return string;

end package ESCBasicTypesPkg;

package body ESCBasicTypesPkg is

   function max(constant a: IntArray) return integer is
      variable m : integer;
   begin
      m := a(a'low);
      if ( a'ascending ) then
         for i in a'low + 1 to a'high loop
            if ( a(i) > m ) then
               m := a(i);
            end if;
         end loop;
      else
         for i in a'high downto a'low + 1 loop
            if ( a(i) > m ) then
               m := a(i);
            end if;
         end loop;
      end if;
      return m;
   end function max;

   function numBits(constant x : integer) return integer is
      variable rv : integer;
      variable  m : integer;
   begin
      m  := 2;
      rv := 1;
      while ( x > (m - 1) ) loop
         m  := m + m;
         rv := rv + 1;
      end loop;
      return rv;
-- *** I had ghdl ( v1.0.0/gcc ) produce floor(log2(real(8))) => 2 !
--      if ( x = 0 ) then return 1; end if;
--      return integer( floor( log2( real( x ) ) ) ) + 1;
   end function numBits;

   -- convert a real counter value to an 'natural' that can
   -- be used to initialize a counter.
   function initCnt(constant p : real) return natural is
      constant IVAL : integer := integer( ceil(p) ) - 1;
   begin
      return IVAL;
   end function initCnt;

   function toString(constant x : std_logic_vector)
   return string is
      variable s : string((x'length + 3)/4 - 1 downto 0);
      variable t : std_logic_vector(x'length + 3 downto 0);
      variable d : std_logic_vector(3 downto 0);
   begin
      t                        := (others => '0');
      t(x'length - 1 downto 0) := x;
      for i in 0 to s'length - 1 loop
         d := t(4*i+3 downto 4*i);
         if    ( d = x"0") then s(i) := '0';
         elsif ( d = x"1") then s(i) := '1';
         elsif ( d = x"2") then s(i) := '2';
         elsif ( d = x"3") then s(i) := '3';
         elsif ( d = x"4") then s(i) := '4';
         elsif ( d = x"5") then s(i) := '5';
         elsif ( d = x"6") then s(i) := '6';
         elsif ( d = x"7") then s(i) := '7';
         elsif ( d = x"8") then s(i) := '8';
         elsif ( d = x"9") then s(i) := '9';
         elsif ( d = x"A") then s(i) := 'A';
         elsif ( d = x"B") then s(i) := 'B';
         elsif ( d = x"C") then s(i) := 'C';
         elsif ( d = x"D") then s(i) := 'D';
         elsif ( d = x"E") then s(i) := 'E';
         elsif ( d = x"F") then s(i) := 'F';
         else                   s(i) := 'U';
         end if;
      end loop;
      return s;
   end function toString;

   function toString(constant x : unsigned)
   return string is
   begin
      return toString(std_logic_vector(x));
   end function toString;

   function toSl(constant a: boolean)
   return std_logic is
   begin
      if ( a ) then return '1'; else return '0'; end if;
   end function toSl;

   function bswap(constant x: std_logic_vector)
   return std_logic_vector is
      constant xd : std_logic_vector(x'high downto x'low) := x;
      variable vd : std_logic_vector(x'high downto x'low);
      variable v  : std_logic_vector(x'range);
      constant n  : integer := (x'length/8 - 1);
      constant l  : integer := x'left;
      constant r  : integer := x'left + n;

   begin
      assert x'length mod 8 = 0 report "vector must have length mod 8 = 0" severity failure;
      for i in 0 to x'length/8 - 1 loop
         vd(x'high - 8*i downto x'high - 8*i - 7) := xd(x'low + 8*i + 7 downto x'low + 8*i );
      end loop;
      v := vd;
      return v;
   end function bswap;

   function bswap(constant x: unsigned)
   return unsigned is
   begin
      return unsigned( bswap( std_logic_vector( x ) ) );
   end function bswap;

   function slv08ArrayLen(constant x: Slv08Array)
      return natural is
   begin
      return x'length;
   end function slv08ArrayLen;

   function ite(
      constant c: in boolean;
      constant a: in integer;
      constant b: in integer
   ) return integer is
   begin
      if ( c ) then return a; else return b; end if;
   end function ite;

   function ite(
      constant c: in boolean;
      constant a: in string;
      constant b: in string
   ) return string is
   begin
      if ( c ) then return a; else return b; end if;
   end function ite;

   function toSlv(
      constant x : integer;
      constant l : natural
   ) return std_logic_vector is
   begin
      return std_logic_vector( to_unsigned( x, l ) );
   end function toSlv;

end package body ESCBasicTypesPkg;
