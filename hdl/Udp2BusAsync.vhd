library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Udp2BusPkg.all;

-- async coupler between two clock domains
-- (not highly efficient)

entity Udp2BusAsync is
   generic (
      STAGES_I2O_G : natural := 2;
      STAGES_O2I_G : natural := 2
   );
   port (
      clkIb        : in  std_logic;
      rstIb        : in  std_logic      := '0';

      reqIb        : in  Udp2BusReqType := UDP2BUSREQ_INIT_C;
      repIb        : out Udp2BusRepType := UDP2BUSREP_ERROR_C;

      clkOb        : in  std_logic;
      rstOb        : in  std_logic      := '0';
      reqOb        : out Udp2BusReqType := UDP2BUSREQ_INIT_C;
      repOb        : in  Udp2BusRepType := UDP2BUSREP_ERROR_C
   );
end entity Udp2BusAsync;

architecture rtl of Udp2BusAsync is
   attribute ASYNC_REG  : string;

   signal   i2oTgl      : std_logic := '0';
   signal   o2iTgl      : std_logic := '0';
   signal   i2oOut      : std_logic;
   signal   o2iOut      : std_logic;
   signal   o2iOutLst   : std_logic := '0';

begin

   B_Udp2BusAsync_CCSync : block
      signal i2o    : std_logic_vector(STAGES_I2O_G - 1 downto 0) := (others => '0');
      signal o2i    : std_logic_vector(STAGES_I2O_G - 1 downto 0) := (others => '0');
      attribute ASYNC_REG of i2o : signal is "TRUE";
      attribute ASYNC_REG of o2i : signal is "TRUE";

      signal i2oReq : Udp2BusReqType := UDP2BUSREQ_INIT_C;
      signal o2iRep : Udp2BusRepType := UDP2BUSREP_INIT_C;
   begin
      P_I2O : process ( clkOb ) is
      begin
         if ( rising_edge( clkOb ) ) then
            i2o <= i2o(i2o'left - 1 downto 0) & i2oTgl;

            if ( ( repOb.valid and (i2oOut xor o2iTgl) ) = '1' ) then
               o2iTgl <= not o2iTgl;
               o2iRep <= repOb;
            end if;
         end if;
      end process P_I2O;

      P_O2I : process ( clkIb ) is
      begin
         if ( rising_edge( clkIb ) ) then
            o2i <= o2i(o2i'left - 1 downto 0) & o2iTgl;

            if ( o2iOutLst = i2oTgl ) then
               i2oReq <= reqIb;

               if ( reqIb.valid = '1' ) then
                  i2oTgl <= not i2oTgl;
               end if;
            end if;

            o2iOutLst <= o2iOut;
         end if;
      end process P_O2I;

      P_COMB : process ( o2iOut, o2iOutLst, i2oReq, o2iRep, i2oOut, o2iTgl ) is
      begin

         reqOb       <= i2oReq;
         reqOb.valid <= i2oOut xor o2iTgl;

         repIb       <= o2iRep;
         repIb.valid <= o2iOut xor o2iOutLst;

      end process P_COMB;


      i2oOut <= i2o(i2o'left);
      o2iOut <= o2i(o2i'left);
   end block B_Udp2BusAsync_CCSync;

end architecture rtl;
