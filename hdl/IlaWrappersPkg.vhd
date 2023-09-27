------------------------------------------------------------------------------
--      Copyright (c) 2022-2023 by Paul Scherrer Institute, Switzerland
--      All rights reserved.
--  Authors: Till Straumann
--  License: PSI HDL Library License, Version 2.0 (see License.txt)
------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

-- Stub/declaration for (pre-configured) Xilinx-ILA IP.

package IlaWrappersPkg is

   component Ila_256 is
      port (
         clk          : in std_logic;
         probe0       : in std_logic_vector(63 downto 0);
         probe1       : in std_logic_vector(63 downto 0);
         probe2       : in std_logic_vector(63 downto 0);
         probe3       : in std_logic_vector(63 downto 0);

         trig_out     : out std_logic;
         trig_out_ack : in  std_logic := '1';
         trig_in      : in  std_logic := '1';
         trig_in_ack  : out std_logic
      );
   end component Ila_256;

end package IlaWrappersPkg;
