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

use work.Lan9254Pkg.all;

-- HBI in single-cycle, 16-bit wide multiplexed mode
-- The entity is declared here; architectures are implemented
-- in separate files:
--   Lan9254HbiImpl.vhd -> implementation in FPGA fabric (RTL)
--   Lan9254HbiSoft.vhd -> wrapper for simulation mode when
--                         running simulation on a ZYNQ.
--                         This enables the simulation/CPU to interact
--                         with the real LAN9254 hardware via
--                         a AXI-bus-to-HBI-bridge.

entity Lan9254HBI is

   generic (
      -- could use these generics to implement different modes
      DATA_WIDTH_G   : positive range 16   to 16   := 16;
      ADDR_WIDTH_G   : positive range 16   to 16   := 16;
      MUXED_MODE_G   : boolean  range true to true := true;
      GEN_ILA_G      : boolean                     := true;
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
