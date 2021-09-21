library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.Lan9254Pkg.all;
use work.Lan9254ESCPkg.all;
use work.EEEmulPkg.all;
use work.EEPROMContentPkg.all;

-- ESC Core; ESC state machine interfacing to the LAN9254 controller

use work.IlaWrappersPkg.all;

entity Lan9254ESC is
   generic (
      CLK_FREQ_G              : real;
      TXPDO_MAX_UPDATE_FREQ_G : real    := 5.0E3;
      REG_IO_TEST_ENABLE_G    : boolean := true
   );
   port (
      clk         : in  std_logic;
      rst         : in  std_logic;

      req         : out Lan9254ReqType;
      rep         : in  Lan9254RepType    := LAN9254REP_INIT_C;

      escState    : out ESCStateType;
      debug       : out std_logic_vector(23 downto 0);

      txPDOMst    : in  Lan9254PDOMstType := LAN9254PDO_MST_INIT_C;
      txPDORdy    : out std_logic;

      rxPDOMst    : out Lan9254PDOMstType;
      rxPDORdy    : in  std_logic := '1';

      irq         : in  std_logic := EC_IRQ_ACT_C; -- defaults to polling mode

      testFailed  : out std_logic_vector(4 downto 0)
   );
end entity Lan9254ESC;

architecture rtl of Lan9254ESC is

   signal eeprom : EEPromArray(EEPROM_INIT_C'range) := EEPROM_INIT_C;

   constant TXPDO_UPDATE_DECIMATION_C : natural := integer(CLK_FREQ_G/TXPDO_MAX_UPDATE_FREQ_G);

   type ControllerState is (
      TEST,
      INIT,
      POLL_IRQ,
      POLL_AL_EVENT,
      HANDLE_AL_EVENT,
      HANDLE_WD_EVENT,
      READ_AL,
      EEP_EMUL,
      EEP_READ,
      EEP_WRITE,
      EVALUATE_TRANSITION,
      XACT,
      UPDATE_AS,
      CHECK_SM,
      CHECK_MBOX,
      EN_DIS_SM,
      SM_ACTIVATION_CHANGED,
      UPDATE_RXPDO,
      DROP_RXPDO,
      UPDATE_TXPDO
   );

   constant RB0 : EcRegType := ( addr=> x"3064", bena => HBI_BE_B0_C );
   constant RB1 : EcRegType := ( addr=> x"3065", bena => HBI_BE_B0_C );
   constant RB2 : EcRegType := ( addr=> x"3066", bena => HBI_BE_B0_C );
   constant RB3 : EcRegType := ( addr=> x"3067", bena => HBI_BE_B0_C );

   constant RW0 : EcRegType := ( addr=> x"3064", bena => HBI_BE_W0_C );
   constant RW1 : EcRegType := ( addr=> x"3066", bena => HBI_BE_W0_C );

   constant RD0 : EcRegType := ( addr=> x"3064", bena => (others => HBI_BE_ACT_C) );

   constant WB0 : EcRegType := ( addr=> x"0F80", bena => HBI_BE_B0_C );
   constant WB1 : EcRegType := ( addr=> x"0F81", bena => HBI_BE_B0_C );
   constant WB2 : EcRegType := ( addr=> x"0F82", bena => HBI_BE_B0_C );
   constant WB3 : EcRegType := ( addr=> x"0F83", bena => HBI_BE_B0_C );

   constant WW0 : EcRegType := ( addr=> x"0F80", bena => HBI_BE_W0_C );
   constant WW1 : EcRegType := ( addr=> x"0F82", bena => HBI_BE_W0_C );

   constant WD0 : EcRegType := ( addr=> x"0F80", bena => (others => HBI_BE_ACT_C) );

   constant EC_IRQ_CFG_INIT_C : std_logic_vector(31 downto 0) := (
      EC_IRQ_CFG_TYP_IDX_C => '1', -- push-pull
      EC_IRQ_CFG_ENA_IDX_C => '1', -- enable
      EC_IRQ_CFG_POL_IDX_C => EC_IRQ_ACT_C,
      others               => '0'
   );

   constant EC_IRQ_ENA_INIT_C : std_logic_vector(31 downto 0) := (
      EC_IRQ_ENA_ECAT_IDX_C => '1',
      others                => '0'
   );

   constant EC_AL_EMSK_INIT_C : std_logic_vector(31 downto 0) := (
      EC_AL_EREQ_CTL_IDX_C  => '1',
      EC_AL_EREQ_EEP_IDX_C  => '1',
      EC_AL_EREQ_SMA_IDX_C  => '1',
      EC_AL_EREQ_SM2_IDX_C  => '1',
      EC_AL_EREQ_WDG_IDX_C  => '1',
      others                => '0'
   );

   function toESCState(constant x : std_logic_vector)
   return EscStateType is
   begin
      case to_integer(unsigned(x(3 downto 0))) is
         when 1 => return INIT;
         when 2 => return PREOP;
         when 3 => return BOOT;
         when 4 => return SAFEOP;
         when 8 => return OP;
         when others =>
      end case;
      return UNKNOWN;
   end function toESCState;

   type RWXactType is record
      reg      : EcRegType;
      val      : std_logic_vector(31 downto 0);
      rdnwr    : boolean;
   end record RWXactType;

   constant RWXACT_INIT_C : RWXactType := (
      reg      => ( addr => (others => '0'), bena => (others => '0') ),
      val      => ( others => '0' ),
      rdnwr    => true
   );

   function toSL(constant x : boolean) return std_logic is
   begin
      if ( x ) then return '1'; else return '0'; end if;
   end function toSL;

   function RWXACT(
      constant reg : EcRegType;
      constant val : std_logic_vector := ""
   )
   return RWXactType is
      variable rv    : RWXactType;
   begin
      rv.reg   := reg;
      rv.rdnwr := (val'length = 0);
      rv.val   := (others => '0');
      if ( not rv.rdnwr ) then
         rv.val( val'length - 1 downto 0 ) := val;
      end if;
      return rv;
   end function RWXACT;

   function RWXACT(
      constant addr: std_logic_vector;
      constant bena: std_logic_vector( 3 downto 0);
      constant val : std_logic_vector := ""
   )
   return RWXactType is
      variable rv    : RWXactType;
      variable reg   : EcRegType;
   begin
      reg.addr                          := (others => '0');
      reg.addr(addr'length -1 downto 0) := addr;
      reg.bena                          := bena;
      return RWXACT( reg, val );
   end function RWXACT;

   type RWXactArray is array (natural range <>) of RWXactType;

   constant LD_XACT_MAX_C          : natural := 3;
   constant XACT_MAX_C             : natural := 2**LD_XACT_MAX_C;

   constant TXPDO_BURST_MAX_C      : natural := 7;

   type RWXactSeqType is record
      seq      : RWXactArray(0 to XACT_MAX_C - 1);
      idx      : unsigned(LD_XACT_MAX_C - 1 downto 0);
      num      : unsigned(LD_XACT_MAX_C - 1 downto 0);
      dly      : unsigned(                3 downto 0); -- FIXME
      don      : std_logic;
      ret      : ControllerState;
   end record RWXactSeqType;

   constant RWXACT_SEQ_INIT_C : RWXactSeqType := (
      seq      => (others => RWXACT_INIT_C),
      idx      => (others => '0'),
      num      => (others => '0'),
      dly      => (others => '0'),
      don      => '0',
      ret      => POLL_IRQ
   );

   type RegType is record
      state    : ControllerState;
      testPhas : natural range 0 to 3;
      testFail : natural range 0 to 31;
      reqState : ESCStateType;
      errAck   : std_logic;
      curState : ESCStateType;
      errSta   : std_logic;
      alErr    : ESCVal16Type;
      ctlReq   : Lan9254ReqType;
      program  : RWXactSeqType;
      smDis    : std_logic_vector( 3 downto 0);
      rptAck   : std_logic_vector( 3 downto 0);
      lastAL   : std_logic_vector(31 downto 0);
      rxPDO    : Lan9254PDOMstType;
      txPDORdy : std_logic;
      txPDOBst : natural range 0 to TXPDO_BURST_MAX_C;
      txPDOSnt : natural range 0 to (to_integer(unsigned(ESC_SM3_LEN_C)) - 1)/2;
      txPDODcm : natural range 0 to TXPDO_UPDATE_DECIMATION_C;
      decim    : natural;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state    => TEST,
      testPhas => 0,
      testFail => 0,
      reqState => INIT,
      errAck   => '0',
      curState => INIT,
      errSta   => '0',
      alErr    => EC_ALER_OK_C,
      ctlReq   => LAN9254REQ_INIT_C,
      program  => RWXACT_SEQ_INIT_C,
      smDis    => (others => '1'),
      rptAck   => (others => '0'),
      lastAL   => (others => '0'),
      rxPDO    => LAN9254PDO_MST_INIT_C,
      txPDORdy => '0',
      txPDOBst => 0,
      txPDOSnt => 0,
      txPDODcm => 0,
      decim    => 0
   );

   signal     r    : RegType := REG_INIT_C;
   signal     rin  : RegType; 

   signal     probe0 : std_logic_vector(63 downto 0) := (others => '0');
   signal     probe1 : std_logic_vector(63 downto 0) := (others => '0');
   signal     probe2 : std_logic_vector(63 downto 0) := (others => '0');
   signal     probe3 : std_logic_vector(63 downto 0) := (others => '0');

   procedure scheduleRegXact(
      variable endp : inout RegType;
      constant prog : in    RWXactArray;
      constant dly  : in    unsigned(3 downto 0) := x"0"  -- FIXME
   ) is
   begin
      endp.program.ret             := endp.state;
      endp.state                   := XACT;
      endp.program.seq(prog'range) := prog;
      endp.program.idx             := (others => '0');
      endp.program.num             := to_unsigned(prog'length - 1, endp.program.num'length);
      endp.program.dly             := dly;
      endp.ctlReq.valid            := '0';
   end procedure scheduleRegXact;

   procedure readReg (
      variable rdOut: inout Lan9254ReqType;
      signal   rdInp: in    Lan9254RepType;
      constant reg  : in    EcRegType;
      constant enbl : in    boolean                      := true
   ) is
   begin
      lan9254HBIRead( rdOut, rdInp, reg.addr, reg.bena, enbl );
   end procedure readReg;

   procedure writeReg(
      variable wrOut: inout Lan9254ReqType;
      signal   wrInp: in    Lan9254RepType;
      constant reg  : in    EcRegType;
      constant wrDat: in    std_logic_vector(31 downto 0);
      constant enbl : in    boolean                       := true
   ) is
   begin
      lan9254HBIWrite( wrOut, wrInp, reg.addr, wrDat, reg.bena, enbl );
   end procedure writeReg;

   function toSlv(constant arg : ESCStateType) return std_logic_vector is
      variable ret : std_logic_vector(3 downto 0);
   begin
      case arg is
         when UNKNOWN => ret := "0001";
         when INIT    => ret := "0001";
         when PREOP   => ret := "0010";
         when BOOT    => ret := "0011";
         when SAFEOP  => ret := "0100";
         when OP      => ret := "1000";
      end case;
      return ret;
   end function toSlv;

   procedure testRegisterIO(
      variable v : inout RegType
   ) is
   begin
      CASE_TEST : case ( r.testPhas ) is
         when 0 =>
            if ( '0' = r.program.don ) then
               scheduleRegXact( v,
                  (
                     0 => RWXACT( RD0 ), -- read twice (after reset)
                     1 => RWXACT( RD0 ),
                     2 => RWXACT( RB3 ),
                     3 => RWXACT( RB2 ),
                     4 => RWXACT( RB1 ),
                     5 => RWXACT( RB0 ),
                     6 => RWXACT( RW1 ),
                     7 => RWXACT( RW0 )
                  )
               );
            else
               if ( r.program.seq(1).val(31 downto  0) /= x"87654321" ) then
                  assert false report "Reg32  readback mismatch" severity failure;
                  if ( v.testFail = 0 ) then v.testFail := 1; end if;
               end if;
               if ( r.program.seq(2).val( 7 downto  0) /= x"87"       ) then
                  assert false report "Reg8d  readback mismatch" severity failure;
                  if ( v.testFail = 0 ) then v.testFail := 2; end if;
               end if;
               if ( r.program.seq(3).val( 7 downto  0) /= x"65"       ) then
                  assert false report "Reg8c  readback mismatch" severity failure;
                  if ( v.testFail = 0 ) then v.testFail := 3; end if;
               end if;
               if ( r.program.seq(4).val( 7 downto  0) /= x"43"       ) then
                  assert false report "Reg8b  readback mismatch" severity failure;
                  if ( v.testFail = 0 ) then v.testFail := 4; end if;
               end if;
               if ( r.program.seq(5).val( 7 downto  0) /= x"21"       ) then
                  assert false report "Reg8a  readback mismatch" severity failure;
                  if ( v.testFail = 0 ) then v.testFail := 5; end if;
               end if;
               if ( r.program.seq(6).val(15 downto  0) /= x"8765"     ) then
                  assert false report "Reg16b readback mismatch" severity failure;
                  if ( v.testFail = 0 ) then v.testFail := 6; end if;
               end if;
               if ( r.program.seq(7).val(15 downto  0) /= x"4321"     ) then
                  assert false report "Reg16a readback mismatch" severity failure;
                  if ( v.testFail = 0 ) then v.testFail := 7; end if;
               end if;
               v.testPhas := r.testPhas + 1;
            end if;

         when 1 =>
            if ( '0' = r.program.don ) then
               scheduleRegXact( v,
                  (
                     0 => RWXACT( WD0, x"c3b2a1f0" ),
                     1 => RWXACT( RD0 ),
                     2 => RWXACT( WD0 ),
                     3 => RWXACT( WB3, x"aa" ),
                     4 => RWXACT( WD0 ),
                     5 => RWXACT( WB2, x"bb" ),
                     6 => RWXACT( WD0 )
                  )
               );
            else
               if ( r.program.seq(1).val(31 downto  0) /= x"87654321" ) then
                  assert false report "Reg32 (check) readback mismatch" severity failure;
                  if ( v.testFail = 0 ) then v.testFail := 8; end if;
               end if;
               if ( r.program.seq(2).val(31 downto  0) /= x"c3b2a1f0" ) then
                  assert false report "Write32 readback mismatch" severity failure;
                  if ( v.testFail = 0 ) then v.testFail := 9; end if;
               end if;
               if ( r.program.seq(4).val(31 downto  0) /= x"aab2a1f0" ) then
                  assert false report "Write8d  readback mismatch" severity failure;
                  if ( v.testFail = 0 ) then v.testFail :=10; end if;
               end if;
               if ( r.program.seq(6).val(31 downto  0) /= x"aabba1f0" ) then
                  assert false report "Write8c  readback mismatch" severity failure;
                  if ( v.testFail = 0 ) then v.testFail :=11; end if;
               end if;
               v.testPhas := r.testPhas + 1;
            end if;

         when 2 =>
            if ( '0' = r.program.don ) then
               scheduleRegXact( v,
                  (
                     0 => RWXACT( WB1, x"cc" ),
                     1 => RWXACT( WD0 ),
                     2 => RWXACT( WB0, x"dd" ),
                     3 => RWXACT( WD0 ),
                     4 => RWXACT( WW1, x"4433" ),
                     5 => RWXACT( WD0 ),
                     6 => RWXACT( WW0, x"2211" ),
                     7 => RWXACT( WD0 )
                  )
               );
            else
               if ( r.program.seq(1).val(31 downto  0) /= x"aabbccf0" ) then
                  assert false report "Write8b  readback mismatch" severity failure;
                  if ( v.testFail = 0 ) then v.testFail :=12; end if;
               end if;
               if ( r.program.seq(3).val(31 downto  0) /= x"aabbccdd" ) then
                  assert false report "Write8a  readback mismatch" severity failure;
                  if ( v.testFail = 0 ) then v.testFail :=13; end if;
               end if;
               if ( r.program.seq(5).val(31 downto  0) /= x"4433ccdd" ) then
                  assert false report "Write16b readback mismatch" severity failure;
                  if ( v.testFail = 0 ) then v.testFail :=14; end if;
               end if;
               if ( r.program.seq(7).val(31 downto  0) /= x"44332211" ) then
                  assert false report "Write16a readback mismatch" severity failure;
                  if ( v.testFail = 0 ) then v.testFail :=15; end if;
               end if;
               if ( v.testFail = 0 ) then
                  v.testPhas := 0;
                  v.state    := INIT;
               else
                  v.testPhas := r.testPhas + 1; -- go into limbo
               end if;
            end if;
         when others =>
            -- remain here
      end case CASE_TEST;
   end procedure testRegisterIO;

begin

   assert ESC_SM2_SMA_C(0) = '0' report "RXPDO address must be word aligned" severity failure;
   assert ESC_SM3_SMA_C(0) = '0' report "TXPDO address must be word aligned" severity failure;

   P_COMB : process (r, rep, rxPDORdy, txPDOMst, eeprom, irq) is
      variable v   : RegType;
      variable val : std_logic_vector(31 downto 0);
      variable xct : RWXactType;
   begin
      v             := r;
      v.program.don := '0';
      val           := (others => '0');
      xct           := RWXACT_INIT_C;

      if ( r.txPDODcm > 0 ) then
         v.txPDODcm := r.txPDODcm - 1;
      end if;

      C_STATE : case r.state is

         when TEST =>
            if ( REG_IO_TEST_ENABLE_G ) then
               testRegisterIO(v);
            else
               v.state := INIT;
            end if;

         when INIT =>
            if ( '0' = r.program.don ) then
               scheduleRegXact(
                  v,
                  (
                     0 => RWXACT( EC_REG_AL_EMSK_C, EC_AL_EMSK_INIT_C ),
                     1 => RWXACT( EC_REG_IRQ_ENA_C, EC_IRQ_ENA_INIT_C ),
                     2 => RWXACT( EC_REG_IRQ_CFG_C, EC_IRQ_CFG_INIT_C )
                  )
               );
            else
               v.state := UPDATE_AS;
            end if;

         when POLL_IRQ =>
            if ( irq = EC_IRQ_ACT_C ) then
               v.state := POLL_AL_EVENT;
            else
               -- maybe the TXPDO needs to be updated
               if (    ( r.curState = SAFEOP or r.curState = OP )
                   and ( ESC_SM3_ACT_C = '1' )
                   and ( to_integer(unsigned(ESC_SM3_LEN_C)) >  0  )
                   and ( r.txPDODcm = 0 )
                  ) then
                  v.txPDOBst :=  TXPDO_BURST_MAX_C;
                  v.txPDORdy := '1';
                  v.state    := UPDATE_TXPDO;
               end if;
            end if;

         when POLL_AL_EVENT =>
            if ( '0' = r.program.don ) then
               scheduleRegXact( v, ( 0 => RWXACT( EC_REG_AL_EREQ_C ) ) );
            else
               v.lastAL := r.program.seq(0).val;
               if ( (r.program.seq(0).val and EC_AL_EMSK_INIT_C) = x"0000_0000" ) then
                  -- no more events pending; wait for an IRQ
                  v.state  := POLL_IRQ;
               else
                  v.state  := HANDLE_AL_EVENT;
               end if;
            end if;

         -- ************ NOTE ************
         -- All events handled here must be
         -- enabled in EC_REG_AL_EMSK_C
         -- ******************************
         when HANDLE_AL_EVENT =>
            v.state := POLL_AL_EVENT; -- keep polling AL until nothing is pending
            if    ( r.lastAL(EC_AL_EREQ_CTL_IDX_C) = '1' ) then
               v.lastAL(EC_AL_EREQ_CTL_IDX_C) := '0';
               v.state                        := READ_AL;
report "AL  EVENT";
            elsif ( r.lastAL(EC_AL_EREQ_EEP_IDX_C) = '1' ) then
               v.lastAL(EC_AL_EREQ_EEP_IDX_C) := '0';
               v.state                        := EEP_EMUL;
report "EEP EVENT";
            elsif ( r.lastAL(EC_AL_EREQ_SMA_IDX_C) = '1' ) then
               v.lastAL(EC_AL_EREQ_SMA_IDX_C) := '0';
               v.state                        := SM_ACTIVATION_CHANGED;
report "SMA EVENT";
            elsif ( r.lastAL(EC_AL_EREQ_SM2_IDX_C) = '1' ) then
               v.lastAL(EC_AL_EREQ_SM2_IDX_C) := '0';
               if ( (ESC_SM2_ACT_C = '1') and (unsigned(ESC_SM2_LEN_C) > 0) ) then
                  if ( r.curState = OP ) then
                     v.state                     := UPDATE_RXPDO;
                  else
                     v.state                     := DROP_RXPDO;
                  end if;
               end if;
            elsif ( r.lastAL(EC_AL_EREQ_WDG_IDX_C) = '1' ) then
               -- NOTE: we only detect if the watchdog expires if it has ever
               --       been triggered (by the master) and subsequently expires.
               --       We cannot clear the watchdog from the PDI interface and
               --       thus cannot reset it when entering OP state.
               --       Therefore, if we enter OP state and the watchdog is never petted
               --       then it never expires (because it already is) and we'll
               --       never get an event.
               v.lastAL(EC_AL_EREQ_WDG_IDX_C) := '0';
               v.state                        := HANDLE_WD_EVENT;
            end if;

         when HANDLE_WD_EVENT =>
            if ( '0' = r.program.don ) then
               scheduleRegXact( v, ( 0 => RWXACT( EC_REG_WD_PDST_C ) ) );
            else
report "WATCHDOG EVENT: " & std_logic'image( r.program.seq(0).val(0) );
               if ( r.program.seq(0).val(0) = '0' ) then
                  v.alErr    := EC_ALER_WATCHDOG_C;
                  v.errSta   := '1';
                  v.reqState := SAFEOP;
                  v.state    := UPDATE_AS;
               else
                  v.state := HANDLE_AL_EVENT;
               end if;
            end if;

         when READ_AL =>
            -- read AL control reg
            if ( '0' = r.program.don ) then
               scheduleRegXact( v, ( 0 => RWXACT( EC_REG_AL_CTRL_C ) ) );
            else
               v.errAck       := r.program.seq(0).val(4);
               if ( v.errAck = '1' ) then
                  v.errSta := '0';
                  v.errAck := '0';
                  v.alErr  := EC_ALER_OK_C;
               end if;

               v.reqState := toESCState(r.program.seq(0).val);
               if ( v.reqState = INIT ) then
                  v.errSta := '0'; v.errAck := '0';
               elsif ( v.reqState = UNKNOWN ) then
                  assert false report "Invalid state in AL_CTRL: " & integer'image(to_integer(unsigned(r.program.seq(0).val(3 downto 0)))) severity failure;
                  v.reqState := INIT;
                  v.errSta   := '1';
                  v.alErr    := EC_ALER_UNKNOWNSTATE_C;
               end if;

report "READ_AL " & toString( r.program.seq(0).val ) & " v.errSta " & std_logic'image(v.errSta) & " r.errSta " & std_logic'image(r.errSta);
report "CUR-STATE " & integer'image(ESCStateType'pos(r.curState)) & " REQ-STATE " & integer'image(ESCStateType'pos(v.reqState));
               if ( v.reqState /= r.reqState or v.errSta /= r.errSta ) then
                  v.state := EVALUATE_TRANSITION;
               else
                  v.state := HANDLE_AL_EVENT;
               end if;
            end if;

         when EVALUATE_TRANSITION =>

            v.state := UPDATE_AS;

            if ( r.reqState = BOOT ) then
               if ( r.curState = INIT or r.curState = BOOT ) then
                  -- retrieve station address # NOT IMPLEMENTED
                  -- start boot mailbox       # NOT IMPLEMENTED
               else
                  if ( r.curState = OP ) then
                     -- stop output           # FIXME
                     v.reqState := SAFEOP;
                  end if;
                  v.errSta := '1';
                  v.alErr  := EC_ALER_INVALIDSTATECHANGE_C;
               end if;
            elsif ( r.curState = BOOT ) then
               if ( r.reqState = INIT ) then
                  -- stop boot mailbox       # NOT IMPLEMENTED
               else
                  -- stop boot mailbox       # SOES doesn't do that -- should we?
                  v.errSta    := '1';
                  v.reqState := PREOP;
                  v.alErr     := EC_ALER_INVALIDSTATECHANGE_C;
               end if;
            elsif ( ESCStateType'pos( r.reqState ) - ESCStateType'pos( r.curState ) >  1 ) then
                  v.errSta    := '1';
                  v.alErr     := EC_ALER_INVALIDSTATECHANGE_C;
            elsif ( ESCStateType'pos( r.reqState ) - ESCStateType'pos( r.curState ) >= 0 ) then
               if ( ( r.reqState = PREOP ) and ( r.curState /= PREOP ) ) then
                  -- start mailbox           # NOT IMPLEMENTED
                  v.smDis(1) := '0';
                  v.smDis(0) := '0';
                  v.state    := CHECK_MBOX;
report "starting MBOX";
               elsif ( ( r.reqState = SAFEOP ) ) then
                  v.smDis(3) := '0';
                  v.state    := CHECK_SM;
report "starting SM23";
               elsif ( ( r.reqState = OP ) and ( r.curState /= OP ) ) then
                  -- start output            # NOT IMPLEMENTED
                  v.smDis(2) := '0';
                  v.state    := EN_DIS_SM;
               end if;
            else -- state downshift
               if ( ( r.reqState < OP ) and ( r.curState = OP ) ) then
                  -- stop output             # NOT IMPLEMENTED
                  v.smDis(2) := '1';
               end if;
               if ( ( r.reqState < SAFEOP ) and ( r.curState >= SAFEOP ) ) then
                  -- stop input              # NOT IMPLEMENTED
                  v.smDis(3) := '1';
               end if;
               if ( ( r.reqState < PREOP  ) and ( r.curState >= PREOP  ) ) then
                  -- stop mailbox            # NOT IMPLEMENTED
                  v.smDis(1) := '1';
                  v.smDis(0) := '1';
               end if;
               v.state := EN_DIS_SM;
            end if;

         when XACT =>
            xct := r.program.seq(to_integer(r.program.idx));
            if ( xct.rdnwr ) then
               readReg( v.ctlReq, rep, xct.reg );
               if ( ( r.ctlReq.valid and rep.valid ) = '1' ) then
                  v.program.seq(to_integer(r.program.idx)).val := v.ctlReq.wdata;
               end if;
            else
--report "WRITE " & integer'image(to_integer(unsigned(xct.reg.addr))) & " " & integer'image(to_integer(signed(xct.val)));
               writeReg( v.ctlReq, rep, xct.reg, xct.val );
            end if;
            if ( ( r.ctlReq.valid and rep.valid ) = '1' ) then
               v.ctlReq.valid := '0';
               if ( r.program.idx = r.program.num ) then
                  v.state        := r.program.ret;
                  v.program.don  := '1';
               else
                  v.program.idx  := r.program.idx + 1;
               end if;
            end if;

         when UPDATE_AS =>
            if ( '0' = r.program.don ) then
               val(4)          := r.errSta;
               val(3 downto 0) := toSlv( r.reqState );
report "entering UPDATE_AS " & toString( val );
               scheduleRegXact(
                  v,
                  (
                     0 => RWXACT( EC_REG_AL_STAT_C, val     ),
                     1 => RWXACT( EC_REG_AL_ERRO_C, r.alErr )
                  )
               );
            else
               -- handle state transitions
               report "Transition from " & integer'image(ESCStateType'pos(r.curState)) & " => " & integer'image(ESCStateType'pos(r.reqState));
               v.curState := r.reqState;
               v.state    := POLL_IRQ;
            end if;

         when CHECK_SM =>
            if ( '0' = r.program.don ) then
               scheduleRegXact(
                  v,
                  (
                     0 => RWXACT( EC_REG_SM_PSA_F(2) ),
                     1 => RWXACT( EC_REG_SM_LEN_F(2) ),
                     2 => RWXACT( EC_REG_SM_CTL_F(2) ),
                     3 => RWXACT( EC_REG_SM_ACT_F(2) ),
                     4 => RWXACT( EC_REG_SM_PSA_F(3) ),
                     5 => RWXACT( EC_REG_SM_LEN_F(3) ),
                     6 => RWXACT( EC_REG_SM_CTL_F(3) ),
                     7 => RWXACT( EC_REG_SM_ACT_F(3) )
                  )
               );
            else
               v.state             := CHECK_MBOX;
               if (   ( (ESC_SM2_ACT_C or  r.program.seq(3).val(EC_SM_ACT_IDX_C)) = '0'   ) -- deactivated
                   or (    ( (ESC_SM2_ACT_C and r.program.seq(3).val(EC_SM_ACT_IDX_C)) = '1' )
                       and ( ESC_SM2_SMA_C     =  r.program.seq(0).val(ESC_SM2_SMA_C'range) )
                       and ( ESC_SM2_LEN_C     =  r.program.seq(1).val(ESC_SM2_LEN_C'range) )
                       and ( ESC_SM2_SMC_C     =  r.program.seq(2).val(ESC_SM2_SMC_C'range) ) )
               ) then
                  -- PASSED CHECK
               else
report "CHECK SM2 FAILED ACT: " & integer'image(to_integer( unsigned( r.program.seq(3).val ) ))
       & " PSA " & integer'image(to_integer( unsigned( r.program.seq(0).val ) ))
       & " LEN " & integer'image(to_integer( unsigned( r.program.seq(1).val ) ))
       & " CTL " & integer'image(to_integer( unsigned( r.program.seq(2).val ) ))
severity warning;
                  v.smDis(3 downto 2) := (others => '1');
                  v.reqState          := PREOP;
                  v.errSta            := '1';
                  v.alErr             := EC_ALER_INVALIDOUTPUTSM_C;
               end if;
               if (   ( (ESC_SM3_ACT_C or  r.program.seq(7).val(EC_SM_ACT_IDX_C)) = '0'   ) -- deactivated
                   or (    ( (ESC_SM3_ACT_C and r.program.seq(7).val(EC_SM_ACT_IDX_C)) = '1' )
                       and ( ESC_SM3_SMA_C     =  r.program.seq(4).val(ESC_SM3_SMA_C'range) )
                       and ( ESC_SM3_LEN_C     =  r.program.seq(5).val(ESC_SM3_LEN_C'range) )
                       and ( ESC_SM3_SMC_C     =  r.program.seq(6).val(ESC_SM3_SMC_C'range) ) )
               ) then
                  -- PASSED CHECK
               else
report "CHECK SM3 FAILED"
severity warning;
                  v.smDis(3 downto 2) := (others => '1');
                  v.reqState          := PREOP;
                  v.errSta            := '1';
                  v.alErr             := EC_ALER_INVALIDINPUTSM_C;
               end if;
            end if;

         when CHECK_MBOX =>
            if ( '0' = r.program.don ) then
               scheduleRegXact(
                  v,
                  (
                     0 => RWXACT( EC_REG_SM_PSA_F(0) ),
                     1 => RWXACT( EC_REG_SM_LEN_F(0) ),
                     2 => RWXACT( EC_REG_SM_CTL_F(0) ),
                     3 => RWXACT( EC_REG_SM_ACT_F(0) ),
                     4 => RWXACT( EC_REG_SM_PSA_F(1) ),
                     5 => RWXACT( EC_REG_SM_LEN_F(1) ),
                     6 => RWXACT( EC_REG_SM_CTL_F(1) ),
                     7 => RWXACT( EC_REG_SM_ACT_F(1) )
                  )
               );
            else
               v.state             := EN_DIS_SM;
               if (   ( (ESC_SM0_ACT_C or  r.program.seq(3).val(EC_SM_ACT_IDX_C)) = '0'   ) -- deactivated
                   or (    ( (ESC_SM0_ACT_C and r.program.seq(3).val(EC_SM_ACT_IDX_C)) = '1' )
                       and ( ESC_SM0_SMA_C     =  r.program.seq(0).val(ESC_SM0_SMA_C'range) )
                       and ( ESC_SM0_LEN_C     =  r.program.seq(1).val(ESC_SM0_LEN_C'range) )
                       and ( ESC_SM0_SMC_C     =  r.program.seq(2).val(ESC_SM0_SMC_C'range) ) )
               ) then
                  -- PASSED CHECK
               else
report "CHECK SM0 FAILED ACT: " & integer'image(to_integer( unsigned( r.program.seq(3).val ) ))
       & " PSA " & integer'image(to_integer( unsigned( r.program.seq(0).val ) ))
       & " LEN " & integer'image(to_integer( unsigned( r.program.seq(1).val ) ))
       & " CTL " & integer'image(to_integer( unsigned( r.program.seq(2).val ) ))
severity warning;
                  v.smDis(1 downto 0) := (others => '1');
                  v.reqState          := INIT;
                  v.errSta            := '1';
                  v.alErr             := EC_ALER_INVALIDMBXCONFIG_C;
               end if;
               if (   ( (ESC_SM1_ACT_C or  r.program.seq(7).val(EC_SM_ACT_IDX_C)) = '0'   ) -- deactivated
                   or (    ( (ESC_SM1_ACT_C and r.program.seq(7).val(EC_SM_ACT_IDX_C)) = '1' )
                       and ( ESC_SM1_SMA_C     =  r.program.seq(4).val(ESC_SM1_SMA_C'range) )
                       and ( ESC_SM1_LEN_C     =  r.program.seq(5).val(ESC_SM1_LEN_C'range) )
                       and ( ESC_SM1_SMC_C     =  r.program.seq(6).val(ESC_SM1_SMC_C'range) ) )
               ) then
                  -- PASSED CHECK
               else
report "CHECK SM1 FAILED"
severity warning;
                  v.smDis(1 downto 0) := (others => '1');
                  v.reqState          := INIT;
                  v.errSta            := '1';
                  v.alErr             := EC_ALER_INVALIDMBXCONFIG_C;
               end if;
            end if;

         when EN_DIS_SM =>
            if ( '0' = r.program.don ) then
               scheduleRegXact(
                  v,
                  (
                     0 => RWXACT( EC_REG_SM_PDI_F(0), r.rptAck(0) & r.smDis(0) ),
                     1 => RWXACT( EC_REG_SM_PDI_F(1), r.rptAck(1) & r.smDis(1) ),
                     2 => RWXACT( EC_REG_SM_PDI_F(2), r.rptAck(2) & r.smDis(2) ),
                     3 => RWXACT( EC_REG_SM_PDI_F(3), r.rptAck(3) & r.smDis(3) )
                  )
               );
               -- start input if enabled  # NOT IMPLEMENTED
            else
               v.state := UPDATE_AS;               
            end if;

         when SM_ACTIVATION_CHANGED =>

            report "SM_ACTIVATION_CHANGED";
            report "CurState " & integer'image(ESCStateType'pos(r.curState)) & " ReqState " & integer'image(ESCStateType'pos(r.reqState));
            report "last AL  " & toString( r.lastAL );

              
            if ( '0' = r.program.don ) then
               scheduleRegXact(
                  v,
                  (
                     0 => RWXACT( EC_REG_SM_ACT_F(0) ),
                     1 => RWXACT( EC_REG_SM_ACT_F(1) ),
                     2 => RWXACT( EC_REG_SM_ACT_F(2) ),
                     3 => RWXACT( EC_REG_SM_ACT_F(3) ),
                     4 => RWXACT( EC_REG_SM_ACT_F(4) ),
                     5 => RWXACT( EC_REG_SM_ACT_F(5) ),
                     6 => RWXACT( EC_REG_SM_ACT_F(6) ),
                     7 => RWXACT( EC_REG_SM_ACT_F(7) )
                  )
               );
            else
               for i in 0 to 7 loop
                  report "SM " & integer'image(i) & " active: " & std_logic'image(r.program.seq(i).val(0));
               end loop;
               v.state := POLL_IRQ;
               if ( r.curState = SAFEOP or r.curState = OP ) then
                  v.state := CHECK_SM;
               elsif ( r.curState = PREOP ) then
                  v.state := CHECK_MBOX;
               end if;
            end if;

         when EEP_EMUL =>
            if ( '0' = r.program.don ) then
               -- read CSR last; we keep it in the same position;
               -- in case of a READ command it must be written last!
               scheduleRegXact(
                  v,
                  (
                     0 => RWXACT( EC_REG_EEP_DLO_C ),
                     1 => RWXACT( EC_REG_EEP_ADR_C ),
                     2 => RWXACT( EC_REG_EEP_CSR_C )
                  )
               );
            else
               case r.program.seq(2).val(10 downto 8) is
                  when EEPROM_WRITE_C =>
--DONX                     writeEEPROMEmul( eeprom, r.program.seq(1).val, r.program.seq(0).val );
                     v.state := EEP_WRITE;

                  when EEPROM_READ_C | EEPROM_RELD_C  =>
                     readEEPROMEmul( eeprom, r.program.seq(1).val, v.program.seq(0).val, v.program.seq(1).val );
                     v.state := EEP_READ;

                  when others  =>
                     report "UNSUPPORTED EE EMULATION COMMAND " & integer'image(to_integer(unsigned(r.program.seq(2).val)))
                        severity warning;
                     v.state := HANDLE_AL_EVENT;
               end case;
            end if;

        when EEP_WRITE =>
            if ( '0' = r.program.don ) then
               scheduleRegXact( v, ( 0 => RWXACT( EC_REG_EEP_CSR_C, r.program.seq(2).val ) ) );
            else
               v.state := HANDLE_AL_EVENT;
            end if;
                     
        when EEP_READ =>
            if ( '0' = r.program.don ) then
--report "EEP_READ CSR" & integer'image(to_integer(signed(r.program.seq(0).val)));
--report "         VLO" & integer'image(to_integer(signed(r.program.seq(1).val)));
--report "         VHI" & integer'image(to_integer(signed(r.program.seq(2).val)));
               -- the EEPROM contents are now in r.program.seq(1/2).val
               scheduleRegXact(
                  v,
                  (
                     0 => RWXACT( EC_REG_EEP_DLO_C, r.program.seq(0).val ),
                     1 => RWXACT( EC_REG_EEP_DHI_C, r.program.seq(1).val ),
                     2 => RWXACT( EC_REG_EEP_CSR_C, r.program.seq(2).val )
                  )
               );
            else
               v.state := HANDLE_AL_EVENT;
            end if;

         when DROP_RXPDO =>
            if ( '0' = r.program.don ) then
               scheduleRegXact(
                  v,
                  (
                     0 => RWXACT( EC_REG_RXPDO_L_C )
                  )
               );
            else
               v.state := HANDLE_AL_EVENT;
            end if;

         when UPDATE_RXPDO =>

            if ( r.rxPDO.valid = '1' ) then
               -- write to RXPDO pending
               if ( rxPDORdy  = '1' ) then
if ( r.decim = 0 ) then
report "UPDATE_RXPDO " & toString(std_logic_vector(r.rxPDO.wrdAddr)) & " LST: " & std_logic'image(r.rxPDO.last) & " BEN " & toString(r.rxPDO.ben) & " DAT " & toString(r.rxPDO.data);
v.decim := 200;
else
v.decim := r.decim - 1;
end if;
                  -- write to RXPDO complete
                  v.rxPDO.valid := '0';
                  if ( r.rxPDO.last = '1' ) then
                     -- last write completed; we are done
                     v.state := HANDLE_AL_EVENT;
                     v.rxPDO := LAN9254PDO_MST_INIT_C;
                  else
                     -- next word
                     v.rxPDO.wrdAddr := r.rxPDO.wrdAddr + 1;
                  end if;
               end if;
            elsif ( '1' = r.program.don ) then
               -- read from lan9254 complete; initiate write to RXPDO interface
               v.rxPDO.data   := rep.rdata(15 downto  0);
               v.rxPDO.valid  := '1';
            else
               -- RXPDO write not onging and lan9254 register read not done
               -- => initiate next lan9254 register read operation

               v.ctlReq.addr  := std_logic_vector((r.rxPDO.wrdAddr & "0") + unsigned(ESC_SM2_SMA_C(v.ctlReq.addr'range)));
               v.rxPDO.ben    := "11";
               v.rxPDO.last   := '0';
               v.ctlReq.be    := HBI_BE_W0_C;
              
               if ( r.rxPDO.wrdAddr = SM2_WADDR_END_C ) then
                  v.rxPDO.last := '1';
                  if ( ESC_SM2_HACK_LEN_C(0) = '1' ) then
                     v.rxPDO.ben(1) := '0';
                     v.ctlReq.be(1) := not HBI_BE_ACT_C;
                  end if;
               end if;

               scheduleRegXact( v, ( 0 => RWXACT( v.ctlReq.addr, v.ctlReq.be ) ) );

            end if;

         when UPDATE_TXPDO =>
            if ( r.txPDORdy = '1' ) then

               v.txPDORdy := '0';

               -- write to RXPDO pending
               if ( txPDOMst.valid  = '1' ) then

if ( r.decim = 0 ) then
report "UPDATE_TXPDO " & toString(std_logic_vector(txPDOMst.wrdAddr)) & " LST: " & std_logic'image(txPDOMst.last) & " BEN " & toString(txPDOMst.ben) & " DAT " & toString(txPDOMst.data);
v.decim := 200;
else
v.decim := r.decim - 1;
end if;

                  if ( txPDOMst.wrdAddr <= SM3_WADDR_END_C ) then
                     v.ctlReq.addr  := std_logic_vector((txPDOMst.wrdAddr & "0") + unsigned(ESC_SM3_SMA_C(v.ctlReq.addr'range)));
                     v.ctlReq.wdata := ( x"0000" & txPDOMst.data );
                     v.ctlReq.be    := HBI_BE_W0_C;

                     if ( txPDOMst.ben(0) = '0' ) then
                        v.ctlReq.be(0) := not HBI_BE_ACT_C;
                     end if;

                     -- if last byte make sure proper byte-enable is deasserted
                     if (    ( txPDOMst.ben(1) = '0'       )
                          or (    ( ESC_SM3_HACK_LEN_C(0) = '1' )
                              and ( txPDOMst.wrdAddr      = SM3_WADDR_END_C )
                             )
                        ) then
                        v.ctlReq.be(1) := not HBI_BE_ACT_C;
                     end if;
                  else 
                     -- illegal address; drop
                     if ( r.txPDOBst = 0 ) then
                        v.state := POLL_IRQ;
                     else
                        v.txPDORdy := '1';
                        v.txPDOBst := r.txPDOBst - 1;
                     end if;
                  end if;
               else
                  -- nothing to send ATM
                  v.state    := POLL_IRQ;
                  v.txPDOBst := 0;
               end if;
            elsif ( '1' = r.program.don ) then
               -- write to lan9254 done
               if ( r.txPDOSnt = ( ( to_integer(unsigned(ESC_SM3_LEN_C)) - 1 ) / 2 ) ) then
                  v.txPDOSnt := 0;
                  v.txPDODcm := TXPDO_UPDATE_DECIMATION_C;
               else
                  v.txPDOSnt := r.txPDOSnt + 1;
               end if;
               if ( r.txPDOBst = 0 ) then
                  v.state := POLL_IRQ;
               else
                  v.txPDORdy := '1';
                  v.txPDOBst := r.txPDOBst - 1;
               end if;
            else
               -- => initiate lan9254 register write operation

               scheduleRegXact( v, ( 0 => RWXACT( v.ctlReq.addr, v.ctlReq.be, v.ctlReq.wdata ) ) );

            end if;

      end case C_STATE;

      rin <= v;

   end process P_COMB;

   P_SEQ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
       if ( rst = '1' ) then
            r <= REG_INIT_C;
       else
            r <= rin;
       end if;
      end if;
   end process P_SEQ;

   req      <= r.ctlReq;
   rxPDOMst <= r.rxPDO;
   escState <= r.curState;
   txPDORdy <= r.txPDORdy;

debug(4  downto 0) <= std_logic_vector( to_unsigned( ControllerState'pos( r.state ), 5) );
debug(7 downto 5)  <= r.program.seq(2).val(10 downto 8);
debug(12 downto 8) <= std_logic_vector( to_unsigned( ControllerState'pos( rin.state ), 5) );
debug(15 downto 13) <= std_logic_vector(r.program.idx);
debug(20 downto 16) <= r.program.seq(0).val(8 downto 4);
debug(21)           <= r.program.don;
debug(22)           <= r.ctlReq.valid;
debug(23)           <= rep.valid;


   probe0(13 downto  0) <= r.ctlReq.addr;
   probe0(15 downto 14) <= (others => '0');
   probe0(20 downto 16) <= std_logic_vector( to_unsigned( ControllerState'pos( r.state ), 5) );
   probe0(21          ) <= r.ctlReq.rdnwr;
   probe0(22          ) <= r.ctlReq.valid;
   probe0(23          ) <= rep.valid;
   probe0(28 downto 24) <= std_logic_vector( to_unsigned( ControllerState'pos( rin.state ), 5) );
   probe0(29          ) <= r.program.don;
   probe0(30 downto 30) <= (others => '0');
   probe0(31          ) <= irq;
   probe0(63 downto 32) <= r.ctlReq.wdata;

   probe1(31 downto  0) <= rep.rdata;
   probe1(63 downto 32) <= r.lastAL;

   probe2( 2 downto  0) <= std_logic_vector(r.program.idx);
   probe2( 3 downto  3) <= (others => '0');
   probe2( 6 downto  4) <= std_logic_vector(r.program.num);
   probe2( 7 downto  7) <= (others => '0');
   probe2( 8          ) <= toSL(r.program.seq(0).rdnwr);
   probe2( 9          ) <= toSL(r.program.seq(1).rdnwr);
   probe2(10          ) <= toSL(r.program.seq(2).rdnwr);
   probe2(11 downto 11) <= (others => '0');
   probe2(15 downto 12) <= r.program.seq(0).reg.bena;
   probe2(19 downto 16) <= r.program.seq(1).reg.bena;
   probe2(23 downto 20) <= r.program.seq(2).reg.bena;
   probe2(27 downto 24) <= r.ctlReq.be;
   

   probe2(63 downto 32) <= r.program.seq(0).val;

   probe3(31 downto  0) <= r.program.seq(1).val;
   probe3(63 downto 32) <= r.program.seq(2).val;

   U_ILA_ESC : component Ila_256
      port map (
         clk    => clk,
         probe0 => probe0,
         probe1 => probe1,
         probe2 => probe2,
         probe3 => probe3
      );

   testFailed <= std_logic_vector(to_unsigned(r.testFail, testFailed'length));

end architecture rtl;
