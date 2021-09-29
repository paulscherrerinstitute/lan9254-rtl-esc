library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.Lan9254Pkg.all;
use work.ESCMbxPkg.all;

-- Convert error status from ESC controller into a mailbox message

entity ESCTxMbxErr is
   port (
      clk     : in  std_logic;
      rst     : in  std_logic;

      errCode : in  std_logic_vector(15 downto 0) := (others => '0');
      errVld  : in  std_logic := '0';
      errRdy  : out std_logic;

      mbxOb   : out Lan9254StrmMstType;
      rdyOb   : in  std_logic := '1'
   );
end entity ESCTxMbxErr;

architecture rtl of ESCTxMbxErr is

   type StateType is ( IDLE, LAST );

   type RegType   is record
      state    : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state    => IDLE
   );

   signal   r        : RegType                       := REG_INIT_C;
   signal   rin      : RegType;

begin

   P_COMB : process (r, errCode, errVld, rdyOb) is
      variable v : RegType;
   begin
      v   := r;

      mbxOb.ben                      <= "11";
      mbxOb.usr                      <= (others => '0');
      mbxOb.usr(MBX_TYP_ERR_C'range) <= MBX_TYP_ERR_C;
      mbxOb.last                     <= '0';
      mbxOb.valid                    <= errVld;
      mbxOb.data                     <= MBX_ERR_CMD_C;

      errRdy                         <= '0';

      case ( r.state ) is
         when IDLE =>
            if ( ( errVld and rdyOb ) = '1' ) then
               v.state := LAST;
            end if;
         when LAST =>
            mbxOb.data <= errCode;
            mbxOb.last <= '1';
            if ( ( errVld and rdyOb ) = '1' ) then
               errRdy  <= '1';
               v.state := IDLE;
            end if;
      end case;

      rin <= r;
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
