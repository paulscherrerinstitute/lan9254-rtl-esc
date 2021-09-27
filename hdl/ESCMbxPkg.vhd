library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

-- mailbox definitions

package ESCMbxPkg is

   constant MBX_TYP_ERR_C                         : std_logic_vector( 3 downto 0)  := x"0";
   constant MBX_TYP_EOE_C                         : std_logic_vector( 3 downto 0)  := x"2";
   constant MBX_TYP_COE_C                         : std_logic_vector( 3 downto 0)  := x"3";

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

end package ESCMbxPkg;

package body ESCMbxPkg is
end package body ESCMbxPkg;
