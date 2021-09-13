library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

package Lan9254ESCPkg is

   type EcRegType is record
      addr     : std_logic_vector(15 downto 0);
      bena     : std_logic_vector( 3 downto 0);
   end record EcRegType;

   constant EC_REG_AL_CTRL_C : EcRegType := (
      addr     => x"0120",
      bena     => "0011"
   );

   constant EC_REG_AL_STAT_C : EcRegType := (
      addr     => x"0130",
      bena     => "0011"
   );

   constant EC_REG_AL_ERRO_C : EcRegType := (
      addr     => x"0134",
      bena     => "0011"
   );

   constant EC_REG_AL_EREQ_C : EcRegType := (
      addr     => x"0220",
      bena     => "1111"
   );

   constant EC_AL_EREQ_CTL_IDX_C         : natural := 0;
   constant EC_AL_EREQ_EEP_IDX_C         : natural := 5;

   constant EC_REG_EEP_CSR_C : EcRegType := (
      addr     => x"0500",
      bena     => "1100"
   );

   subtype EEPROMCommandType is std_logic_vector(2 downto 0);

   constant EEPROM_NOOP_C  : std_logic_vector(2 downto 0) := "000";
   constant EEPROM_READ_C  : std_logic_vector(2 downto 0) := "001";
   constant EEPROM_WRITE_C : std_logic_vector(2 downto 0) := "010";
   constant EEPROM_RELD_C  : std_logic_vector(2 downto 0) := "100";

   function EE_CMD_GET_F(constant v : in std_logic_vector)
   return EEPROMCommandType;

   constant EC_REG_EEP_ADR_C : EcRegType := (
      addr     => x"0504",
      bena     => "1111"
   );

   constant EC_REG_EEP_DLO_C : EcRegType := (
      addr     => x"0508",
      bena     => "1111"
   );

   constant EC_REG_EEP_DHI_C : EcRegType := (
      addr     => x"050C",
      bena     => "1111"
   );

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

   function EC_REG_SM_PDI_F(constant sm : natural range 0 to 7)
   return EcRegType;

   constant EC_SM_ACT_IDX_C                             : natural      := 0;

   subtype  ESCVal16Type is std_logic_vector(15 downto 0);

   constant EC_ALER_OK_C                                : ESCVal16Type := x"0000";
   constant EC_ALER_INVALIDSTATECHANGE_C                : ESCVal16Type := x"0011";
   constant EC_ALER_UNKNOWNSTATE_C                      : ESCVal16Type := x"0012";
   constant EC_ALER_INVALIDOUTPUTSM_C                   : ESCVal16Type := x"001D";
   constant EC_ALER_INVALIDINPUTSM_C                    : ESCVal16Type := x"001E";

   constant ESC_SM2_SMA_C                               : ESCVal16Type := x"1100";
   constant ESC_SM2_SMC_C                               : ESCVal16Type := x"0024";
   constant ESC_SM2_LEN_C                               : ESCVal16Type := x"0002";
   constant ESC_SM2_ACT_C                               : std_logic    := '1';

   constant ESC_SM3_SMA_C                               : ESCVal16Type := x"1180";
   constant ESC_SM3_SMC_C                               : ESCVal16Type := x"0020";
   constant ESC_SM3_LEN_C                               : ESCVal16Type := x"0001";
   constant ESC_SM3_ACT_C                               : std_logic    := '1';

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
      v.bena :=  "0011";
      return v;
   end function EC_REG_SM_PSA_F;

   function EC_REG_SM_LEN_F(constant sm : natural range 0 to 7)
   return EcRegType is
      variable v : EcRegType;
   begin
      v.addr := SM_ADDR_F(sm, 0);
      v.bena :=  "1100";
      return v;
   end function EC_REG_SM_LEN_F;

   function EC_REG_SM_CTL_F(constant sm : natural range 0 to 7)
   return EcRegType is
      variable v : EcRegType;
   begin
      v.addr := SM_ADDR_F(sm, 4);
      v.bena :=  "0001";
      return v;
   end function EC_REG_SM_CTL_F;

   function EC_REG_SM_STA_F(constant sm : natural range 0 to 7)
   return EcRegType is
      variable v : EcRegType;
   begin
      v.addr := SM_ADDR_F(sm, 4);
      v.bena :=  "0010";
      return v;
   end function EC_REG_SM_STA_F;

   function EC_REG_SM_ACT_F(constant sm : natural range 0 to 7)
   return EcRegType is
      variable v : EcRegType;
   begin
      v.addr := SM_ADDR_F(sm, 4);
      v.bena :=  "0100";
      return v;
   end function EC_REG_SM_ACT_F;

   function EC_REG_SM_PDI_F(constant sm : natural range 0 to 7)
   return EcRegType is
      variable v : EcRegType;
   begin
      v.addr := SM_ADDR_F(sm, 4);
      v.bena :=  "1000";
      return v;
   end function EC_REG_SM_PDI_F;

   function EE_CMD_GET_F(constant v : in std_logic_vector)
   return EEPROMCommandType is
   begin
      return v(10 downto 8);
   end function EE_CMD_GET_F;


end package body LAN9254ESCPkg;
