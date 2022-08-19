-- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
-- FIXME: this is work-in-progress and not complete!
-- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     std.textio.all;

use     work.ESCBasicTypesPkg.all;
use     work.Lan9254ESCPkg.all;

entity GatherFwParams is
end entity GatherFwParams;

architecture soft of GatherFwParams is

   -- FIXME: should obtain this from the application!
   constant TXPDO_MXMAP_C : natural                       := 16;
   constant PROM_CAT_ID_C : natural                       := 1;
   constant I2CP_CAT_ID_C : natural                       := 2;
   constant DFLT_MACADD_C : std_logic_vector(47 downto 0) := x"f106a98e0200";  -- 00:02:8e:a9:06:f1
   constant DFLT_IP4ADD_C : std_logic_vector(31 downto 0) := x"0A0A0A0A";      -- 10.10.10.10
   constant DFLT_UDPPRT_C : std_logic_vector(15 downto 0) := x"0010";          -- 4096
   constant ENBL_FOE_C    : natural                       := 1;
   constant ENBL_EOE_C    : natural                       := 1;
   constant ENBL_VOE_C    : natural                       := 0;

begin

   P_WORK : process is
      variable l  : line;
      variable ma : string(1 to 3*6);
      variable ia : string(1 to 3*6);
   begin
      write(l, string'("ESC_SM0_SMA_C = 0x")); write(l, toString(ESC_SM0_SMA_C)); writeline(output, l);
      write(l, string'("ESC_SM0_SMC_C = 0x")); write(l, toString(ESC_SM0_SMC_C)); writeline(output, l);
      write(l, string'("ESC_SM0_LEN_C = 0x")); write(l, toString(ESC_SM0_LEN_C)); writeline(output, l);
      write(l, string'("ESC_SM0_MXL_C = 0x")); write(l, toString(ESC_SM0_MXL_C)); writeline(output, l);

      write(l, string'("ESC_SM1_SMA_C = 0x")); write(l, toString(ESC_SM1_SMA_C)); writeline(output, l);
      write(l, string'("ESC_SM1_SMC_C = 0x")); write(l, toString(ESC_SM1_SMC_C)); writeline(output, l);
      write(l, string'("ESC_SM1_LEN_C = 0x")); write(l, toString(ESC_SM1_LEN_C)); writeline(output, l);

      write(l, string'("ESC_SM2_SMA_C = 0x")); write(l, toString(ESC_SM2_SMA_C)); writeline(output, l);
      write(l, string'("ESC_SM2_SMC_C = 0x")); write(l, toString(ESC_SM2_SMC_C)); writeline(output, l);
      write(l, string'("ESC_SM2_LEN_C = 0x")); write(l, toString(ESC_SM2_LEN_C)); writeline(output, l);
      write(l, string'("ESC_SM2_MXL_C = 0x")); write(l, toString(ESC_SM2_MXL_C)); writeline(output, l);

      write(l, string'("ESC_SM3_SMA_C = 0x")); write(l, toString(ESC_SM3_SMA_C)); writeline(output, l);
      write(l, string'("ESC_SM3_SMC_C = 0x")); write(l, toString(ESC_SM3_SMC_C)); writeline(output, l);
      write(l, string'("ESC_SM3_LEN_C = 0x")); write(l, toString(ESC_SM3_LEN_C)); writeline(output, l);
      write(l, string'("ESC_SM3_MXL_C = 0x")); write(l, toString(ESC_SM3_MXL_C)); writeline(output, l);

      write(l, string'("TXPDO_MXMAP_C =   ")); write(l, TXPDO_MXMAP_C); writeline(output, l);

      write(l, string'("PROM_CAT_ID_C = ")); write(l, PROM_CAT_ID_C); writeline(output, l);
      write(l, string'("I2CP_CAT_ID_C = ")); write(l, I2CP_CAT_ID_C); writeline(output, l);

      for i in 0 to 5 loop
          ma(3*i+1 to 3*i+1) := toString( DFLT_MACADD_C(47 - 4*2*i     downto 47 - 4*2*i - 3    ) );
          ma(3*i+2 to 3*i+2) := toString( DFLT_MACADD_C(47 - 4*2*i - 4 downto 47 - 4*2*i - 3 - 4) );
          ma(3*i+3 to 3*i+3) := ":";
      end loop;
      write(l, string'("DFLT_MACADD = """)); write(l, ma(1 to 3*6-1)); write(l, string'("""")); writeline(output, l);

      write(l, string'("DFLT_IP4ADD = """));

      for i in 0 to 3 loop
         write(l, to_integer( unsigned( DFLT_IP4ADD_C(7+8*i downto 8*i) ) ));
         if ( i /= 3 ) then
            write(l,string'("."));
         end if;
      end loop;
      write(l, string'(""""));

      writeline(output, l);

      write(l, string'("ENBL_EOE_C = ")); write(l, ENBL_EOE_C ); writeline(output, l);
      write(l, string'("ENBL_FOE_C = ")); write(l, ENBL_FOE_C ); writeline(output, l);
      write(l, string'("ENBL_VOE_C = ")); write(l, ENBL_VOE_C ); writeline(output, l);

      wait; 
   end process P_WORK;

end architecture soft;
