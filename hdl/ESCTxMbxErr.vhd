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
use work.ESCMbxPkg.all;

-- Convert error status from ESC controller into a mailbox message

entity ESCTxMbxErr is
   generic (
      NUM_ERROR_SRCS_G : natural := 1
   );
   port (
      clk     : in  std_logic;
      rst     : in  std_logic;

      errIb   : in  MbxErrorArray   (NUM_ERROR_SRCS_G - 1 downto 0) := (others => MBX_ERROR_INIT_C);
      rdyIb   : out std_logic_vector(NUM_ERROR_SRCS_G - 1 downto 0);

      mbxOb   : out Lan9254StrmMstType;
      rdyOb   : in  std_logic := '1'
   );
end entity ESCTxMbxErr;

architecture rtl of ESCTxMbxErr is

   type StateType is ( IDLE, CMD, CODE );

   type RegType   is record
      state    : StateType;
      sel      : natural range 0 to NUM_ERROR_SRCS_G - 1;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state    => IDLE,
      sel      => 0
   );

   signal   r        : RegType                       := REG_INIT_C;
   signal   rin      : RegType;

begin

   P_COMB : process (r, errIb, rdyOb) is
      variable v : RegType;
   begin
      v   := r;

      mbxOb.ben                      <= "11";
      mbxOb.usr                      <= (others => '0');
      mbxOb.usr(MBX_TYP_ERR_C'range) <= MBX_TYP_ERR_C;
      mbxOb.last                     <= '0';
      mbxOb.valid                    <= '0';
      mbxOb.data                     <= MBX_ERR_CMD_C;

      rdyIb                          <= (others => '0');

      case ( r.state ) is
         when IDLE =>
            F_SEL : for i in 0 to NUM_ERROR_SRCS_G - 1 loop
               if ( errIb(i).vld = '1' ) then
                  v.state     := CMD;
                  v.sel       := i;
                  exit F_SEL;
               end if;
            end loop;
         when CMD  =>
            mbxOb.valid <= '1';
            if ( rdyOb = '1' ) then
               v.state := CODE;
            end if;

         when CODE =>
            mbxOb.data  <= errIb(r.sel).code;
            mbxOb.valid <= '1';
            mbxOb.last  <= '1';
            if ( rdyOb  = '1' ) then
               rdyIb(r.sel) <= '1';
               v.state      := IDLE;
            end if;
      end case;

      rin <= v;
   end process P_COMB;

   P_SEQ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

end architecture rtl;
