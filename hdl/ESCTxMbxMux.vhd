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

-- TX Mailbox multiplexer
-- streams are arbitrated in the order they are connected; 
-- i.e., mbxIb(0) has the highest priority.

entity ESCTxMbxMux is
   generic (
      NUM_STREAMS_G : natural
   );
   port (
      clk     : in  std_logic;
      rst     : in  std_logic;

      mbxIb   : in  Lan9254StrmMstArray(NUM_STREAMS_G - 1 downto 0) := (others => LAN9254STRM_MST_INIT_C);
      rdyIb   : out std_logic_vector   (NUM_STREAMS_G - 1 downto 0);

      mbxOb   : out Lan9254StrmMstType;
      rdyOb   : in  std_logic := '1'
   );
end entity ESCTxMbxMux;

architecture rtl of ESCTxMbxMux is
   type StateType is ( ARBITRATE, FORWARD );

   type RegType   is record
      state    : StateType;
      sel      : natural range 0 to NUM_STREAMS_G - 1;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state    => ARBITRATE,
      sel      => 0
   );

   signal   r        : RegType                       := REG_INIT_C;
   signal   rin      : RegType;
begin

   P_COMB : process ( r, mbxIb, rdyOb ) is
      variable   v : RegType;
      variable   m : Lan9254StrmMstType;
      variable   y : std_logic_vector(rdyIb'range);
   begin
      v  := r;
      m  := LAN9254STRM_MST_INIT_C;
      y  := (others => '0');

      case ( r.state ) is
         when ARBITRATE =>
            FOR_SEL : for i in 0 to NUM_STREAMS_G - 1 loop
               if ( mbxIb(i).valid = '1' ) then
                  v.sel   := i;
                  v.state := FORWARD;
--                  if ( rdyOb = '1' ) then
--                     m     := mbxIb(i);
--                     y(i)  := rdyOb;
--                     if ( mbxIb(i).last = '1' ) then
--                        v.state := ARBITRATE;
--                     end if;
--                  end if;
                  exit FOR_SEL;
               end if;
            end loop FOR_SEL;
            
         when FORWARD   =>
            m        := mbxIb(r.sel);
            y(r.sel) := rdyOb;
            if ( ( mbxIb(r.sel).valid and rdyOb and mbxIb(r.sel).last ) = '1' ) then
               v.state := ARBITRATE;
            end if;
      end case;

      rin   <= v;
      mbxOb <= m;
      rdyIb <= y;
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
