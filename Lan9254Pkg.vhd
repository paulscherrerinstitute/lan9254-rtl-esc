library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;

package Lan9254Pkg is

   type Lan9254ReqType is record
      addr    : std_logic_vector(13 downto 0);
      wdata   : std_logic_vector(31 downto 0);
      be      : std_logic_vector( 3 downto 0);
      valid   : std_logic;
      rdnwr   : std_logic;
   end record Lan9254ReqType;

   constant LAN9254REQ_INIT_C : Lan9254ReqType := (
      addr    => (others => '0'),
      wdata   => (others => '0'),
      be      => (others => '0'),
      valid   => '0',
      rdnwr   => '1'
   );

   type Lan9254RepType is record
      valid   : std_logic;
      rdata   : std_logic_vector(31 downto 0);
      berr    : std_logic_vector( 0 downto 0);
   end record Lan9254RepType;

   constant LAN9254REP_INIT_C : Lan9254RepType := (
      valid   => '0',
      rdata   => (others => 'X'),
      berr    => (others => '1')
   );

   type Lan9254HBIOutType is record
      cs      : std_logic;
      be      : std_logic_vector(1 downto 0);
      rs      : std_logic;
      ws      : std_logic;
      ahi     : std_logic_vector(15 downto 0);
      ad      : std_logic_vector(15 downto 0);
      ad_t    : std_logic_vector(15 downto 0);
      ale     : std_logic_vector(1 downto 0);
      end_sel : std_logic;
   end record Lan9254HBIOutType;

   constant HBI_CS_ACT_C : std_logic := '0';
   constant HBI_BE_ACT_C : std_logic := '0';
   constant HBI_RS_ACT_C : std_logic := '0';
   constant HBI_WS_ACT_C : std_logic := '0';
   constant HBI_AL_ACT_C : std_logic := '0';

   constant LAN9254HBIOUT_INIT_C : Lan9254HBIOutType := (
      cs      => not HBI_CS_ACT_C,
      be      => (others => not HBI_BE_ACT_C),
      rs      => not HBI_RS_ACT_C,
      ws      => not HBI_WS_ACT_C,
      ahi     => (others => '0'),
      ad      => (others => '0'),
      ad_t    => (others => '1'),
      ale     => (others => not HBI_AL_ACT_C),
      end_sel => '0'
   );

   type Lan9254HBIInpType is record
      waitAck : std_logic;
      ad      : std_logic_vector(15 downto 0);
   end record Lan9254HBIInpType;

   constant LAN9254HBIINP_INIT_C : Lan9254HBIInpType := (
      waitAck => '1',
      ad      => (others => 'U')
   );

   procedure lan9254HBIRead(
      variable rdOut: inout Lan9254ReqType;
      signal   rdInp: in    Lan9254RepType;
      constant rdAdr: in    std_logic_vector(15 downto 0) := (others => '0');
      constant rdBEn: in    std_logic_vector(3 downto 0)  := "1111";
      constant enbl : in    boolean                       := true
   );

   procedure lan9254HBIWrite(
      variable wrOut: inout Lan9254ReqType;
      signal   wrInp: in    Lan9254RepType;
      constant wrAdr: in    std_logic_vector(15 downto 0) := (others => '0');
      constant wrDat: in    std_logic_vector(31 downto 0);
      constant wrBEn: in    std_logic_vector(3 downto 0)  := "1111";
      constant enbl : in    boolean                       := true
   );


   type IntArray is array(natural range <>) of integer;

   function max    (constant a: IntArray) return integer;
   function numBits(constant x: integer ) return integer;
   function initCnt(constant p: real    ) return natural;

end package Lan9254Pkg;

package body Lan9254Pkg is

   procedure lan9254HBIRead(
      variable rdOut: inout Lan9254ReqType;
      signal   rdInp: in    Lan9254RepType;
      constant rdAdr: in    std_logic_vector(15 downto 0) := (others => '0');
      constant rdBEn: in    std_logic_vector(3 downto 0) := "1111";
      constant enbl : in    boolean                      := true
   ) is
   begin
      if ( rdOut.valid = '0' ) then
         rdOut       := LAN9254REQ_INIT_C;
         rdOut.addr  := rdAdr(rdOut.addr'range);
         rdOut.be    := rdBEn;
         rdOut.rdnwr := '1';
         rdOut.valid := '1';
      else
         if ( rdInp.valid = '1' ) then
            rdOut.valid := '0';
         end if;
      end if;
   end procedure lan9254HBIRead;

   procedure lan9254HBIWrite(
      variable wrOut: inout Lan9254ReqType;
      signal   wrInp: in    Lan9254RepType;
      constant wrAdr: in    std_logic_vector(15 downto 0) := (others => '0');
      constant wrDat: in    std_logic_vector(31 downto 0);
      constant wrBEn: in    std_logic_vector(3 downto 0)  := "1111";
      constant enbl : in    boolean                       := true
   ) is
   begin
      if ( wrOut.valid = '0' ) then
         wrOut       := LAN9254REQ_INIT_C;
         wrOut.addr  := wrAdr(wrOut.addr'range);
         wrOut.be    := wrBEn;
         wrOut.wdata := wrDat;
         wrOut.rdnwr := '0';
         wrOut.valid := '1';
      else
         if ( wrInp.valid = '1' ) then
            wrOut.valid := '0';
         end if;
      end if;
   end procedure lan9254HBIWrite;


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
   begin
      if ( x = 0 ) then return 1; end if;
      return integer( floor( log2( real( x ) ) ) ) + 1;
   end function numBits;

   -- convert a real counter value to an 'natural' that can
   -- be used to initialize a counter.
   function initCnt(constant p : real) return natural is
      constant IVAL : integer := integer( ceil(p) ) - 1;
   begin
      return IVAL;
   end function initCnt;

end package body Lan9254Pkg;
