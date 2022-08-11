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
      err     : std_logic;
      doneAck : std_logic;
      fileIdx : natural range 0 to 15;
   end record FoEMstType;

   constant FOE_MST_INIT_C : FoEMstType := (
      strmMst => LAN9254STRM_MST_INIT_C,
      fifoRst => '0',
      err     => '0',
      doneAck => '0',
      fileIdx => 0
   );

   type FoESubType is record
      strmRdy : std_logic;
      abort   : std_logic;
      done    : std_logic;
      file0WP : std_logic;
   end record FoESubType;

   constant FOE_SUB_ASSERT_C : FoESubType := (
      strmRdy => '1',
      abort   => '0',
      done    => '1',
      file0WP => '1'
   );

   constant FOE_SUB_INIT_C : FoESubType := (
      strmRdy => '0',
      abort   => '0',
      done    => '0',
      file0WP => '0'
   );

   type FoEFileNameArray is array (natural range <>) of std_logic_vector(7 downto 0);

   constant FOE_FILE_NAME_ARRAY_EMPTY_C : FoeFileNameArray(1 to 0) := (others => (others => '0'));

end package ESCFoEPkg;
