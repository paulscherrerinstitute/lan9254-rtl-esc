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
use work.Lan9254ESCPkg.all;
use work.EEEmulPkg.all;
use work.EEPROMContentPkg.all;
use work.ESCMbxPkg.all;

-- ESC Core; ESC state machine interfacing to the LAN9254 controller

use work.IlaWrappersPkg.all;

entity Lan9254ESC is
   generic (
      CLK_FREQ_G              : real;
      DISABLE_RXPDO_G         : boolean := false;
      ENABLE_VOE_G            : boolean := false;
      ENABLE_EOE_G            : boolean := false;
      ENABLE_FOE_G            : boolean := false;
      TXPDO_MAX_UPDATE_FREQ_G : real    := 5.0E3;
      REG_IO_TEST_ENABLE_G    : boolean := true;
      -- e.g., if the user decides to use the HBI interface
      -- instead of the txPDOMst then the respective module
      -- can be disabled.
      DISABLE_TXPDO_G         : boolean := false;
      -- disable some things to just run the TXMBX test
      TXMBX_TEST_G            : boolean := false;
      NUM_EXT_HBI_MASTERS_G   : natural := 1;
      -- external HBI masters with an index < 0 have a higher
      -- priority than internal masters; external masters with
      -- index >= 0 have a lower priority than internal masters.
      EXT_HBI_MASTERS_PRI_G   : integer := 0;
      GEN_ILA_G               : boolean := true
   );
   port (
      clk         : in  std_logic;
      rst         : in  std_logic;

      req         : out Lan9254ReqType;
      rep         : in  Lan9254RepType    := LAN9254REP_INIT_C;

      -- read during INIT state (and only during INIT) of the controller FSM
      -- user may delay initialization by deasserting 'valid'.
      configReq   : in  ESCConfigReqType  := ESC_CONFIG_REQ_INIT_C;
      configAck   : out ESCConfigAckType;
      configRst   : out std_logic;

      eepWriteReq : out EEPROMWriteWordReqType;
      eepWriteAck : in  EEPROMWriteWordAckType := EEPROM_WRITE_WORD_ACK_ASSERT_C;

      eepEmul     : out std_logic;

      extHBIReq   : in  Lan9254ReqArray(NUM_EXT_HBI_MASTERS_G - 1 + EXT_HBI_MASTERS_PRI_G downto EXT_HBI_MASTERS_PRI_G) := (others => LAN9254REQ_INIT_C);
      extHBIRep   : out Lan9254RepArray(NUM_EXT_HBI_MASTERS_G - 1 + EXT_HBI_MASTERS_PRI_G downto EXT_HBI_MASTERS_PRI_G);

      escState    : out ESCStateType;
      debug       : out std_logic_vector(23 downto 0);

      txPDOMst    : in  Lan9254PDOMstType     := LAN9254PDO_MST_INIT_C;
      txPDORdy    : out std_logic;

      rxPDOMst    : out Lan9254PDOMstType     := LAN9254PDO_MST_INIT_C;
      rxPDORdy    : in  std_logic             := '1';

      txMBXMst    : in  LAN9254StrmMstType    := LAN9254STRM_MST_INIT_C;
      txMBXRdy    : out std_logic;

      rxMBXMst    : out LAN9254StrmMstType    := LAN9254STRM_MST_INIT_C;
      rxMBXRdy    : in  std_logic             := '1';
      -- current size of the mailbox (without MBX header)
      rxMBXSiz    : out unsigned(15 downto 0) := (others => '0');

      irq         : in  std_logic := EC_IRQ_ACT_C; -- defaults to polling mode

      mbxErrMst   : out MbxErrorType;
      mbxErrRdy   : in  std_logic := '1';

      testFailed  : out std_logic_vector(4 downto 0);

      stats       : out StatCounterArray(1 downto 0) := (others => STAT_COUNTER_INIT_C);

      ilaTrigOb   : out std_logic := '0';
      ilaTackOb   : in  std_logic := '1';
      ilaTrigIb   : in  std_logic := '0';
      ilaTackIb   : out std_logic := '1'
   );
end entity Lan9254ESC;

architecture rtl of Lan9254ESC is
   attribute KEEP                     : string;

   constant TXPDO_UPDATE_DECIMATION_C : natural := integer(CLK_FREQ_G/TXPDO_MAX_UPDATE_FREQ_G);

   constant HBI_WAIT_MAX_TIME_C       : real    := 200.0E-9;
   constant HBI_WAIT_MAX_C            : natural := natural( HBI_WAIT_MAX_TIME_C * CLK_FREQ_G );

   subtype  HBIWaitTimeType          is natural range 0 to HBI_WAIT_MAX_C;

   function hbiWaitTime(constant t : real) return HBIWaitTimeType is
   begin
      if ( t > HBI_WAIT_MAX_TIME_C ) then
         return HBI_WAIT_MAX_C;
      else
         return natural( t * CLK_FREQ_G );
      end if;
   end function hbiWaitTime;

   type HBIMuxStateType is ( IDLE, EXT, ESC, SM0, SM2, SM3 );

   type ControllerStateType is (
      WRDY,
      TEST,
      CONF,
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
      CHECK_TX_WORK,
      DROP_RXPDO,
      MBOX_READ,
      SM0_RELEASE,
      MBOX_SM1,
      TXMBX_SEND,
      TXMBX_REPLAY,
      TXMBX_REP_ACK
   );

   type TxMbxReplayType is ( NONE, NORMAL, SAVE_BUF, RESEND_BUF );

   -- hardware configuration register
   constant DEVICE_READY : natural := 27;
   constant HWC : EcRegType := ( addr=> x"3074", bena => (others => HBI_BE_ACT_C) );

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
      EC_AL_EREQ_SM0_IDX_C  => '0',
      EC_AL_EREQ_SM1_IDX_C  => '0',
      EC_AL_EREQ_SM2_IDX_C  => '0',
      EC_AL_EREQ_WDG_IDX_C  => '1',
      others                => '0'
   );

   constant TXMBX_MAXWORDS_C         : natural := to_integer( unsigned( ESC_SM1_LEN_C ) )/2;
   constant TXMBX_PAYLOAD_MAXWORDS_C : natural := TXMBX_MAXWORDS_C - ( MBX_HDR_SIZE_C / 2 );

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

   function smcAcceptable(
      constant expected : in  ESCVal08Type;
      constant check    : in  ESCVal08Type
   ) return boolean is
      constant ZERO_C : ESCVal08Type := (others => '0');
   begin
      return ( (expected xor check) and ESC_SMC_MSK_C ) = ZERO_C;
   end function smcAcceptable;

   function smlAcceptable(
      constant sm       : in  natural;
      constant act      : in  ESCVal16Type;
      constant reqState : in  EscStateType
   ) return boolean is
      variable lim      : unsigned(ESCVal16Type'range);
      variable val      : unsigned(ESCVal16Type'range);
   begin
      case ( sm ) is
         when 0 =>
            lim := unsigned(ESC_SM0_MXL_C);
         when 2 =>
            lim := unsigned(ESC_SM2_MXL_C);
         when 3 =>
            lim := unsigned(ESC_SM3_MXL_C);
         when others =>
            return false;
      end case;
      return (unsigned(act) <= lim);
   end function smlAcceptable;

   type RWXactType is record
      reg      : EcRegType;
      val      : std_logic_vector(31 downto 0);
      rdnwr    : boolean;
      dis      : std_logic;
   end record RWXactType;

   constant RWXACT_INIT_C : RWXactType := (
      reg      => ( addr => (others => '0'), bena => (others => '0') ),
      val      => ( others => '0' ),
      rdnwr    => true,
      dis      => '0'
   );

   function toSL(constant x : boolean) return std_logic is
   begin
      if ( x ) then return '1'; else return '0'; end if;
   end function toSL;

   function RWXACT(
      constant reg : EcRegType;
      constant val : std_logic_vector := "";
      constant dis : std_logic        := '0'
   )
   return RWXactType is
      variable rv    : RWXactType;
   begin
      rv.reg   := reg;
      rv.rdnwr := (val'length = 0);
      rv.val   := (others => '0');
      rv.dis   := dis;
      if ( not rv.rdnwr ) then
         rv.val( val'length - 1 downto 0 ) := val;
      end if;
      return rv;
   end function RWXACT;

   function RWXACT(
      constant addr: unsigned;
      constant bena: std_logic_vector( 3 downto 0);
      constant val : std_logic_vector := "";
      constant dis : std_logic        := '0'
   )
   return RWXactType is
      variable rv    : RWXactType;
      variable reg   : EcRegType;
   begin
      reg.addr                          := (others => '0');
      reg.addr(addr'length -1 downto 0) := std_logic_vector(addr);
      reg.bena                          := bena;
      return RWXACT( reg, val, dis );
   end function RWXACT;

   type RWXactArray is array (natural range <>) of RWXactType;

   constant LD_XACT_MAX_C          : natural := 3;
   constant XACT_MAX_C             : natural := 2**LD_XACT_MAX_C;

   constant TXPDO_BURST_MAX_C      : natural := 16;

   type RWXactSeqType is record
      seq      : RWXactArray(0 to XACT_MAX_C - 1);
      idx      : unsigned(LD_XACT_MAX_C - 1 downto 0);
      num      : unsigned(LD_XACT_MAX_C - 1 downto 0);
      dly      : HBIWaitTimeType;
      don      : std_logic;
      ret      : ControllerStateType;
   end record RWXactSeqType;

   constant RWXACT_SEQ_INIT_C : RWXactSeqType := (
      seq      => (others => RWXACT_INIT_C),
      idx      => (others => '0'),
      num      => (others => '0'),
      dly      => 0,
      don      => '0',
      ret      => POLL_IRQ
   );

   type RegType is record
      state                : ControllerStateType;
      config               : ESCConfigReqType;
      configAck            : ESCConfigAckType;
      sm0Len               : ESCVal16Type;
      testPhas             : natural range 0 to 6;
      testFail             : natural range 0 to 31;
      reqState             : ESCStateType;
      errAck               : std_logic;
      curState             : ESCStateType;
      errSta               : std_logic;
      alErr                : ESCVal16Type;
      ctlReq               : Lan9254ReqType;
      program              : RWXactSeqType;
      smDis                : std_logic_vector( 3 downto 0);
      rptAck               : std_logic_vector( 3 downto 0);
      lastAL               : std_logic_vector(31 downto 0);
      emask                : std_logic_vector(31 downto 0);
      rxPDORst             : std_logic;
      txPDORst             : std_logic;
      txMBXStrb            : std_logic;
      txMBXLEna            : std_logic;
      txMBXTEna            : std_logic;
      txMBXLen             : unsigned(15 downto 0);
      txMBXWAddr           : natural range 0 to TXMBX_MAXWORDS_C - 1;
      txMBXRdy             : std_logic;
      txMBXMAck            : std_logic;
      txMBXMRep            : std_logic;
      txMBXReplay          : TxMbxReplayType;
      txMBXLast            : std_logic;
      txMBXOverrun         : std_logic;
      txMBXRst             : std_logic;
      rxMBXCnt             : unsigned(2 downto 0);
      rxMBXTyp             : std_logic_vector(3 downto 0);
      rxMBXLen             : unsigned(15 downto 0);
      mbxErr               : MbxErrorType;
      decim                : natural;
      hbiWaitTimer         : HBIWaitTimeType;
      eepWriteReqVld       : std_logic;
      eepEmulActive        : std_logic;
      configRst            : std_logic;
      wasRdy               : std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state                => WRDY,
      config               => ESC_CONFIG_REQ_INIT_C,
      configAck            => ESC_CONFIG_ACK_INIT_C,
      sm0Len               => (others => '0'),
      testPhas             => 0,
      testFail             => 0,
      reqState             => INIT,
      errAck               => '0',
      curState             => INIT,
      errSta               => '0',
      alErr                => EC_ALER_OK_C,
      ctlReq               => LAN9254REQ_INIT_C,
      program              => RWXACT_SEQ_INIT_C,
      smDis                => (others => '1'),
      rptAck               => (others => '0'),
      lastAL               => (others => '0'),
      emask                => EC_AL_EMSK_INIT_C,
      rxPDORst             => '1',
      txPDORst             => '1',
      txMBXStrb            => '0',
      txMBXLEna            => '0',
      txMBXTEna            => '0',
      txMBXLen             => (others => '0'),
      txMBXWAddr           =>  0,
      txMBXRdy             => '0',
      txMBXRst             => '1',
      txMBXMAck            => '0',
      txMBXMRep            => '0',
      txMBXReplay          => NONE,
      txMBXLast            => '0',
      txMBXOverrun         => '0',
      rxMBXCnt             => (others => '0'),
      rxMBXLen             => (others => '0'),
      rxMBXTyp             => (others => '0'),
      mbxErr               => MBX_ERROR_INIT_C,
      decim                => 0,
      hbiWaitTimer         => 0,
      eepWriteReqVld       => '0',
      eepEmulActive        => '0',
      configRst            => '1',
      wasRdy               => '0'
   );

   type HBIMuxRegType is record
      hbiState             : HBIMuxStateType;
      extSel               : integer range extHBIReq'low to extHBiReq'high;
   end record HBIMuxRegType;

   constant HBIMUX_REG_INIT_C : HBIMuxRegType := (
      hbiState             => IDLE,
      extSel               => extHBIReq'low
   );

   procedure scheduleRegXact(
      variable endp : inout RegType;
      constant prog : in    RWXactArray;
      constant dly  : in    HBIWaitTimeType := 0
   ) is
   begin
      endp                         := endp;
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
      lan9254HBIRead( rdOut, rdInp, reg.addr, reg.bena, '0', enbl );
   end procedure readReg;

   procedure writeReg(
      variable wrOut: inout Lan9254ReqType;
      signal   wrInp: in    Lan9254RepType;
      constant reg  : in    EcRegType;
      constant wrDat: in    std_logic_vector(31 downto 0);
      constant enbl : in    boolean                       := true
   ) is
   begin
      lan9254HBIWrite( wrOut, wrInp, reg.addr, wrDat, reg.bena, '0', enbl );
   end procedure writeReg;

   procedure testRegisterIO(
      variable v   : inout RegType;
      signal   r   : in    RegType;
      signal   rpl : in    Lan9254RepType
   ) is
   begin
      v := v;
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
               v.testPhas := r.testPhas + 1;
            end if;

         when 3 =>
            if ( r.ctlReq.valid = '0' ) then
               v.ctlReq.addr := unsigned( WB1.addr(v.ctlReq.addr'range) );
               v.ctlReq.be   := WB1.bena;
            end if;
            lan9254HBIRead( v.ctlReq, rpl );
            if ( ( r.ctlReq.valid and rpl.valid ) = '1' ) then
               if ( v.ctlReq.data( 7 downto  0) /= x"22" ) then
                  assert false report "ReadEPa8 readback mismatch" severity failure;
                  if ( v.testFail = 0 ) then v.testFail :=16; end if;
               end if;
               v.testPhas := r.testPhas + 1;
            end if;

         when 4 =>
            if ( r.ctlReq.valid = '0' ) then
               v.ctlReq.addr := unsigned( WW1.addr(v.ctlReq.addr'range) );
               v.ctlReq.be   := WW1.bena;
               v.ctlReq.data := x"0000abcd";
            end if;
            lan9254HBIWrite( v.ctlReq, rpl );
            if ( ( r.ctlReq.valid and rpl.valid ) = '1' ) then
               v.testPhas := r.testPhas + 1;
            end if;

         when 5 =>
            if ( r.ctlReq.valid = '0' ) then
               v.ctlReq.addr := unsigned( WB3.addr(v.ctlReq.addr'range) );
               v.ctlReq.be   := WB3.bena;
            end if;
            lan9254HBIRead( v.ctlReq, rpl );
            if ( ( r.ctlReq.valid and rpl.valid ) = '1' ) then
               if ( v.ctlReq.data( 7 downto  0) /= x"ab" ) then
                  assert false report "ReadEPa8_2 readback mismatch" severity failure;
                  if ( v.testFail = 0 ) then v.testFail :=17; end if;
               end if;

               if ( v.testFail = 0 ) then
                  v.testPhas := 0;
                  v.state    := CONF;
               else
                  v.testPhas := r.testPhas + 1; -- go into limbo
               end if;
            end if;

         when others =>
            -- remain here
      end case CASE_TEST;
   end procedure testRegisterIO;

   -- An EEPROM with 5088 bits eats up 303 slice LUTs (depends on contents, probably
   -- since this was read-only).
   signal     eeprom          : EEPromArray(EEPROM_INIT_C'range) := EEPROM_INIT_C;

   signal     rHBIMux         : HBIMuxRegType                 := HBIMUX_REG_INIT_C;
   signal     rinHBIMux       : HBIMuxRegType;

   signal     r               : RegType                       := REG_INIT_C;
--   attribute  KEEP       of r : signal is "TRUE"; -- This messed things really up; ILA was not detected
   signal     rin             : RegType;

   signal     rxMBXDebug      : std_logic_vector(2 downto 0)  := (others => '0');

   signal     stalled         : std_logic;
   constant   STALL_C         : natural := 15;
   signal     stalledCount    : natural range 0 to STALL_C;

   signal     txMBXBufWBEh    : std_logic;
   signal     txMBXBufWEna    : std_logic;
   signal     txMBXBufWRdy    : std_logic;
   signal     txMBXBufRDat    : std_logic_vector(15 downto 0);
   signal     txMBXBufHaveBup : boolean;

   signal     rxPDOTrg        : std_logic := '0';
   signal     rxPDOReq        : Lan9254ReqType := LAN9254REQ_INIT_C;
   signal     rxPDORep        : Lan9254RepType := LAN9254REP_INIT_C;
   signal     txPDOReq        : Lan9254ReqType := LAN9254REQ_INIT_C;
   signal     txPDORep        : Lan9254RepType := LAN9254REP_INIT_C;

   signal     rxMBXAck        : std_logic         := '1';
   signal     rxMBXTrg        : std_logic         := '0';
   signal     rxMBXReq        : Lan9254ReqType    := LAN9254REQ_INIT_C;
   signal     rxMBXRep        : Lan9254RepType    := LAN9254REP_INIT_C;
   signal     rxMBXPDO        : Lan9254PDOMstType := LAN9254PDO_MST_INIT_C;
   signal     rxMBXLen        : unsigned(15 downto 0);
   signal     rxMBXTyp        : std_logic_vector(3 downto 0);

   signal     reqLoc          : Lan9254ReqType;
   signal     repLoc          : Lan9254RepType;

begin

   assert ESC_SM1_SMA_C(0) = '0' report "TXMBX address must be word aligned" severity failure;
   assert ESC_SM1_LEN_C(0) = '0' report "TXMBX length  must be word aligned" severity failure;
   assert ESC_SM2_SMA_C(0) = '0' report "RXPDO address must be word aligned" severity failure;
   assert ESC_SM3_SMA_C(0) = '0' report "TXPDO address must be word aligned" severity failure;

   txMBXBufWEna <= ( txMBXMst.valid and r.txMBXRdy and not r.txMBXOverrun ) or r.txMBXStrb;
   txMBXBufWBEh <= ( not r.txMBXRdy ) or txMBXMst.ben(1);
   txMBXRdy     <= r.txMBXRdy;

   P_HBI_COMB : process ( rHBIMux, r, rep, reqLoc, rxPDOReq, rxMBXReq, txPDOReq, extHBIReq ) is
      variable v : HBIMuxRegType;
   begin
      v               := rHBIMux;

      rxPDORep        <= rep;
      rxPDORep.valid  <= '0';
      txPDORep        <= rep;
      txPDORep.valid  <= '0';
      rxMBXRep        <= rep;
      rxMBXRep.valid  <= '0';
      repLoc          <= rep;
      repLoc.valid    <= '0';
      for i in extHBIRep'range loop
         extHBIRep(i)       <= rep;
         extHBIRep(i).valid <= '0';
      end loop;

      reqLoc          <= r.ctlReq;

      if ( rHBIMux.hbiState = IDLE ) then
         -- if the HBI is free then arbitrate access
         if    ( txPDOReq.valid  = '1' ) then
            v.hbiState := SM3;
         elsif ( rxPDOReq.valid  = '1' ) then
            v.hbiState := SM2;
         elsif ( rxMBXReq.valid  = '1' ) then
            v.hbiState := SM0;
         elsif ( r.ctlReq.valid  = '1' ) then
            v.hbiState := ESC;
         end if;

         L_ARB_EXT : for i in extHBIReq'range loop
           if (    (extHBIReq(i).valid = '1')
               and ( (v.hbiState = IDLE) or ( i < 0 ) ) ) then
              v.hbiState := EXT;
              v.extSel   := i;
              exit L_ARB_EXT;
           end if;
         end loop L_ARB_EXT;
      end if;

      case ( v.hbiState ) is
         when SM3 =>
            reqLoc         <= txPDOReq;
            txPDORep.valid <= rep.valid;

         when SM2 =>
            reqLoc         <= rxPDOReq;
            rxPDORep.valid <= rep.valid;

         when SM0 =>
            reqLoc         <= rxMBXReq;
            rxMBXRep.valid <= rep.valid;

         when EXT =>
            reqLoc                    <= extHBIReq(v.extSel);
            extHBIRep(v.extSel).valid <= rep.valid;

         when others =>
            repLoc.valid   <= rep.valid;
      end case;

      if ( ( (not reqLoc.lock) and rep.valid ) = '1' ) then
         -- HBI access terminated; release the HBI
         v.hbiState        := IDLE;
      end if;

      rinHBIMux  <= v;
   end process P_HBI_COMB;

   P_HBI_SEQ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
              rHBIMux <= HBIMUX_REG_INIT_C;
         else
              rHBIMux <= rinHBIMux;
         end if;
      end if;
   end process P_HBI_SEQ;

   P_COMB : process (
         r, repLoc, eeprom, irq,
         mbxErrRdy,
         rxPDORdy,
         txMBXMst,
         rxMBXRdy,
         txMBXBufWRdy, txMBXBufRDat, txMBXBufHaveBup,
         configReq,
         eepWriteAck
   ) is
      variable v         : RegType;
      variable val       : std_logic_vector(31 downto 0);
      variable xct       : RWXactType;
   begin
      v             := r;
      val           := (others => '0');
      xct           := RWXACT_INIT_C;
      v.txMBXMAck   := '0';
      v.txMBXMRep   := '0';
      v.txMBXLEna   := '0';
      v.txMBXTEna   := '0';
      v.txMBXStrb   := '0';
      v.program.don := '0';

      rxPDOTrg      <= '0';
      rxMBXTrg      <= '0';

      mbxErrMst     <= r.mbxErr;
      if ( ( mbxErrRdy and r.mbxErr.vld ) = '1' ) then
         v.mbxErr.vld := '0';
      end if;

      if ( r.hbiWaitTimer /= 0 ) then
         v.hbiWaitTimer := r.hbiWaitTimer - 1;
      end if;

      C_STATE : case ( r.state ) is
         when WRDY =>
            v.state := TEST;
--            if ( '0' = r.program.don ) then
--               scheduleRegXact( v, ( 0 => RWXACT( HWC ) ) );
--            else
--               v.wasRdy := r.program.seq(0).val( DEVICE_READY );
--               if ( v.wasRdy = '1' ) then
--                  v.state  := TEST;
--               end if;
--            end if;

         when TEST =>
            if ( REG_IO_TEST_ENABLE_G ) then
               testRegisterIO(v, r, repLoc);
            else
               if ( '0' = r.program.don ) then
                  scheduleRegXact( v,
                     (
                        0 => RWXACT( RD0 ), -- read twice (after reset)
                        1 => RWXACT( RD0 )
                     )
                  );
               else
                  v.state := CONF;
               end if;
            end if;

         when CONF =>
            if ( '0' = r.program.don ) then
               scheduleRegXact( v, ( 0 => RWXACT( EC_REG_EEP_CSR_C ) ) );
            else
               v.eepEmulActive := r.program.seq(0).val( EC_EEP_CSR_EMUL_IDX_C );
report "EEPROM emulation active: " & std_logic'image( v.eepEmulActive );
               v.configRst     := '0';
               v.configAck.ack := '1';
               v.state         := INIT;
            end if;

         when INIT =>
            if ( r.configAck.ack = '1' ) then
               if ( configReq.valid = '1' ) then
                  v.config        := configReq;
                  v.configAck.ack := '0';
               end if;
            else
               if ( '0' = r.program.don ) then
                  scheduleRegXact(
                     v,
                     (
                        0 => RWXACT( EC_REG_AL_EMSK_C, r.emask           ),
                        1 => RWXACT( EC_REG_IRQ_ENA_C, EC_IRQ_ENA_INIT_C ),
                        2 => RWXACT( EC_REG_IRQ_CFG_C, EC_IRQ_CFG_INIT_C )
                     )
                  );
               else
                  v.state := UPDATE_AS;
               end if;
            end if;

         when POLL_IRQ =>
            -- wait for an interrupt; this leaves the lan9254 HBI alone
            if ( irq = EC_IRQ_ACT_C ) then
               v.state := POLL_AL_EVENT;
            else
               -- if we operate in fully polled mode (IRQ permanently asserted)
               -- then we never get here; CHECK_TX_WORK is also entered if
               -- polling the event status yields no work
               v.state := CHECK_TX_WORK;
            end if;

         when POLL_AL_EVENT =>
            if ( '0' = r.program.don ) then
               -- read AL register
               scheduleRegXact( v, ( 0 => RWXACT( EC_REG_AL_EREQ_C ) ) );
            else
               -- cache AL readback value
               v.lastAL := r.program.seq(0).val;
               if ( (r.program.seq(0).val and r.emask) = x"0000_0000" ) then
                  -- no more events pending; maybe there is TX work to do?
                  v.state  := CHECK_TX_WORK;
               else
                  v.state  := HANDLE_AL_EVENT;
               end if;
            end if;

         -- ************ NOTE ************
         -- All events handled here must be
         -- enabled in EC_REG_AL_EMSK_C
         -- ******************************
         when HANDLE_AL_EVENT =>
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
            elsif ( r.lastAL(EC_AL_EREQ_SM0_IDX_C) = '1' ) then
               v.lastAL(EC_AL_EREQ_SM0_IDX_C) := '0';
               v.state                        := MBOX_READ;
            elsif ( r.lastAL(EC_AL_EREQ_SM1_IDX_C) = '1' ) then
               v.lastAL(EC_AL_EREQ_SM1_IDX_C) := '0';
               v.state                        := MBOX_SM1;
report "SM1 EVENT";
            elsif ( r.lastAL(EC_AL_EREQ_SM2_IDX_C) = '1' ) then
               v.lastAL(EC_AL_EREQ_SM2_IDX_C) := '0';
               if ( ( r.curState = OP ) and ( not DISABLE_RXPDO_G ) ) then
                  rxPDOTrg <= '1';
                  v.state  := HANDLE_AL_EVENT;
               else
                  v.state  := DROP_RXPDO;
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
            else
               v.state := POLL_AL_EVENT; -- keep polling AL until nothing is pending
            end if;

         when HANDLE_WD_EVENT =>
            if ( '0' = r.program.don ) then
               scheduleRegXact( v, ( 0 => RWXACT( EC_REG_WD_PDST_C ) ) );
            else
               if ( r.program.seq(0).val(0) = '0' ) then
report "WATCHDOG EVENT: " & std_logic'image( r.program.seq(0).val(0) );
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
                  -- start boot mailbox
                  v.txMBXRst    := '0';
                  v.txMBXReplay := NONE;
                  v.smDis(1)    := '0';
                  v.smDis(0)    := '0';
                  v.state       := CHECK_MBOX;
report "starting BOOT MBOX";
               else
                  if ( r.curState = OP ) then
                     -- stop output           # FIXME
                     v.rxPDORst := '1';
                     v.reqState := SAFEOP;
                  end if;
                  v.errSta := '1';
                  v.alErr  := EC_ALER_INVALIDSTATECHANGE_C;
               end if;
            elsif ( r.curState = BOOT ) then
               if ( r.reqState = INIT ) then
                  -- stop boot mailbox
                  v.txMBXRst    := '1';
                  v.smDis(1)    := '1';
                  v.smDis(0)    := '1';
                  v.state       := EN_DIS_SM;
               else
                  -- stop boot mailbox       # SOES doesn't do that -- should we?
                  v.errSta      := '1';
                  v.reqState    := PREOP;
                  v.alErr       := EC_ALER_INVALIDSTATECHANGE_C;
               end if;
            elsif ( ESCStateType'pos( r.reqState ) - ESCStateType'pos( r.curState ) >  1 ) then
                  v.errSta      := '1';
                  v.alErr       := EC_ALER_INVALIDSTATECHANGE_C;
            elsif ( ESCStateType'pos( r.reqState ) - ESCStateType'pos( r.curState ) >= 0 ) then
               if ( ( r.reqState = PREOP ) and ( r.curState /= PREOP ) ) then
                  v.txMBXRst    := '0';
                  v.txMBXReplay := NONE;
                  v.smDis(1)    := '0';
                  v.smDis(0)    := '0';
                  v.state       := CHECK_MBOX;
report "starting MBOX";
               elsif ( ( r.reqState = SAFEOP ) ) then
                  v.txMBXRst    := '0';
                  v.txPDORst    := '0'; -- start input
                  v.smDis(3)    := '0';
                  v.state       := CHECK_SM;
report "starting SM23";
               elsif ( ( r.reqState = OP ) and ( r.curState /= OP ) ) then
                  v.txMBXRst    := '0';
                  v.rxPDORst    := '0'; -- start output
                  v.txPDORst    := '0'; -- start input
                  v.smDis(2)    := '0';
                  v.state       := EN_DIS_SM;
               end if;
            else -- state downshift
               if ( ( r.reqState < OP ) and ( r.curState = OP ) ) then
                  -- stop output
                  v.rxPDORst    := '1';
                  v.smDis(2)    := '1';
               end if;
               if ( ( r.reqState < SAFEOP ) and ( r.curState >= SAFEOP ) ) then
                  -- stop input, stop output
                  v.smDis(3)    := '1';
                  v.txPDORst    := '1';
                  v.rxPDORst    := '1';
               end if;
               if ( ( r.reqState < PREOP  ) and ( r.curState >= PREOP  ) ) then
                  v.txMBXRst    := '1';
                  v.txPDORst    := '1';
                  v.rxPDORst    := '1';
                  v.smDis(1)    := '1';
                  v.smDis(0)    := '1';
               end if;
               v.state := EN_DIS_SM;
            end if;

         when XACT =>
            if ( r.hbiWaitTimer = 0 ) then
               xct := r.program.seq(to_integer(r.program.idx));
               if ( xct.dis = '0' ) then
                  if ( xct.rdnwr ) then
                     readReg( v.ctlReq, repLoc, xct.reg );
                     if ( ( r.ctlReq.valid and repLoc.valid ) = '1' ) then
                        v.program.seq(to_integer(r.program.idx)).val := v.ctlReq.data;
                     end if;
                  else
--report "WRITE " & integer'image(to_integer(unsigned(xct.reg.addr))) & " " & integer'image(to_integer(signed(xct.val)));
                     writeReg( v.ctlReq, repLoc, xct.reg, xct.val );
                  end if;
               end if;
               if ( ( ( r.ctlReq.valid and repLoc.valid ) or xct.dis  ) = '1' ) then
                  v.ctlReq.valid := '0';
                  v.hbiWaitTimer := r.program.dly;
                  if ( r.program.idx = r.program.num ) then
                     v.state        := r.program.ret;
                     v.program.don  := '1';
                  else
                     v.program.idx  := r.program.idx + 1;
                  end if;
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
               v.rptAck(2)         := r.program.seq(3).val(EC_SM_ACT_RPT_IDX_C);
               v.smDis (2)         := not r.program.seq(3).val(EC_SM_ACT_DIS_IDX_C);
               v.rptAck(3)         := r.program.seq(7).val(EC_SM_ACT_RPT_IDX_C);
               v.smDis (3)         := not r.program.seq(7).val(EC_SM_ACT_DIS_IDX_C);

               if (   (    r.program.seq(3).val(EC_SM_ACT_DIS_IDX_C) = '0'                           ) -- deactivated
                   or (    ( (ESC_SM2_ACT_C and r.program.seq(3).val(EC_SM_ACT_DIS_IDX_C)) = '1' )
                       and ( ESC_SM2_SMA_C     =  r.program.seq(0).val(ESC_SM2_SMA_C'range) )
                       and smlAcceptable( 2, r.program.seq(1).val(ESC_SM2_LEN_C'range), r.reqState )
                       and smcAcceptable( ESC_SM2_SMC_C, r.program.seq(2).val(ESC_SM2_SMC_C'range) ) )
               ) then
                  -- PASSED CHECK
                  v.config.sm2Len := r.program.seq(1).val(ESC_SM2_LEN_C'range);
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
               if (   (    r.program.seq(7).val(EC_SM_ACT_DIS_IDX_C) = '0'                           ) -- deactivated
                   or (    ( (ESC_SM3_ACT_C and r.program.seq(7).val(EC_SM_ACT_DIS_IDX_C)) = '1' )
                       and ( ESC_SM3_SMA_C     =  r.program.seq(4).val(ESC_SM3_SMA_C'range) )
                       and smlAcceptable( 3, r.program.seq(5).val(ESC_SM3_LEN_C'range), r.reqState )
                       and smcAcceptable( ESC_SM3_SMC_C, r.program.seq(6).val(ESC_SM3_SMC_C'range) ) )
               ) then
                  -- PASSED CHECK
                  v.config.sm3Len := r.program.seq(5).val(ESC_SM3_LEN_C'range);
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
               v.rptAck(0)         := r.program.seq(3).val(EC_SM_ACT_RPT_IDX_C);
               v.smDis (0)         := not r.program.seq(3).val(EC_SM_ACT_DIS_IDX_C);
               v.rptAck(1)         := r.program.seq(7).val(EC_SM_ACT_RPT_IDX_C);
               v.smDis (1)         := not r.program.seq(7).val(EC_SM_ACT_DIS_IDX_C);
               if (   ( (ESC_SM0_ACT_C or  r.program.seq(3).val(EC_SM_ACT_DIS_IDX_C)) = '0'   ) -- deactivated
                   or (    ( (ESC_SM0_ACT_C and r.program.seq(3).val(EC_SM_ACT_DIS_IDX_C)) = '1'     )
                       and ( ESC_SM0_SMA_C     =  r.program.seq(0).val(ESC_SM0_SMA_C'range)          )
                       and smlAcceptable( 0, r.program.seq(1).val(ESC_SM0_LEN_C'range), r.reqState   )
                       and smcAcceptable( ESC_SM0_SMC_C, r.program.seq(2).val(ESC_SM0_SMC_C'range) ) )
               ) then
                  v.sm0Len := r.program.seq(1).val(ESC_SM0_LEN_C'range);
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
               if (   ( (ESC_SM1_ACT_C or  r.program.seq(7).val(EC_SM_ACT_DIS_IDX_C)) = '0'   ) -- deactivated
                   or (    ( (ESC_SM1_ACT_C and r.program.seq(7).val(EC_SM_ACT_DIS_IDX_C)) = '1' )
                       and ( ESC_SM1_SMA_C     =  r.program.seq(4).val(ESC_SM1_SMA_C'range) )
                       and ( ESC_SM1_LEN_C     =  r.program.seq(5).val(ESC_SM1_LEN_C'range) )
                       and smcAcceptable( ESC_SM1_SMC_C, r.program.seq(6).val(ESC_SM1_SMC_C'range) ) )
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
               v.emask( EC_AL_EREQ_SM0_IDX_C ) := not r.smDis(0);
               v.emask( EC_AL_EREQ_SM1_IDX_C ) := not r.smDis(1);
               v.emask( EC_AL_EREQ_SM2_IDX_C ) := not r.smDis(2);
               scheduleRegXact(
                  v,
                  (
                     0 => RWXACT( EC_REG_AL_EMSK_C  , v.emask                  ),
                     1 => RWXACT( EC_REG_SM_PDI_F(0), r.rptAck(0) & r.smDis(0) ),
                     2 => RWXACT( EC_REG_SM_PDI_F(1), r.rptAck(1) & r.smDis(1) ),
                     3 => RWXACT( EC_REG_SM_PDI_F(2), r.rptAck(2) & r.smDis(2) ),
                     4 => RWXACT( EC_REG_SM_PDI_F(3), r.rptAck(3) & r.smDis(3) )
                  )
               );
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
               v.state      := HANDLE_AL_EVENT;
               v.rptAck(0)  := r.program.seq(0).val(EC_SM_ACT_RPT_IDX_C);
               v.rptAck(1)  := r.program.seq(1).val(EC_SM_ACT_RPT_IDX_C);
               v.rptAck(2)  := r.program.seq(2).val(EC_SM_ACT_RPT_IDX_C);
               v.rptAck(3)  := r.program.seq(3).val(EC_SM_ACT_RPT_IDX_C);
               if (    ( r.program.seq(0).val(EC_SM_ACT_DIS_IDX_C) /= not r.smDis(0) )
                    or ( r.program.seq(1).val(EC_SM_ACT_DIS_IDX_C) /= not r.smDis(1) )
                    or ( r.program.seq(2).val(EC_SM_ACT_DIS_IDX_C) /= not r.smDis(2) )
                    or ( r.program.seq(3).val(EC_SM_ACT_DIS_IDX_C) /= not r.smDis(3) )
                  ) then
                  if ( r.curState = SAFEOP or r.curState = OP ) then
                     v.state := CHECK_SM;
                  elsif ( r.curState = PREOP or r.curState = BOOT ) then
                     v.state := CHECK_MBOX;
                  end if;
               elsif ( r.curState /= INIT and ( r.rptAck(1) /= r.program.seq(1).val(EC_SM_ACT_RPT_IDX_C) ) ) then
                  -- send REPEAT REQ.
                  if ( txMBXBufHaveBup ) then
                     -- reset; we toggle after we are done resending
                     v.rptAck(1)       := r.rptAck(1);

                     v.state           := TXMBX_REPLAY;
                     if ( txMBXBufWRdy = '0' ) then
                        -- last buffer send has not been ACKed yet
                        v.txMBXReplay  := SAVE_BUF;
                     else
                        v.txMBXReplay  := NORMAL;
                     end if;
                     v.txMBXMRep       := '1';
                  end if;
               end if;
            end if;

            -- No need to check the 'emulation' bit in EEP_CSR_C; we don't get
            -- an EEP event when not in emulation mode.
            -- NOTE: when in emulation mode we write to the *real* eeprom. This
            --       allows us to boot-strap or fix a fault EEPROM from emulation
            --       mode!
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
                     v.eepWriteReqVld := '1';
                     v.state          := EEP_WRITE;
report "EEP_WRITE CSR" & integer'image(to_integer(signed(r.program.seq(0).val)));
report "         VLO" & integer'image(to_integer(signed(r.program.seq(1).val)));
report "         VHI" & integer'image(to_integer(signed(r.program.seq(2).val)));

                  when EEPROM_READ_C | EEPROM_RELD_C  =>
                     readEEPROMEmul( eeprom, r.program.seq(1).val, v.program.seq(0).val, v.program.seq(1).val );
                     v.state := EEP_READ;
report "EEP_READ CSR" & integer'image(to_integer(signed(r.program.seq(0).val)));
report "         VLO" & integer'image(to_integer(signed(r.program.seq(1).val)));
report "         VHI" & integer'image(to_integer(signed(r.program.seq(2).val)));

                  when others  =>
                     report "UNSUPPORTED EE EMULATION COMMAND " & integer'image(to_integer(unsigned(r.program.seq(2).val)))
                        severity warning;
                     v.state := HANDLE_AL_EVENT;
               end case;
            end if;

         when EEP_WRITE =>
            if ( r.eepWriteReqVld = '1' ) then
               if ( eepWriteAck.ack = '1' ) then
                  v.eepWriteReqVld := '0';
               end if;
            else
               if ( '0' = r.program.don ) then
                  scheduleRegXact( v, ( 0 => RWXACT( EC_REG_EEP_CSR_C, r.program.seq(2).val ) ) );
               else
                  v.state := HANDLE_AL_EVENT;
               end if;
            end if;

        when EEP_READ =>
            if ( '0' = r.program.don ) then
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


         when CHECK_TX_WORK =>

            v.state := POLL_IRQ;
            -- maybe the TXPDO or MBX needs to be updated ?
            if    ( ( ( txMBXMst.valid and txMBXBufWRdy and not r.txMBXRst ) = '1' ) and ( r.txMBXReplay = NONE ) ) then
report "post MBOX";
               -- master has data, mailbox buffer can accept data and is running
               -- => start mailbox TX

               -- enable latching the payload length into the buffer memory
               v.txMBXLEna    := '1';
               -- initially, we assume the message covers the full length of the mailbox
               -- so that if this is indeed true when the last word is written (which triggers
               -- the SM) everything is fine. If OTOH, it turns out that the message is shorter
               -- then we can re-adjust the length in the header later since writing the last
               -- byte has not triggered the SM yet.
               v.txMBXLen     := to_unsigned(2*TXMBX_PAYLOAD_MAXWORDS_C, v.txMBXLen'length);
               -- cannot accept data yet (write header first)
               v.txMBXRdy     := '0';
               -- reset address pointer, last and overrun flags
               v.txMBXWAddr   :=  0 ;
               v.txMBXLast    := '0';
               v.txMBXOverrun := '0';
               -- byte-enables are computed on the fly; almost always the full width
               -- is used; only if the last payload byte is the second-last byte of
               -- the mailbox then we have to be careful to avoid triggering the SM
               -- (so the correct length can be re-written). Only in that special case
               -- is the 'be' reduced to a single lane.
               v.ctlReq.be    := HBI_BE_W0_C;
               -- enable latching the mailbox type (from the master interface)
               v.txMBXTEna    := '1';
               v.state        := TXMBX_SEND;
            end if;

         when DROP_RXPDO =>
            if ( '0' = r.program.don ) then
               scheduleRegXact(
                  v,
                  (
                     0 => RWXACT( EC_BYTE_REG_F( ESC_SM2_SMA_C, r.config.sm2Len, -1 ) )
                  )
               );
            else
               v.state := HANDLE_AL_EVENT;
            end if;

         when MBOX_READ =>
            if    ( '0' = r.program.don ) then
               scheduleRegXact( v,
                  (
                     0 => RWXACT( EC_REG_SM_STA_F( 0 )                  ),
                     1 => RWXACT( EC_WORD_REG_F(ESC_SM0_SMA_C, x"0000") ),
                     2 => RWXACT( EC_WORD_REG_F(ESC_SM0_SMA_C, x"0002") ),
                     3 => RWXACT( EC_WORD_REG_F(ESC_SM0_SMA_C, x"0004") )
                  )
               );
            else

report  "RX-MBX Header: len "
       & toString(r.program.seq(1).val(15 downto 0))
       & ", cnt "
       & toString(r.program.seq(3).val(15 downto 12))
       & ", typ "
       & toString(r.program.seq(3).val(11 downto  8))
       & ", pri/channel "
       & toString(r.program.seq(3).val( 7 downto  0))
;
               v.rxMBXLen := unsigned(r.program.seq(1).val(15 downto  0));
               v.rxMBXCnt := unsigned(r.program.seq(3).val(MBX_CNT_RNG_T));
               v.rxMBXTyp := r.program.seq(3).val(11 downto 8);
               if ( v.rxMBXLen > to_integer(unsigned( r.sm0Len ) - MBX_HDR_SIZE_C) ) then
                  v.state    := HANDLE_AL_EVENT;
                  if ( v.mbxErr.vld = '0' ) then
                     v.mbxErr.code := MBX_ERR_CODE_INVALIDSIZE_C;
                     v.mbxErr.vld  := '1';
                  end if;
               elsif ( ( v.rxMBXCnt /= "000" ) and ( v.rxMBXCnt = r.rxMBXCnt ) ) then
                  -- redundant  transmission; drop
                  v.state           := SM0_RELEASE;
               elsif (    (    ( ENABLE_EOE_G and ( MBX_TYP_EOE_C = v.rxMBXTyp ) )
                            or ( ENABLE_VOE_G and ( MBX_TYP_VOE_C = v.rxMBXTyp ) )
                            or ( ENABLE_FOE_G and ( MBX_TYP_FOE_C = v.rxMBXTyp ) )
                          )
                      and r.txMBXRst = '0'
                     ) then
                  rxMBXTrg <= '1';
                  v.state  := HANDLE_AL_EVENT;
               else
                  v.state    := SM0_RELEASE;
                  if ( v.mbxErr.vld = '0' ) then
                     v.mbxErr.code := MBX_ERR_CODE_UNSUPPORTEDPROTOCOL_C;
                     v.mbxErr.vld  := '1';
                  end if;
               end if;
            end if;

         when SM0_RELEASE =>
            if ( '0' = r.program.don ) then
               scheduleRegXact( v, ( 0 => RWXACT( EC_BYTE_REG_F( ESC_SM0_SMA_C, r.sm0Len, -1 ) ) ) );
            else
               v.state := HANDLE_AL_EVENT;
            end if;

         when MBOX_SM1 =>
            if ( '0' = r.program.don ) then
               scheduleRegXact( v,
                  (
                     0 => RWXACT( EC_REG_SM_STA_F( 1 )                ),
                     1 => RWXACT( EC_WORD_REG_F(ESC_SM1_SMA_C, x"0000"), x"fafa" )
                  )
               );
            else
report "TXMBOX now status " & toString( r.program.seq(0).val(7 downto 0) );
               v.txMBXMAck := '1';
               if ( r.txMBXReplay = RESEND_BUF ) then
                  -- txMBXMAck restores the buffer that has been previously written
                  -- but had not been acked by the master when we received a repeat request
                  v.state := TXMBX_REPLAY;
               else
                  v.state := HANDLE_AL_EVENT;
               end if;
            end if;

         when TXMBX_SEND =>
            HANDLE_TXMBX : if ( r.txMBXRdy = '1' ) then
               -- this case handles reading the txMBXMst stream into
               -- the ESCTxMbxBuf buffer memory
               if ( txMBXMst.valid = '1' ) then
                  if ( r.txMBXOverrun = '0' ) then
                     -- stop the input stream until the current word
                     -- has also been written into the LAN9254
                     v.txMBXRdy    := '0';
                     -- remember the 'last' flag
                     v.txMBXLast   := txMBXMst.last;
                     v.ctlReq.be   := HBI_BE_W0_C;
                     -- honor the byte-enable (we look at the hi-byte only)
                     -- this is only relevant for the very last byte. If the
                     -- message is just one byte short of the full mailbox
                     -- capacity then writing one byte beyond the message length
                     -- would trigger the sync-manager and we don't want that
                     -- to happen since we first must write the correct length
                     -- to the message header.
                     -- It also doesn't matter if we write the high-byte to the
                     -- buffer memory -- but the 'be' we set here is later
                     -- used by the HBI write-cycle where it matters (A).
                     if ( txMBXMst.ben(1) = '0' ) then
                        v.ctlReq.be(1) := not HBI_BE_ACT_C;
                     end if;
                  elsif ( txMBXMst.last = '1' ) then
                     -- ERROR RETURN (overrun drained)
                     v.state := POLL_IRQ;
                     v.txMBXRdy := '0';
                  end if;
               end if;
            elsif ( r.program.don = '1' ) then
               -- this case is reached after a word has been written to the LAN9254
               v.ctlReq.be := HBI_BE_W0_C;
               if ( r.txMBXLast = '1' ) then
                  -- the last word has just been written; first we handle the special
                  -- case when the message length is identical with the mailbox capacity.
                  -- If this is true then the sync-manager has just been triggered. Since
                  -- we initially wrote the full-capacity to the header's length field the
                  -- everything is fine and we are left with no more work to do.
                  -- If, OTOH, the message length is just one byte short of the capacity
                  -- then the SM has not been triggered yet and we must proceed like with
                  -- any other message length (write correct length to the header and trigger
                  -- SM by writing the last byte).
                  -- We find out whether the last byte was part of the message or not by
                  -- inspecting the byte-enable in the program (note that r.ctlReq.be() has
                  -- been modified for word-aligned access, see lan9254HBIWrite()).
                  -- This is where the information set at point (A) above matters...
                  if ( ( r.txMBXWAddr = TXMBX_MAXWORDS_C - 1 ) and ( r.program.seq(0).reg.bena(1) = HBI_BE_ACT_C ) ) then
                        -- message spans full mailbox capacity => ALL DONE
                        if ( r.txMBXReplay = NONE or r.txMBXReplay = RESEND_BUF ) then
                           -- we have either the normal case or the case when an un-acknowledged
                           -- message has been re-sent after a repeated message.
                           v.state       := POLL_IRQ;
                           v.txMBXReplay := NONE;
                        else
                           -- a repeated message has been sent. We must toggle the repeat-ack bit
                           -- in the SM PDI register.
                           v.state := TXMBX_REP_ACK;
                        end if;
                  else
                     -- message was shorter than the full capacity. We must write the true
                     -- length to the header and eventually kick the sync-manager
                     if ( ( r.txMBXWAddr /= 0 ) and ( r.txMBXReplay = NONE ) ) then
                        -- we get here after the last message word was written to the lan9254
                        -- r.txMBXWAddr therefore contains the correct length of the message
                        -- (in words). We must write twice this value (plus info about the last byte)
                        -- to the message header (nothing to do during a replay since the correct value
                        -- is already in buffer memory). Schedule that for next cycle:
                        -- target address is 0
                        v.txMBXWAddr := 0;
                        -- compute the length
                        if ( r.program.seq(0).reg.bena(1) = HBI_BE_ACT_C ) then
                           v.txMBXLen   :=  to_unsigned(r.txMBXWAddr - (MBX_HDR_SIZE_C/2) + 1, v.txMBXLen'length - 1 ) & "0";
                        else
                           v.txMBXLen   :=  to_unsigned(r.txMBXWAddr - (MBX_HDR_SIZE_C/2)    , v.txMBXLen'length - 1 ) & "1";
                        end if;
                        -- enable writing txMBXLen to the header.
                        v.txMBXLEna     := '1';
                     else
                        -- header has been written or we are in a replay (in which case we skip directly here)
                        -- must kick the SM by writing to the last address
                        v.txMBXWAddr := TXMBX_MAXWORDS_C - 1;
                        if ( r.txMBXReplay = NONE ) then
                           -- if we are doing a 'normal' send then issue a write to the last
                           -- word of the ESCTxMbxBuf which will cause it to swap buffers and clear the 'rdy' flag.
                           -- If we are in replay mode then the ESCTxMbxBuf is already in 'not rdy' mode.
                           v.txMBXStrb  := '1';
                        end if;
                     end if;
                  end if;
               elsif ( r.txMBXWAddr = TXMBX_MAXWORDS_C - 1 ) then
                  -- message too long -> DRAIN
                  v.txMBXOverrun := '1';
                  v.txMBXRdy     := '1';
               else
                  -- 'normal' write (i.e., not last word) to the LAN9254 has finished; compute the next memory address
                  if ( r.txMBXWAddr = 0 ) then
                     -- remember length when doing a replay
                     v.txMBXLen := unsigned( txMBXBufRDat );
                  end if;
                  if ( ( r.txMBXReplay /= NONE ) and ( r.txMBXLen +  MBX_HDR_SIZE_C - 4 ) <= ( to_unsigned(r.txMBXWAddr, r.txMBXLen'length - 1) & "0" ) ) then
                     -- if we are in replay mode then use the length information from the header (stored in txMBXLen)
                     -- to raise the 'last' flag.
                     v.txMBXLast := '1';
                  end if;
                  v.txMBXWAddr   := r.txMBXWAddr + 1;
                  if ( ( r.txMBXWAddr >= MBX_HDR_SIZE_C/2 - 1 ) and ( r.txMBXReplay = NONE ) ) then
                     -- if we are not in replay mode and beyond the header then
                     -- we are ready to read the next word from the txMBXMst stream
                     -- (and we'll end up in the first branch of this big 'if' statement).
                     v.txMBXRdy := '1';
                  end if;
               end if;
            elsif ( r.txMBXLEna = '0' ) then -- must wait until msg length is written to the buffer
               -- schedule next write to the LAN9254. Note that we always 'write-through' the
               -- ESCTxMbxBuf buffer memory; i.e,. data are stored there (first branch of the 'HANDLE_TXMBX'
               -- statement).
               scheduleRegXact( v, (
                  0 => RWXACT(
                         unsigned(ESC_SM1_SMA_C) + (to_unsigned(r.txMBXWAddr, ESC_SM1_SMA_C'length - 1) & "0"),
                         v.ctlReq.be,
                         txMBXBufRDat
                       )
                  )
               );
            end if HANDLE_TXMBX;

         when TXMBX_REPLAY =>
            if ( '0' = r.program.don and ( r.txMBXReplay = SAVE_BUF ) ) then
               -- reset the TX mailbox; will resend the non-acked data again
               scheduleRegXact(
                  v,
                  (
                     0 => RWXACT( EC_REG_SM_PDI_F(1), r.rptAck(1) & "1" ),
                     1 => RWXACT( EC_REG_SM_PDI_F(1), r.rptAck(1) & r.smDis(1) )
                  )
               );
            else
               -- trigger sending the current buffer (ESCTxMBX) again
               v.state        := TXMBX_SEND;
               v.ctlReq.be    := HBI_BE_W0_C;
               v.txMBXWAddr   := 0;
               v.txMBXLast    := '0';
               v.txMBXOverrun := '0';
            end if;

         when TXMBX_REP_ACK =>
            -- after a repeat request has ben honored (last unacked message re-sent)
            -- we must toggle the repeat-ack flag in the SM PDI register. This
            -- state takes care of that.
            if ( '0' = r.program.don ) then
               scheduleRegXact(
                  v,
                  (
                     0 => RWXACT( EC_REG_SM_PDI_F(1), not r.rptAck(1) & r.smDis(1) )
                  )
               );
            else
               v.rptAck(1) := not r.rptAck(1);
               if ( r.txMBXReplay = NORMAL ) then
                  v.txMBXReplay := NONE;
               else
                  -- there was an unacked buffer (x) when we received the repeat request.
                  -- the ESCTxMbxBuf had been 'rewound' to the previous message (prior to
                  -- the unacked buffer) and that previous message has just been sent
                  -- with toggling the repeat-ack flag as the final step.
                  -- Once this resent message is ACKed we reach MBOX_SM1 state and
                  -- find that we can schedule the other (unacked) message (x).
                  v.txMBXReplay := RESEND_BUF;
               end if;
               v.state       := POLL_IRQ;
            end if;

      end case C_STATE;

      rxMBXLen      <= v.rxMBXLen;
      rxMBXTyp      <= v.rxMBXTyp;

      rin           <= v;

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

   P_EEP_WRITE : process ( r ) is
      variable v : EEPROMWriteWordReqType;
   begin
      v := EEPROM_WRITE_WORD_REQ_INIT_C;
      v.waddr     := unsigned( r.program.seq(1).val( v.waddr'range ) );
      v.wdata     := r.program.seq(0).val( v.wdata'range );
      v.valid     := r.eepWriteReqVld;
      eepWriteReq <= v;
   end process P_EEP_WRITE;

   U_MBX_BUF : entity work.ESCTxMbxBuf
      generic map (
         MBX_NUM_PAYLOAD_WORDS_G => TXMBX_PAYLOAD_MAXWORDS_C
      )
      port map (
         clk         => clk,
         rst         => r.txMBXRst,

         raddr       => r.txMBXWAddr,
         rdat        => txMBXBufRDat,

         tena        => r.txMBXTEna,
         htyp        => txMBXMst.usr(3 downto 0),
         lena        => r.txMBXLEna,
         mlen        => r.txMBXLen,

         wena        => txMBXBufWEna,
         wdat        => txMBXMst.data,
         wrdy        => txMBXBufWRdy,
         waddr       => r.txMBXWAddr,
         wbeh        => txMBXBufWBEh,

         ecMstAck    => r.txMBXMAck,
         ecMstRep    => r.txMBXMRep,
         haveBackup  => txMBXBufHaveBup
      );

   GEN_RX_MBX : if ( ENABLE_EOE_G or ENABLE_VOE_G or ENABLE_FOE_G ) generate
      signal sm0PldLen : unsigned(15 downto 0);
   begin

      sm0PldLen <= unsigned( r.sm0Len ) - MBX_HDR_SIZE_C;

   U_SM_RX  : entity work.ESCSmRx
      generic map (
         SM_SMA_G    => unsigned(ESC_SM0_SMA_C) + MBX_HDR_SIZE_C
      )
      port map (
         clk         => clk,
         rst         => rst,
         stop        => r.txMBXRst,

         trg         => rxMBXTrg,
         smLen       => sm0PldLen,
         len         => rxMBXLen,
         typ         => rxMBXTyp,

         rxPDOMst    => rxMBXPDO,
         rxPDORdy    => rxMBXRdy,

         req         => rxMBXReq,
         rep         => rxMBXRep,

         debug       => rxMBXDebug,
         stats       => stats(0 downto 0)
      );

      rxMbxSiz <= sm0PldLen;

      P_REFORMAT : process ( rxMBXPDO ) is
      begin
         rxMBXMst <= toStrmMst( rxMBXPDO );
      end process P_REFORMAT;

   end generate GEN_RX_MBX;

   GEN_RX_PDO : if ( not DISABLE_RXPDO_G ) generate

      signal rxPDOMstLoc : Lan9254PDOMstType;

   begin

   U_SM_RX   : entity work.ESCSmRx
      generic map (
         SM_SMA_G    => unsigned(ESC_SM2_SMA_C)
      )
      port map (
         clk         => clk,
         rst         => rst,
         stop        => r.rxPDORst,

         trg         => rxPDOTrg,
         smLen       => unsigned(r.config.sm2Len),
         len         => unsigned(r.config.sm2Len),
         typ         => x"0",

         rxPDOMst    => rxPDOMstLoc,
         rxPDORdy    => rxPDORdy,

         req         => rxPDOReq,
         rep         => rxPDORep,

         stats       => stats(1 downto 1)
      );

   P_SPLICE : process ( rxPDOMstLoc, r ) is
   begin
      rxPDOMst          <= rxPDOMstLoc;
      rxPDOMst.escState <= r.curState;
   end process P_SPLICE;

   end generate GEN_RX_PDO;

   GEN_TXPDO : if ( ( ESC_SM3_ACT_C  = '1' ) and ( to_integer(unsigned(ESC_SM3_LEN_C)) >  0  ) and not DISABLE_TXPDO_G ) generate
      U_TXPDO : entity work.ESCTxPDO
         generic map (
            TXPDO_BURST_MAX_G         => TXPDO_BURST_MAX_C,
            TXPDO_BURST_GAP_G         => 8,
            TXPDO_UPDATE_DECIMATION_G => TXPDO_UPDATE_DECIMATION_C
         )
         port map (
            clk         => clk,
            rst         => rst,
            stop        => r.txPDORst,

            smLen       => r.config.sm3Len,
            cfgVld      => r.config.valid,
            cfgAck      => open,

            txPDOMst    => txPDOMst,
            txPDORdy    => txPDORdy,

            req         => txPDOReq,
            rep         => txPDORep
         );
   end generate GEN_TXPDO;

   escState  <= r.curState;

   P_STALLED : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            stalledCount <= 0;
         else
            if ( (r.state /= TXMBX_SEND) ) then
               stalledCount <= 0;
            elsif ( stalledCount < STALL_C ) then
               if ( rHBIMux.hbiState = IDLE ) then
                  stalledCount <= stalledCount + 1;
               end if;
            end if;
         end if;
      end if;
   end process P_STALLED;

   P_IS_STALLED : process ( stalledCount ) is
   begin
      if ( stalledCount = STALL_C ) then
         stalled <= '1';
      else
         stalled <= '0';
      end if;
   end process P_IS_STALLED;

   debug(4  downto 0)   <= std_logic_vector( to_unsigned( ControllerStateType'pos( r.state ), 5) );
   debug(7 downto 5)    <= r.program.seq(2).val(10 downto 8);
   debug(12 downto 8)   <= std_logic_vector( to_unsigned( ControllerStateType'pos( rin.state ), 5) );
   debug(15 downto 13)  <= std_logic_vector(r.program.idx);
   debug(20 downto 16)  <= r.program.seq(0).val(8 downto 4);
   debug(21)            <= r.program.don;
   debug(22)            <= reqLoc.valid;
   debug(23)            <= rep.valid;

   G_GEN_ILA : if ( GEN_ILA_G ) generate

      signal     probe0          : std_logic_vector(63 downto 0) := (others => '0');
      signal     probe1          : std_logic_vector(63 downto 0) := (others => '0');
      signal     probe2          : std_logic_vector(63 downto 0) := (others => '0');
      signal     probe3          : std_logic_vector(63 downto 0) := (others => '0');

      signal     testDbg         : std_logic_vector( 7 downto 0);

      attribute KEEP of probe0 : signal is "TRUE";
      attribute KEEP of probe1 : signal is "TRUE";
      attribute KEEP of probe2 : signal is "TRUE";
      attribute KEEP of probe3 : signal is "TRUE";

   begin

      P_TEST_DBG : process ( r, rxMBXPDO ) is
      begin
         testDbg <= std_logic_vector( rxMBXPDO.wrdAddr(7 downto 0) );
         if ( r.state = TEST ) then
            testDbg(4 downto 0) <= std_logic_vector( to_unsigned( r.testFail, 5 ) );
            testDbg(5)          <= '1';
            testDbg(6)          <= r.wasRdy;
         end if;
      end process P_TEST_DBG;

      probe0(13 downto  0) <= std_logic_vector(reqLoc.addr);
      probe0(15 downto 14) <= rxMBXDebug(1 downto 0);
      -- !!!! vivado 2021.1 silently changed encoding, TEST -> 8; this improved when I set KEEP on the probes !!!!
      probe0(20 downto 16) <= std_logic_vector( to_unsigned( ControllerStateType'pos( r.state ), 5) );
      probe0(21          ) <= reqLoc.rdnwr;
      probe0(22          ) <= reqLoc.valid;
      probe0(23          ) <= rep.valid;
      probe0(31 downto 24) <= testDbg; -- rxMBXPDO.wrdAddr but if still in TEST state then testFail
      probe0(63 downto 32) <= reqLoc.data;

      probe1(31 downto  0) <= rep.rdata;
      probe1(63 downto 32) <= r.lastAL;

      probe2( 2 downto  0) <= std_logic_vector(r.program.idx);
      probe2( 3          ) <= r.program.don;
      probe2( 6 downto  4) <= std_logic_vector(r.program.num);
      probe2( 7          ) <= irq;
      probe2( 8          ) <= toSL(r.program.seq(0).rdnwr);
      probe2( 9          ) <= toSL(r.program.seq(1).rdnwr);
      probe2(10          ) <= toSL(r.program.seq(2).rdnwr);
      probe2(11          ) <= (stalled or rst); -- lack of probes; or them together
      probe2(15 downto 12) <= r.program.seq(0).reg.bena;
      probe2(19 downto 16) <= r.program.seq(1).reg.bena;
      probe2(23 downto 20) <= r.program.seq(2).reg.bena;
      probe2(27 downto 24) <= reqLoc.be;
      probe2(30 downto 28) <= std_logic_vector( to_unsigned( HBIMuxStateType'pos( rHBIMux.hbiState ) , 3 ) );
      probe2(31          ) <= rxMBXDebug(2);


      probe2(63 downto 32) <= r.program.seq(0).val;

      probe3(31 downto  0) <= r.program.seq(1).val;
      probe3(63 downto 32) <= r.program.seq(2).val;

      U_ILA_ESC : component Ila_256
         port map (
            clk          => clk,
            probe0       => probe0,
            probe1       => probe1,
            probe2       => probe2,
            probe3       => probe3,
            trig_out     => ilaTrigOb,
            trig_out_ack => ilaTackOb,
            trig_in      => ilaTrigIb,
            trig_in_ack  => ilaTackIb
         );

   end generate G_GEN_ILA;

   G_GEN_NO_ILA : if ( not GEN_ILA_G ) generate
      ilaTrigOb <= ilaTrigIb;
      ilaTackIb <= ilaTackOb;
   end generate G_GEN_NO_ILA;

   testFailed <= std_logic_vector(to_unsigned(r.testFail, testFailed'length));

   req        <= reqLoc;
   configAck  <= r.configAck;

   configRst  <= r.configRst;
   eepEmul    <= r.eepEmulActive;

end architecture rtl;
