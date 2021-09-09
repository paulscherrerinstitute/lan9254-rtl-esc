library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.Lan9254Pkg.all;

architecture rtl of Lan9254HBI is

   constant MAX_DELAY_C : natural := 7;

   type    StateType is (IDLE, DELAY);

   subtype DelayType is natural range 0 to MAX_DELAY_C;

   type RegType is record
      state          : StateType;
      req            : Lan9254ReqType;
      rep            : Lan9254RepType;
      dly            : DelayType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state          => IDLE,
      rep            => LAN9254REP_INIT_C,
      req            => LAN9254REQ_INIT_C,
      dly            => 0
   );

   signal r           : RegType := REG_INIT_C;
   signal rin         : RegType;

   procedure readWrite_C(
      constant addr : in    integer;
      constant rdnwr: in    std_logic;
      variable data : inout integer;
      constant len  : in    integer
   );

   attribute foreign of readWrite_C : procedure is "VHPIDIRECT readWrite_C";

   procedure readWrite_C(
      constant addr : in    integer;
      constant rdnwr: in    std_logic;
      variable data : inout integer;
      constant len  : in    integer
   ) is
   begin
      -- empty; implemented in foreign proc
   end procedure readWrite_C;

begin

   assert DATA_WIDTH_G = 16 report "Only DATA_WIDTH_G = 16 implemented ATM, sorry" severity failure;
   assert ADDR_WIDTH_G = 16 report "Only ADDR_WIDTH_G = 16 implemented ATM, sorry" severity failure;
   assert MUXED_MODE_G      report "Only MUXED_MODE_G = true implemented ATM, sorry" severity failure;

   P_COMB : process( r, req ) is
      variable v : RegType;
      variable d : integer;
      variable a : integer;
      variable l : integer;
   begin
      v := r;

      -- reply only valid for 1 cycle
      v.rep.valid := '0';

      -- delay counter
      B_DELAY : if ( r.dly /= 0 ) then
         v.dly := r.dly - 1;
      else
         case ( r.state ) is
            when IDLE  =>
               if ( req.valid = '1' ) then
                  v.dly   := MAX_DELAY_C;
                  v.state := DELAY;
               end if;
                 
            when DELAY =>
               -- req.valid = '1' at this point
               a := to_integer(unsigned(req.addr));
               if ( req.rdnwr = '1' ) then
                  d := 0;
               else
                  d := to_integer(unsigned(req.wdata));
               end if;
               l := 0;
               for i in req.be'range loop
                  if ( req.be(i) = '1' ) then
                     l := l + 1;
                  end if;
               end loop;
               readWrite_C(a, req.rdnwr, d, l);
               v.rep.berr  := (others => '0');
               v.rep.valid := '1';
               if ( req.rdnwr = '1' ) then
                  v.rep.rdata := std_logic_vector(to_unsigned(d, v.rep.rdata'length));
               end if;
         end case;
      end if B_DELAY;

      rin <= v;
   end process P_COMB;

   P_SEQ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= REG_INIT_C;
         elsif ( cen = '1' ) then
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

   rep    <= r.rep;

end architecture rtl;
