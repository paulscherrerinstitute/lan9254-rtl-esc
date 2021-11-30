library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.ESCBasicTypesPkg.all;
use work.Lan9254Pkg.all;

-- Types, declarations, helpers for ESC support

package Lan9254ESCPkg is

   -- we list BOOT last so the valid increments in state (except for boot)
   -- are always '1'
   type ESCStateType is (
      INIT,
      PREOP,
      SAFEOP,
      OP,
      BOOT,
      UNKNOWN
   );

   type EcRegType is record
      addr     : std_logic_vector(15 downto 0);
      bena     : std_logic_vector( 3 downto 0);
   end record EcRegType;

   constant EC_REG_AL_CTRL_C : EcRegType := (
      addr     => x"0120",
      bena     => HBI_BE_W0_C
   );

   constant EC_REG_AL_STAT_C : EcRegType := (
      addr     => x"0130",
      bena     => HBI_BE_W0_C
   );

   constant EC_REG_AL_ERRO_C : EcRegType := (
      addr     => x"0134",
      bena     => HBI_BE_W0_C
   );

   constant EC_REG_AL_EMSK_C : EcRegType := (
      addr     => x"0204",
      bena     => HBI_BE_DW_C
   );

   constant EC_REG_AL_EREQ_C : EcRegType := (
      addr     => x"0220",
      bena     => HBI_BE_DW_C
   );

   constant EC_REG_WD_PDST_C : EcRegType := (
      addr     => x"0440",
      bena     => HBI_BE_W0_C
   );

   constant EC_AL_EREQ_CTL_IDX_C         : natural :=  0;
   constant EC_AL_EREQ_SMA_IDX_C         : natural :=  4;
   constant EC_AL_EREQ_EEP_IDX_C         : natural :=  5;
   constant EC_AL_EREQ_WDG_IDX_C         : natural :=  6;
   constant EC_AL_EREQ_SM0_IDX_C         : natural :=  8;
   constant EC_AL_EREQ_SM1_IDX_C         : natural :=  9;
   constant EC_AL_EREQ_SM2_IDX_C         : natural := 10;
   constant EC_AL_EREQ_SM3_IDX_C         : natural := 11;

   constant EC_REG_EEP_CSR_C : EcRegType := (
      addr     => x"0502",
      bena     => HBI_BE_W0_C
   );

   subtype EEPROMCommandType is std_logic_vector(2 downto 0);

   constant EEPROM_NOOP_C  : std_logic_vector(2 downto 0) := "000";
   constant EEPROM_READ_C  : std_logic_vector(2 downto 0) := "001";
   constant EEPROM_WRITE_C : std_logic_vector(2 downto 0) := "010";
   constant EEPROM_RELD_C  : std_logic_vector(2 downto 0) := "100";

   function EE_CMD_GET_F(constant v : in std_logic_vector)
   return EEPROMCommandType;

   function EC_BYTE_REG_F(
      constant addr : ESCVal16Type;
      constant off  : ESCVal16Type := (others => '0');
      constant adj  : integer      := 0
   ) return EcRegType;

   function EC_WORD_REG_F(
      constant addr : ESCVal16Type;
      constant off  : ESCVal16Type := (others => '0');
      constant adj  : integer      := 0
   ) return EcRegType;

   constant EC_REG_EEP_ADR_C : EcRegType := (
      addr     => x"0504",
      bena     => HBI_BE_DW_C
   );

   constant EC_REG_EEP_DLO_C : EcRegType := (
      addr     => x"0508",
      bena     => HBI_BE_DW_C
   );

   constant EC_REG_EEP_DHI_C : EcRegType := (
      addr     => x"050C",
      bena     => HBI_BE_DW_C
   );

   constant EC_REG_IRQ_CFG_C : EcRegType := (
      addr     => x"3054",
      bena     => HBI_BE_DW_C
   );

   constant EC_IRQ_CFG_TYP_IDX_C : natural   := 0;   -- '1' : push-pull, '0' open-drain
   constant EC_IRQ_CFG_POL_IDX_C : natural   := 4;
   constant EC_IRQ_CFG_ENA_IDX_C : natural   := 8;
   constant EC_IRQ_ACT_C         : std_logic := '0'; -- active low if 'POL' bit is '0'


   constant EC_REG_IRQ_STS_C : EcRegType := (
      addr     => x"3058",
      bena     => HBI_BE_DW_C
   );

   constant EC_REG_IRQ_ENA_C : EcRegType := (
      addr     => x"305C",
      bena     => HBI_BE_DW_C
   );

   constant EC_IRQ_ENA_ECAT_IDX_C : natural := 0;

   function EC_REG_SM_PSA_F(constant sm : natural range 0 to 7)
   return EcRegType;

   function EC_REG_SM_LEN_F(constant sm : natural range 0 to 7)
   return EcRegType;

   function EC_REG_SM_CTL_F(constant sm : natural range 0 to 7)
   return EcRegType;

   function EC_REG_SM_STA_F(constant sm : natural range 0 to 7)
   return EcRegType;

   function EC_REG_SM_ACT_F(constant sm : natural range 0 to 7)
   return EcRegType;

   constant EC_SM_ACT_DIS_IDX_C          : natural :=  0;
   constant EC_SM_ACT_RPT_IDX_C          : natural :=  1;

   function EC_REG_SM_PDI_F(constant sm : natural range 0 to 7)
   return EcRegType;

   constant EC_SM_ACT_IDX_C                             : natural      := 0;

   constant EC_ALER_OK_C                                : ESCVal16Type := x"0000";
   constant EC_ALER_INVALIDSTATECHANGE_C                : ESCVal16Type := x"0011";
   constant EC_ALER_UNKNOWNSTATE_C                      : ESCVal16Type := x"0012";
   constant EC_ALER_INVALIDMBXCONFIG_C                  : ESCVal16Type := x"0016";
   constant EC_ALER_WATCHDOG_C                          : ESCVal16Type := x"001B";
   constant EC_ALER_INVALIDOUTPUTSM_C                   : ESCVal16Type := x"001D";
   constant EC_ALER_INVALIDINPUTSM_C                    : ESCVal16Type := x"001E";

   constant ESC_SMC_MSK_C                               : ESCVal08Type := x"3F";

   constant ESC_SM0_SMA_C                               : ESCVal16Type := x"1000";
   constant ESC_SM0_SMC_C                               : ESCVal08Type :=   x"26";
   constant ESC_SM0_LEN_C                               : ESCVal16Type := x"0030";
   constant ESC_SM0_ACT_C                               : std_logic    := '1';

   constant ESC_SM1_SMA_C                               : ESCVal16Type := x"1080";
   constant ESC_SM1_SMC_C                               : ESCVal08Type :=   x"22";
   constant ESC_SM1_LEN_C                               : ESCVal16Type := x"0030";
   constant ESC_SM1_ACT_C                               : std_logic    := '1';

   -- PDO address **must** be word-aligned for now
   constant ESC_SM2_SMA_C                               : ESCVal16Type := x"1100";
   constant ESC_SM2_SMC_C                               : ESCVal08Type :=   x"24";
   constant ESC_SM2_LEN_C                               : ESCVal16Type := x"0003";
   -- if this is increased the ESC_SM3_SMA_C must be modified accordingly
   constant ESC_SM2_MAX_C                               : ESCVal16Type := x"0080";
   -- HACK_LEN is used for testing (reduce and make sure PDO is not updated)
   constant ESC_SM2_HACK_LEN_C                          : ESCVal16Type := x"0003";
   constant ESC_SM2_ACT_C                               : std_logic    := '1';

   -- PDO address **must** be word-aligned for now
   constant ESC_SM3_SMA_C                               : ESCVal16Type := x"1180";
   constant ESC_SM3_SMC_C                               : ESCVal08Type :=   x"20";
   constant ESC_SM3_LEN_C                               : ESCVal16Type := x"0004";
   constant ESC_SM3_MAX_C                               : ESCVal16Type := x"0200";
   -- HACK_LEN is used for testing (reduce and make sure PDO is not posted)
   constant ESC_SM3_HACK_LEN_C                          : ESCVal16Type := x"0004";
   constant ESC_SM3_ACT_C                               : std_logic    := '1';

   -- make PDO lengths run-time configurable
   type ESCConfigReqType is record
      sm2Len   : ESCVal16Type;
      sm3Len   : ESCVal16Type;
      valid    : std_logic;
   end record ESCConfigReqType;

   type ESCConfigAckType is record
      ack      : std_logic;
   end record ESCConfigAckType;

   constant ESC_CONFIG_REQ_INIT_C : ESCConfigReqType := (
      sm2Len   => ESC_SM2_LEN_C,
      sm3Len   => ESC_SM3_LEN_C,
      valid    => '1'
   );

   constant ESC_CONFIG_REQ_NULL_C : ESCConfigReqType := (
      sm2Len   => (others => '0'),
      sm3Len   => (others => '0'),
      valid    => '0'
   );


   constant ESC_CONFIG_ACK_INIT_C : ESCConfigAckType := (
      ack      => '0'
   );

   constant ESC_CONFIG_ACK_ASSERT_C : ESCConfigAckType := (
      ack      => '1'
   );

   -- convert to byte-array (for serialization); this does NOT contain
   -- the 'valid' flag.
   -- Items are serialized in the order they appear in the record and
   -- as little-endian.
   function toSlv08Array(constant x: ESCConfigReqType) return Slv08Array;

   function toESCConfigReqType(constant x: Slv08Array) return ESCConfigReqType;

   -- define a 'register' pointing to the last byte of the RX and TX PDOS.
   -- these can be read or written, respectively to release the SM buffers.
   constant EC_REG_RXMBX_L_C : EcRegType := EC_BYTE_REG_F( ESC_SM0_SMA_C, ESC_SM0_LEN_C, -1 );
   constant EC_REG_TXMBX_L_C : EcRegType := EC_BYTE_REG_F( ESC_SM1_SMA_C, ESC_SM1_LEN_C, -1 );

   function toSlv(constant arg : ESCStateType) return std_logic_vector;

   subtype  StatCounterType is unsigned(12 downto 0);
   constant STAT_COUNTER_INIT_C : StatCounterType := (others => '0');

   type    StatCounterArray is array (natural range <>) of StatCounterType;

end package LAN9254ESCPkg;

package body LAN9254ESCPkg is

   function SM_ADDR_F(constant sm : natural range 0 to 7; constant off : natural range 0 to 15)
   return std_logic_vector is
      constant a : unsigned(15 downto 0) := x"0800";
   begin
      return std_logic_vector(a + 8*sm + off);
   end function SM_ADDR_F;

   function EC_REG_SM_PSA_F(constant sm : natural range 0 to 7)
   return EcRegType is
      variable v : EcRegType;
   begin
      v.addr := SM_ADDR_F(sm, 0);
      v.bena := HBI_BE_W0_C;
      return v;
   end function EC_REG_SM_PSA_F;

   function EC_REG_SM_LEN_F(constant sm : natural range 0 to 7)
   return EcRegType is
      variable v : EcRegType;
   begin
      v.addr := SM_ADDR_F(sm, 2);
      v.bena := HBI_BE_W0_C;
      return v;
   end function EC_REG_SM_LEN_F;

   function EC_REG_SM_CTL_F(constant sm : natural range 0 to 7)
   return EcRegType is
   begin
      return EC_BYTE_REG_F( SM_ADDR_F( sm, 4 ), off => x"0000" );
   end function EC_REG_SM_CTL_F;

   function EC_REG_SM_STA_F(constant sm : natural range 0 to 7)
   return EcRegType is
      variable v : EcRegType;
   begin
      return EC_BYTE_REG_F( SM_ADDR_F( sm, 4 ), off => x"0001" );
   end function EC_REG_SM_STA_F;

   function EC_REG_SM_ACT_F(constant sm : natural range 0 to 7)
   return EcRegType is
   begin
      return EC_BYTE_REG_F( SM_ADDR_F( sm, 4 ), off => x"0002" );
   end function EC_REG_SM_ACT_F;

   function EC_REG_SM_PDI_F(constant sm : natural range 0 to 7)
   return EcRegType is
   begin
      return EC_BYTE_REG_F( SM_ADDR_F( sm, 4 ), off => x"0003" );
   end function EC_REG_SM_PDI_F;

   function EE_CMD_GET_F(constant v : in std_logic_vector)
   return EEPROMCommandType is
   begin
      return v(10 downto 8);
   end function EE_CMD_GET_F;

   function EC_REG_F(
      constant addr : ESCVal16Type;
      constant off  : ESCVal16Type := (others => '0');
      constant adj  : integer      := 0;
      constant be   : std_logic_vector(3 downto 0)
   ) return EcRegType is
      variable v : EcRegType;
      variable u : unsigned(addr'high downto addr'low);
      variable l : natural;
   begin
      u           := unsigned(addr) + unsigned(off) + unsigned(to_signed(adj, u'length));
      v.addr      := std_logic_vector( u );
      v.bena      := be;
      return v; 
   end function EC_REG_F;

   function EC_BYTE_REG_F(
      constant addr : ESCVal16Type;
      constant off  : ESCVal16Type := (others => '0');
      constant adj  : integer      := 0
   ) return EcRegType is
   begin
      return EC_REG_F(addr, off, adj, HBI_BE_B0_C);
   end function EC_BYTE_REG_F;

   function EC_WORD_REG_F(
      constant addr : ESCVal16Type;
      constant off  : ESCVal16Type := (others => '0');
      constant adj  : integer      := 0
   ) return EcRegType is
   begin
      return EC_REG_F(addr, off, adj, HBI_BE_W0_C);
   end function EC_WORD_REG_F;
  
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

   function toSlv08Array(constant x: ESCConfigReqType) return Slv08Array is
      constant c : Slv08Array := (
         0 => std_logic_vector( x.sm2Len( 7 downto 0) ),
         1 => std_logic_vector( x.sm2Len(15 downto 8) ),
         2 => std_logic_vector( x.sm3Len( 7 downto 0) ),
         3 => std_logic_vector( x.sm3Len(15 downto 8) )
      );
   begin
      return c;
   end function toSlv08Array;

   function toESCConfigReqType(constant x: Slv08Array) return ESCConfigReqType is
      constant c : ESCConfigReqType := (
         sm2Len  => ESCVal16Type'( x(1 + x'low) & x(0 + x'low) ),
         sm3Len  => ESCVal16Type'( x(3 + x'low) & x(2 + x'low) ),
         valid   => '0'
      );
   begin
      return c; 
   end function toESCConfigReqType;

end package body LAN9254ESCPkg;
