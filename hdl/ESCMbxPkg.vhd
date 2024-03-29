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

-- mailbox definitions

package ESCMbxPkg is

   subtype  ESCMbxType                            is std_logic_vector( 3 downto 0 );

   type     ESCMbxArray is array( natural range <>) of ESCMbxType;

   constant MBX_TYP_ERR_C                         : ESCMbxType := x"0";
   constant MBX_TYP_EOE_C                         : ESCMbxType := x"2";
   constant MBX_TYP_COE_C                         : ESCMbxType := x"3";
   constant MBX_TYP_FOE_C                         : ESCMbxType := x"4";
   constant MBX_TYP_VOE_C                         : ESCMbxType := x"F";

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

   constant EOE_TYPE_FRAG_C                       : std_logic_vector(3 downto 0)   := x"0";
   constant EOE_TYPE_INIT_RESP_TS_C               : std_logic_vector(3 downto 0)   := x"1";
   constant EOE_TYPE_SET_IP_PARM_REQ_C            : std_logic_vector(3 downto 0)   := x"2";
   constant EOE_TYPE_SET_IP_PARM_RSP_C            : std_logic_vector(3 downto 0)   := x"3";
   constant EOE_TYPE_SET_ADDR_FILT_REQ_C          : std_logic_vector(3 downto 0)   := x"4";
   constant EOE_TYPE_SET_ADDR_FILT_RSP_C          : std_logic_vector(3 downto 0)   := x"5";
   constant EOE_TYPE_GET_IP_PARAM_REQ_C           : std_logic_vector(3 downto 0)   := x"6";
   constant EOE_TYPE_GET_IP_PARAM_RSP_C           : std_logic_vector(3 downto 0)   := x"7";
   constant EOE_TYPE_GET_ADDR_FILT_REQ_C          : std_logic_vector(3 downto 0)   := x"8";
   constant EOE_TYPE_GET_ADDR_FILT_RSP_C          : std_logic_vector(3 downto 0)   := x"9";

   constant EOE_ERR_CODE_SUCCESS_C                : std_logic_vector(15 downto  0) := x"0000";
   constant EOE_ERR_CODE_UNSPEC_ERROR_C           : std_logic_vector(15 downto  0) := x"0001";
   constant EOE_ERR_CODE_UNSUP_FRAME_TYPE_C       : std_logic_vector(15 downto  0) := x"0002";
   constant EOE_ERR_CODE_UNSUP_IP_C               : std_logic_vector(15 downto  0) := x"0201";
   constant EOE_ERR_CODE_UNSUP_DHCP_C             : std_logic_vector(15 downto  0) := x"0202";
   constant EOE_ERR_CODE_UNSUP_FILTER_C           : std_logic_vector(15 downto  0) := x"0401";

   constant EOE_HDR_SIZE_C                        : natural                        := 4;
   constant EOE_MAX_FRAME_SIZE_C                  : natural                        := 1472;

   constant FOE_OP_RRQ_C                          : std_logic_vector(7 downto 0)   := x"01";
   constant FOE_OP_WRQ_C                          : std_logic_vector(7 downto 0)   := x"02";
   constant FOE_OP_DATA_C                         : std_logic_vector(7 downto 0)   := x"03";
   constant FOE_OP_ACK_C                          : std_logic_vector(7 downto 0)   := x"04";
   constant FOE_OP_ERR_C                          : std_logic_vector(7 downto 0)   := x"05";
   constant FOE_OP_BUSY_C                         : std_logic_vector(7 downto 0)   := x"06";

   constant FOE_ERR_CODE_VENDOR_C                 : std_logic_vector(15 downto 0)  := x"8000";
   constant FOE_ERR_CODE_NOTFOUND_C               : std_logic_vector(15 downto 0)  := x"8001";
   constant FOE_ERR_CODE_ACCESS_C                 : std_logic_vector(15 downto 0)  := x"8002";
   constant FOE_ERR_CODE_DISKFULL_C               : std_logic_vector(15 downto 0)  := x"8003";
   constant FOE_ERR_CODE_ILLEGAL_C                : std_logic_vector(15 downto 0)  := x"8004";
   constant FOE_ERR_CODE_PACKETNO_C               : std_logic_vector(15 downto 0)  := x"8005";
   constant FOE_ERR_CODE_EXISTS_C                 : std_logic_vector(15 downto 0)  := x"8006";
   constant FOE_ERR_CODE_NOUSER_C                 : std_logic_vector(15 downto 0)  := x"8007";
   constant FOE_ERR_CODE_BOOTSTRAPONLY_C          : std_logic_vector(15 downto 0)  := x"8008";
   constant FOE_ERR_CODE_NOTINBOOTSTRAP_C         : std_logic_vector(15 downto 0)  := x"8009";
   constant FOE_ERR_CODE_NORIGHTS_C               : std_logic_vector(15 downto 0)  := x"800A";
   constant FOE_ERR_CODE_PROGRAM_ERROR_C          : std_logic_vector(15 downto 0)  := x"800B";
   constant FOE_ERR_CODE_CHECKSUM_ERROR_C         : std_logic_vector(15 downto 0)  := x"800C";

   constant FOE_HDR_SIZE_C                        : natural                        := 6;

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
