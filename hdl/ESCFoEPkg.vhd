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

package ESCFoEPkg is

   -- for a description of the signals
   -- see ESCFoE.vhd

   type FoEMstType is record
      strmMst : Lan9254StrmMstType;
      fifoRst : std_logic;
      abort   : std_logic;
      doneAck : std_logic;
      fileIdx : natural range 0 to 15;
   end record FoEMstType;

   constant FOE_MST_INIT_C : FoEMstType := (
      strmMst => LAN9254STRM_MST_INIT_C,
      fifoRst => '0',
      abort   => '0',
      doneAck => '0',
      fileIdx => 0
   );

   subtype  FoEErrorType   is std_logic_vector(15 downto 0);

   -- use FOE mailbox error codes !
   constant FOE_NO_ERROR_C :  FoEErrorType := (others => '0');
   
   type FoESubType is record
      strmRdy : std_logic;
      err     : FoEErrorType;
      done    : std_logic;
      fileWP  : std_logic;
   end record FoESubType;

   constant FOE_SUB_ASSERT_C : FoESubType := (
      strmRdy => '1',
      err     => FOE_NO_ERROR_C,
      done    => '1',
      fileWP  => '1'
   );

   constant FOE_SUB_INIT_C : FoESubType := (
      strmRdy => '0',
      err     => FOE_NO_ERROR_C,
      done    => '0',
      fileWP  => '0'
   );

   type FoEFileType is record
      id      : std_logic_vector(7 downto 0);
      wp      : boolean;
   end record FoEFileType;

   constant FOE_FILE_ID_WILDCARD_C    : std_logic_vector(7 downto 0) := (others => '0');

   constant FOE_FILE_INIT_C : FoEFileType := (
      id      => FOE_FILE_ID_WILDCARD_C,
      wp      => false
   );

   type FoEFileArray is array (natural range <>) of FoEFileType;

   constant FOE_FILE_ARRAY_EMPTY_C : FoeFileArray(1 to 0)     := (others => FOE_FILE_INIT_C );


end package ESCFoEPkg;
