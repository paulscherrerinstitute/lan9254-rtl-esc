library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Lan9254Pkg.all;

entity StrmMux is
   generic (
      NUM_MSTS_G    : natural :=  1;
      -- could mux destinations based on usr bits (not supported ATM)
      NUM_SUBS_G    : natural range 1 to 1 := 1
   );
   port (
      clk         : in  std_logic;
      rst         : in  std_logic;

      -- the mux is arbitrated when masters try to write; once a master
      -- is granted the mux it holds it until it asserts its corresponding
      -- bit in 'busLock' (and 'last' is seen)
      busLock     : in  std_logic_vector(NUM_MSTS_G - 1 downto 0)    := (others => '0');

      reqMstIb    : in  Lan9254StrmMstArray(NUM_MSTS_G - 1 downto 0) := (others => LAN9254STRM_MST_INIT_C);
      reqRdyIb    : out std_logic_vector(NUM_MSTS_G - 1 downto 0)    := (others => '1');

      repMstIb    : out Lan9254StrmMstArray(NUM_MSTS_G - 1 downto 0) := (others => LAN9254STRM_MST_INIT_C);
      repRdyIb    : in  std_logic_vector(NUM_MSTS_G - 1 downto 0)    := (others => '1');

      reqMstOb    : out Lan9254StrmMstArray(NUM_SUBS_G - 1 downto 0) := (others => LAN9254STRM_MST_INIT_C);
      reqRdyOb    : in  std_logic_vector(NUM_SUBS_G - 1 downto 0)    := (others => '1');

      repMstOb    : in  Lan9254StrmMstArray(NUM_SUBS_G - 1 downto 0) := (others => LAN9254STRM_MST_INIT_C);
      repRdyOb    : out std_logic_vector(NUM_SUBS_G - 1 downto 0)    := (others => '1');

      debug       : out std_logic_vector(63 downto 0)
   );
end entity StrmMux;

architecture rtl of StrmMux is

   type     StateType   is (IDLE, SEL);

   subtype  SelType     is integer range 0 to NUM_MSTS_G - 1;

   type     RegType     is record
      state             : StateType;
      sel               : SelType;
      reqActive         : std_logic;
      repActive         : std_logic;
   end record RegType;

   constant REG_INIT_C  : RegType := (
      state             => IDLE,
      sel               =>  0,
      reqActive         => '0',
      repActive         => '0'
   );

   signal   reqMstIbLoc    : Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
   signal   reqRdyIbLoc    : std_logic;
   signal   reqRdyIb_i     : std_logic_vector( reqRdyIb'range );
   signal   repMstIbLoc    : Lan9254StrmMstType;
   signal   repMstIb_i     : Lan9254StrmMstArray( repMstIb'range );
   signal   repRdyIbLoc    : std_logic          := '0';

   signal   r              : RegType            := REG_INIT_C;
   signal   rin            : RegType;

begin

   assert ( NUM_SUBS_G = 1 );

   P_MST_MUX  : process (r, reqMstIb, reqRdyIbLoc, repRdyIb, repMstIbLoc, busLock) is
      variable v : RegType;
   begin
      v := r;

      reqMstIbLoc <= LAN9254STRM_MST_INIT_C;
      reqRdyIb_i  <= (others => '0');

      repMstIb_i  <= (others => LAN9254STRM_MST_INIT_C);
      repRdyIbLoc <= '0';

      case ( r.state ) is
         when IDLE =>
            F_SEL : for i in 0 to NUM_MSTS_G - 1 loop
               if ( reqMstIb(i).valid = '1' ) then
                  reqMstIbLoc   <= reqMstIb(i);
                  reqRdyIb_i(i) <= reqRdyIbLoc;
                  repMstIb_i(i) <= repMstIbLoc;
                  repRdyIbLoc   <= repRdyIb(i);
                  v.reqActive := reqMstIb(i).valid and not ( reqRdyIbLoc and reqMstIb(i).last and not busLock(i) );
                  v.repActive := repMstIbLoc.valid and not ( repRdyIb(i) and repMstIbLoc.last and not busLock(i) );
                  if ( ( v.reqActive or v.repActive ) = '1' ) then
                     v.state := SEL;
                     v.sel   := i;
                  end if;
                  exit F_SEL;
               end if;
            end loop F_SEL;

         when SEL =>
            reqMstIbLoc       <= reqMstIb(r.sel);
            reqRdyIb_i(r.sel) <= reqRdyIbLoc;
            repMstIb_i(r.sel) <= repMstIbLoc;
            repRdyIbLoc       <= repRdyIb(r.sel);
            if ( reqMstIb(r.sel).valid = '1' ) then
               v.reqActive := not ( reqRdyIbLoc     and reqMstIb(r.sel).last );
            end if;
            if ( repMstIbLoc.valid = '1' ) then
               v.repActive := not ( repRdyIb(r.sel) and repMstIbLoc.last     );
            end if;
            if ( ( ( not ( v.reqActive or v.repActive ) ) and not busLock(r.sel) ) = '1' ) then
               v.state := IDLE;
            end if;

      end case;

      rin <= v;
   end process P_MST_MUX;

   P_MST_SEQ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_MST_SEQ;

   G_NO_SUB_MUX  : if ( NUM_SUBS_G = 1 ) generate
      reqMstOb(0) <= reqMstIbLoc;
      reqRdyIbLoc <= reqRdyOb(0);
      repMstIbLoc <= repMstOb(0);
      repRdyOb(0) <= repRdyIbLoc;
   end generate G_NO_SUB_MUX;

   reqRdyIb <= reqRdyIb_i;
   repMstIb <= repMstIb_i;

   P_DEBUG : process ( r, reqMstIb, reqRdyIb_i, repMstIb_i, repRdyIb, reqMstIbLoc, reqRdyOb, repMstOb, repRdyIbLoc, busLock ) is
      variable v : std_logic_vector( debug'range );
      variable m : natural;
   begin
      v := (others => '0');
      m := NUM_MSTS_G;
      if ( m > 4 ) then
         m := 4;
      end if;
      for i in m - 1 downto 0 loop
         v(i*8 + 0) := reqMstIb(i).valid;
         v(i*8 + 1) := reqMstIb(i).last;
         v(i*8 + 2) := busLock(i);
         v(i*8 + 3) := reqRdyIb_i(i);
         v(i*8 + 4) := repMstIb_i(i).valid;
         v(i*8 + 5) := repMstIb_i(i).last;
         v(i*8 + 6) := '0';
         v(i*8 + 7) := repRdyIb(i);
      end loop;
      v(4*8 + 1 downto 4*8 + 0) := std_logic_vector(to_unsigned(StateType'pos(r.state), 2));
      v(4*8 + 2 )               := r.reqActive;
      v(4*8 + 3 )               := r.repActive;
      v(4*8 + 7 downto 4*8 + 4) := std_logic_vector( to_unsigned(r.sel, 4) );

      v(5*8 + 0) := reqMstIbLoc.valid;
      v(5*8 + 1) := reqMstIbLoc.last;
      v(5*8 + 2) := '0';
      v(5*8 + 3) := reqRdyOb(0);
      v(5*8 + 4) := repMstOb(0).valid;
      v(5*8 + 5) := repMstOb(0).last;
      v(5*8 + 6) := '0';
      v(5*8 + 7) := repRdyIbLoc;
      debug <= v;
   end process P_DEBUG;

end architecture rtl;
