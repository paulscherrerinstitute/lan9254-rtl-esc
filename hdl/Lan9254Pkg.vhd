library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

-- General types, definitions and helpers for supporting
-- the lan9254 in multiplexed, directly-mapped 16-bit HBI
-- mode.
-- The focus of this package are HBI bus transactions.

package Lan9254Pkg is

   type Lan9254ReqType is record
      addr    : std_logic_vector(13 downto 0);
      wdata   : std_logic_vector(31 downto 0);
      be      : std_logic_vector( 3 downto 0);
      valid   : std_logic;
      rdnwr   : std_logic;
      noAck   : std_logic; -- waitAck not operational; must use timeout
   end record Lan9254ReqType;

   constant LAN9254REQ_INIT_C : Lan9254ReqType := (
      addr    => (others => '0'),
      wdata   => (others => '0'),
      be      => (others => '0'),
      valid   => '0',
      rdnwr   => '1',
      noAck   => '0'
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

   type Lan9254PDOMstType is record
      wrdAddr : unsigned(12 downto 0);
      data    : std_logic_vector(15 downto 0);
      valid   : std_logic;
      ben     : std_logic_vector(1 downto 0);
      last    : std_logic;
   end record Lan9254PDOMstType;

   constant LAN9254PDO_MST_INIT_C : Lan9254PDOMstType := (
      wrdAddr => (others => '0'),
      data    => (others => 'X'),
      valid   => '0',
      ben     => (others => '0'),
      last    => '0'
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

   constant HBI_BE_B0_C  : std_logic_vector(3 downto 0) := (
      3 => not HBI_BE_ACT_C, 2 => not HBI_BE_ACT_C, 1 => not HBI_BE_ACT_C, 0 =>     HBI_BE_ACT_C
   );

   constant HBI_BE_B1_C  : std_logic_vector(3 downto 0) := (
      3 => not HBI_BE_ACT_C, 2 => not HBI_BE_ACT_C, 1 =>     HBI_BE_ACT_C, 0 => not HBI_BE_ACT_C
   );

   constant HBI_BE_B2_C  : std_logic_vector(3 downto 0) := (
      3 => not HBI_BE_ACT_C, 2 =>     HBI_BE_ACT_C, 1 => not HBI_BE_ACT_C, 0 => not HBI_BE_ACT_C
   );

   constant HBI_BE_B3_C  : std_logic_vector(3 downto 0) := (
      3 =>     HBI_BE_ACT_C, 2 => not HBI_BE_ACT_C, 1 => not HBI_BE_ACT_C, 0 => not HBI_BE_ACT_C
   );

   constant HBI_BE_W1_C : std_logic_vector(3 downto 0) := (
      3 =>     HBI_BE_ACT_C, 2 =>     HBI_BE_ACT_C, 1 => not HBI_BE_ACT_C, 0 => not HBI_BE_ACT_C
   );

   constant HBI_BE_W0_C : std_logic_vector(3 downto 0) := (
      3 => not HBI_BE_ACT_C, 2 => not HBI_BE_ACT_C, 1 =>     HBI_BE_ACT_C, 0 =>     HBI_BE_ACT_C
   );

   constant HBI_BE_DW_C : std_logic_vector(3 downto 0) := (
      others => HBI_BE_ACT_C
   );

   -- ACK-level; while this theoretically may be programmed in the EEPROM
   -- not all settings are possible:
   --   wait-polarity    : 1/0  (ACK is the complement)
   --   driver open drain: 1/0  (0   is push-pull)
   -- HOWEVER: the '00' setting *disables* wait-ack alltogether (lan9252
   --          compatibility.
   -- Therefore, in a push-pull configuration only wait-polarity = '1' (=> ACK = '0')
   -- is possible.
   -- NOTE/UPDATE -- the documentation seems incorrect: my experiments with external
   --                pull-ups and pull-downs (implemented in the fpga) show the
   --                following behaviour:
   --      pol. (Reg150[1])  driver (Reg150[0])
   --              1               1              ack => '0', wait => '1'   (pullup-enabled)
   --              1               0              ack => '1', wait => '0'   (pullup-enabled)
   --              0               1              ack => '1', wait => '0'   (pullup-enabled)
   --              0               0              disabled  (always '1' with pullup-enabled)
   --              0               0              disabled  (always '0' with pulldown)
   --              0               1              ack => '1', wait => '0'   (pulldown)
   --              1               0              always '0' (pulldown-enabled)
   --              1               1              ack => '0', wait => '1' (pulldown enabled)
   --
   -- Hence, it seems the functionality is
   --
   --     Reg150[1:0]
   --          00  => disabled
   --          01  => ack=1, wait=0, push-pull
   --          10  => ack=1, wait=0, open-drain
   --          11  => ack=0, wait=1, push-pull
   --
   -- (makes kind of sense that the open-drain + wait=1 combination is the one
   -- that cannot be chosen - this wouldn't be useful for a wired-or type of
   -- configuration where multiple sources can indicate 'wait').
   --
   -- Furthermore, in EEPROM emulation mode wait/ack is not available at all until
   -- the config bytes are loaded.
   -- Therefore, we provide an enable/disable functionality as well as a timeout
   --
   constant WAITb_ACK_C : std_logic := '1'; -- set eeprom to 01 (push-pull) or 10 (open-drain)

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
      waitAck => (not WAITb_ACK_C),
      ad      => (others => 'U')
   );

   procedure lan9254HBIRead(
      variable rdOut: inout Lan9254ReqType;
      signal   rdInp: in    Lan9254RepType;
      constant rdAdr: in    std_logic_vector(15 downto 0) := (others => '0');
      constant rdBEn: in    std_logic_vector(3 downto 0)  := (others => HBI_BE_ACT_C);
      constant enbl : in    boolean                       := true
   );

   procedure lan9254HBIWrite(
      variable wrOut: inout Lan9254ReqType;
      signal   wrInp: in    Lan9254RepType;
      constant wrAdr: in    std_logic_vector(15 downto 0) := (others => '0');
      constant wrDat: in    std_logic_vector(31 downto 0);
      constant wrBEn: in    std_logic_vector(3 downto 0)  := (others => HBI_BE_ACT_C);
      constant enbl : in    boolean                       := true
   );


   type IntArray is array(natural range <>) of integer;

   function max    (constant a: IntArray) return integer;
   function numBits(constant x: integer ) return integer;
   function initCnt(constant p: real    ) return natural;

   function toString(constant x : std_logic_vector) return string;

end package Lan9254Pkg;

package body Lan9254Pkg is

   function adjReq(
      constant rdAdr: in    std_logic_vector(15 downto 0) := (others => '0');
      constant bena : in    std_logic_vector( 3 downto 0) := (others => HBI_BE_ACT_C);
      constant rdnwr: in    std_logic                     := '1';
      constant data : in    std_logic_vector(31 downto 0) := (others => '0')
   ) return Lan9254ReqType is
      variable rv : Lan9254ReqType;
   begin
      rv       := LAN9254REQ_INIT_C;
      rv.addr  := rdAdr(rv.addr'high downto 2) & "00";
      rv.be    := bena;
      rv.wdata := data;
      rv.rdnwr := rdnwr;
      rv.valid := '1';
      if    ( rdAdr(1 downto 0) = "11" ) then
         rv.be    := ( 3 => bena(0), others => not HBI_BE_ACT_C );
         rv.wdata := data  ( 7 downto 0) & x"00_0000";
      elsif ( rdAdr(1 downto 0) = "10" ) then
         rv.be( 3 downto 2 ) := bena(1 downto 0);
         rv.be( 1 downto 0)  := (others => not HBI_BE_ACT_C);
         rv.wdata := data  (15 downto 0) & x"0000";
      elsif ( rdAdr(1 downto 0) = "01" ) then
         rv.be    := bena  ( 2 downto 0) & not HBI_BE_ACT_C;
         rv.wdata := data  (23 downto 0) & x"00";
      end if;
      return rv;
   end function adjReq;

   function adjRep(
      constant req : in Lan9254ReqType;
      constant rep : in Lan9254RepType
   ) return std_logic_vector is
      variable v : std_logic_vector(31 downto 0);
   begin
      v := rep.rdata;
      if    ( req.be(2 downto 0) = not (HBI_BE_ACT_C & HBI_BE_ACT_C & HBI_BE_ACT_C) ) then
         v := x"0000_00" & rep.rdata(31 downto 24);
      elsif ( req.be(1 downto 0) = not (HBI_BE_ACT_C & HBI_BE_ACT_C) ) then
         v := x"0000" & rep.rdata(31 downto 16);
      elsif ( req.be(0) = not HBI_BE_ACT_C ) then
         v := x"00" & rep.rdata(31 downto  8);
      end if;
      return v;
   end function adjRep;

   procedure lan9254HBIRead(
      variable rdOut: inout Lan9254ReqType;
      signal   rdInp: in    Lan9254RepType;
      constant rdAdr: in    std_logic_vector(15 downto 0) := (others => '0');
      constant rdBEn: in    std_logic_vector(3 downto 0)  := (others => HBI_BE_ACT_C);
      constant enbl : in    boolean                       := true
   ) is
   begin
      if ( rdOut.valid = '0' ) then
         rdOut := adjReq(rdAdr, rdBEn, '1');
--report "HBIRead sched from " & toString(rdOut.addr) & " BE " & toString(rdOut.be) & " (be in " & toString(rdBEn) &")";
      else
         if ( rdInp.valid = '1' ) then
            rdOut.valid := '0';
            rdOut.wdata := adjRep( rdOut, rdInp );
--report "HBIRead from " & toString(rdOut.addr) & " BE " & toString(rdOut.be) & " GOT " & toString(rdOut.wdata) & " (rdata " & toString(rdInp.rdata) &")";
         end if;
      end if;
   end procedure lan9254HBIRead;

   procedure lan9254HBIWrite(
      variable wrOut: inout Lan9254ReqType;
      signal   wrInp: in    Lan9254RepType;
      constant wrAdr: in    std_logic_vector(15 downto 0) := (others => '0');
      constant wrDat: in    std_logic_vector(31 downto 0);
      constant wrBEn: in    std_logic_vector(3 downto 0)  := (others => HBI_BE_ACT_C);
      constant enbl : in    boolean                       := true
   ) is
   begin
      if ( wrOut.valid = '0' ) then
         wrOut       := adjReq(wrAdr, wrBEn, '0', wrDat);
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

end package body Lan9254Pkg;