library ieee;
use     ieee.std_logic_1164.all;

-- General-purpose synchronizer. Re-implemented here
-- to be independent of other libraries.

entity SynchronizerBit is
   generic (
      STAGES_G : positive  := 2;
      WIDTH_G  : positive  := 1;
      RSTPOL_G : std_logic := '0'
   );
   port (
      clk      : in  std_logic;
      rst      : in  std_logic := '0';
      datInp   : in  std_logic_vector(WIDTH_G - 1 downto 0);
      datOut   : out std_logic_vector(WIDTH_G - 1 downto 0)
   );
end entity SynchronizerBit;

architecture rtl of SynchronizerBit is

  attribute syn_srlstyle  : string;
  attribute shreg_extract : string;
  attribute ASYNC_REG     : string;

begin

  GEN_SYNC : for i in datInp'range generate

      signal syncReg : std_logic_vector(STAGES_G - 1 downto 0) := (others => RSTPOL_G);

      attribute syn_srlstyle  of syncReg : signal is "registers";

      attribute shreg_extract of syncReg : signal is "no";

      attribute ASYNC_REG     of syncReg : signal is "TRUE";

  begin
      P_SYNC : process ( clk ) is
      begin
         if ( rising_edge( clk ) ) then
            if ( rst = '1' ) then
               syncReg <= (others => RSTPOL_G);
            else
               syncReg <= syncReg(syncReg'left - 1 downto syncReg'right) & datInp(i);
            end if;
         end if;
      end process P_SYNC;

      datOut(i) <= syncReg(syncReg'left);

  end generate GEN_SYNC;
end architecture rtl;
