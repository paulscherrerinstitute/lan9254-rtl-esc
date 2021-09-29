library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

-- mailbox definitions

package ESCMbxPkg is

   constant MBX_TYP_ERR_C                         : std_logic_vector( 3 downto 0)  := x"0";
   constant MBX_TYP_EOE_C                         : std_logic_vector( 3 downto 0)  := x"2";
   constant MBX_TYP_COE_C                         : std_logic_vector( 3 downto 0)  := x"3";
   constant MBX_TYP_VOE_C                         : std_logic_vector( 3 downto 0)  := x"F";

   constant EC_VENDOR_ID_PSI_C                    : std_logic_vector(31 downto 0)  := x"0050_5349";

   subtype  MBX_TYP_RNG_T is natural range 11 downto  8;
   subtype  MBX_CNT_RNG_T is natural range 14 downto 12;

   constant MBX_HDR_SIZE_C                        : natural                        := 6;

   constant MBX_ERR_CMD_C                         : std_logic_vector(15 downto  0) := x"0001";
   constant MBX_ERR_CODE_SYNTAX_C                 : std_logic_vector(15 downto  0) := x"0001";
   constant MBX_ERR_CODE_UNSUPPORTEDPROTOCOL_C    : std_logic_vector(15 downto  0) := x"0002";
   constant MBX_ERR_CODE_INVALIDCHANNEL_C         : std_logic_vector(15 downto  0) := x"0003";
   constant MBX_ERR_CODE_SERVICENOTSUPPORTED_C    : std_logic_vector(15 downto  0) := x"0004";
   constant MBX_ERR_CODE_INVALIDHEADER_C          : std_logic_vector(15 downto  0) := x"0005";
   constant MBX_ERR_CODE_SIZETOOSHORT_C           : std_logic_vector(15 downto  0) := x"0006";
   constant MBX_ERR_CODE_NOMOREMEMORY_C           : std_logic_vector(15 downto  0) := x"0007";
   constant MBX_ERR_CODE_INVALIDSIZE_C            : std_logic_vector(15 downto  0) := x"0008";
   constant MBX_ERR_CODE_SERVICEINWORK_C          : std_logic_vector(15 downto  0) := x"0009";

   constant EOE_TYPE_FRAG_C                       : std_logic_vector(3 downto 0) := x"0";
   constant EOE_TYPE_INIT_RESP_TS_C               : std_logic_vector(3 downto 0) := x"1";
   constant EOE_TYPE_INIT_REQ_C                   : std_logic_vector(3 downto 0) := x"2";
   constant EOE_TYPE_INIT_RSP_C                   : std_logic_vector(3 downto 0) := x"3";
   constant EOE_TYPE_SET_ADDR_FILT_REQ_C          : std_logic_vector(3 downto 0) := x"4";
   constant EOE_TYPE_SET_ADDR_FILT_RSP_C          : std_logic_vector(3 downto 0) := x"5";
   constant EOE_TYPE_GET_IP_PARAM_REQ_C           : std_logic_vector(3 downto 0) := x"6";
   constant EOE_TYPE_GET_IP_PARAM_RSP_C           : std_logic_vector(3 downto 0) := x"7";
   constant EOE_TYPE_GET_ADDR_FILT_REQ_C          : std_logic_vector(3 downto 0) := x"8";
   constant EOE_TYPE_GET_ADDR_FILT_RSP_C          : std_logic_vector(3 downto 0) := x"9";


   type MbxErrorType is record
      code : std_logic_vector(15 downto 0);
      vld  : std_logic;
   end record MbxErrorType;

   constant MBX_ERROR_INIT_C : MbxErrorType := (
      code => (others => '0'),
      vld  => '0'
   );

   type MbxErrorArray is array (natural range <>) of MbxErrorType;

end package ESCMbxPkg;

package body ESCMbxPkg is
end package body ESCMbxPkg;
