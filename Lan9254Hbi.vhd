library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.Lan9254Pkg.all;

-- HBI in single-cycle, 16-bit wide multiplexed mode
entity Lan9254HBI is

   generic (
      -- could use these generics to implement different modes
      DATA_WIDTH_G   : positive range 16   to 16   := 16;
      ADDR_WIDTH_G   : positive range 16   to 16   := 16;
      MUXED_MODE_G   : boolean  range true to true := true;
      CLOCK_FREQ_G   : real
   );
   port (
      clk            : in  std_logic;
      cen            : in  std_logic := '1';
      rst            : in  std_logic := '0';

      -- upstream interface
      req            : in  Lan9254ReqType;
      rep            : out Lan9254RepType    := LAN9254REP_INIT_C;

      -- HBI interface to LAN9254 chip
      hbiOut         : out Lan9254HBIOutType := LAN9254HBIOUT_INIT_C;
      hbiInp         : in  Lan9254HBIInpType := LAN9254HBIINP_INIT_C
   );

end entity Lan9254HBI;
