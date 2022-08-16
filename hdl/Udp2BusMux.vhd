library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Udp2BusPkg.all;

entity Udp2BusMux is
   generic (
      ADDR_MSB_G    : natural := 29;
      ADDR_LSB_G    : natural := 27;
      NUM_MSTS_G    : natural :=  1;
      NUM_SUBS_G    : natural
   );
   port (
      clk         : in  std_logic;
      rst         : in  std_logic;

      reqIb       : in  Udp2BusReqArray(NUM_MSTS_G - 1 downto 0) := (others => UDP2BUSREQ_INIT_C);
      repIb       : out Udp2BusRepArray(NUM_MSTS_G - 1 downto 0) := (others => UDP2BUSREP_ERROR_C);

      reqOb       : out Udp2BusReqArray(NUM_SUBS_G - 1 downto 0) := (others => UDP2BUSREQ_INIT_C);
      repOb       : in  Udp2BusRepArray(NUM_SUBS_G - 1 downto 0) := (others => UDP2BUSREP_ERROR_C)
   );
end entity Udp2BusMux;

architecture rtl of Udp2BusMux is

   type     StateType   is (IDLE, SEL);

   subtype  SelType     is natural range 0 to NUM_MSTS_G - 1;

   type     RegType     is record
      state             : StateType;
      sel               : SelType;
   end record RegType;

   constant REG_INIT_C  : RegType := (
      state             => IDLE,
      sel               => 0
   );

   signal   reqIbLoc    : Udp2BusReqType   := UDP2BUSREQ_INIT_C;
   signal   repIbLoc    : Udp2BusRepType;

   signal   r           : RegType          := REG_INIT_C;
   signal   rin         : RegType;

begin

   assert ( NUM_SUBS_G = 1 ) or ( NUM_SUBS_G <= 2**(ADDR_MSB_G - ADDR_LSB_G + 1) );

   P_MST_MUX  : process (r, reqIb, repIbLoc) is
      variable v : RegType;
   begin
      v := r;

      reqIbLoc <= UDP2BUSREQ_INIT_C;
      repIb    <= (others => UDP2BUSREP_INIT_C);

      case ( r.state ) is
         when IDLE =>
            F_SEL : for i in 0 to NUM_MSTS_G - 1 loop
               if ( reqIb(i).valid = '1' ) then
                  reqIbLoc <= reqIb(i);
                  repIb(i) <= repIbLoc;
                  if ( repIbLoc.valid /= '1' ) then
                     v.state := SEL;
                     v.sel   := i;
                  end if;
                  exit F_SEL;
               end if;
            end loop F_SEL;

         when SEL =>
            reqIbLoc     <= reqIb(r.sel);
            repIb(r.sel) <= repIbLoc;
            if ( (reqIb(r.sel).valid and repIbLoc.valid) = '1' ) then
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

   G_SUB_MUX  : if ( NUM_SUBS_G > 1 ) generate

      P_SUB_MUX  : process (reqIbLoc, repOb) is
         variable sIdx : natural range 0 to 2**(ADDR_MSB_G - ADDR_LSB_G + 1) - 1;
      begin
         reqOb       <= (others => reqIbLoc);
         repIbLoc    <= UDP2BUSREP_ERROR_C;
         for i in reqOb'range loop
            reqOb(i).valid <= '0';
         end loop;
         sIdx := to_integer(unsigned(reqIbLoc.dwaddr(ADDR_MSB_G downto ADDR_LSB_G)));
         if ( sIdx < NUM_SUBS_G ) then
            reqOb(sIdx).valid <= reqIbLoc.valid;
            repIbLoc         <= repOb(sIdx);
         end if;
      end process P_SUB_MUX;

   end generate G_SUB_MUX;

   G_NO_SUB_MUX  : if ( NUM_SUBS_G = 1 ) generate
      reqOb(0) <= reqIbLoc;
      repIbLoc <= repOb(0);
   end generate G_NO_SUB_MUX;

end architecture rtl;
