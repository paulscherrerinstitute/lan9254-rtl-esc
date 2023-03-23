library ieee;
use     ieee.std_logic_1164.all;

-- Synchronize parallel data between two clock domains.
-- Assumption is that data changes much slower than either
-- clock rate (slow status/controls)

entity SynchronizerVec is
   generic (
      STAGES_A2B_G : natural := 3;
      STAGES_B2A_G : natural := 3;
      W_A2B_G      : natural := 0;
      W_B2A_G      : natural := 0
   );
   port (
      clkA     : in  std_logic;
      dinA     : in  std_logic_vector(W_A2B_G - 1 downto 0) := (others => '0');
      douA     : out std_logic_vector(W_B2A_G - 1 downto 0);

      clkB     : in  std_logic;
      dinB     : in  std_logic_vector(W_B2A_G - 1 downto 0) := (others => '0');
      douB     : out std_logic_vector(W_A2B_G - 1 downto 0)
   );
end entity SynchronizerVec;

architecture Impl of SynchronizerVec is
   signal tokA    : std_logic := '0';
   signal tokB    : std_logic := '0';
   signal tokAatB : std_logic;
   signal tokBatA : std_logic;

   signal datA    : std_logic_vector(W_A2B_G - 1 downto 0) := (others => '0');
   signal datB    : std_logic_vector(W_B2A_G - 1 downto 0) := (others => '0');

   -- set KEEP to facilitate writing constraints
   attribute KEEP : string;
   attribute KEEP of datA : signal is "TRUE";
   attribute KEEP of datB : signal is "TRUE";
begin

   -- send a token back and forth between domains
   U_TOK_A2B : entity work.SynchronizerBit
      generic map (
         STAGES_G  => STAGES_A2B_G
      )
      port map (
         clk       => clkB,
         rst       => '0',
         datInp(0) => tokA,
         datOut(0) => tokAatB
      );

   U_TOK_B2A : entity work.SynchronizerBit
      generic map (
         STAGES_G  => STAGES_B2A_G
      )
      port map (
         clk       => clkA,
         rst       => '0',
         datInp(0) => tokB,
         datOut(0) => tokBatA
      );

   P_B : process ( clkB ) is
   begin
      if ( rising_edge( clkB ) ) then
         if ( tokB /= tokAatB ) then
            -- just received the token; latch values
            datB <= dinB;
            douB <= datA;
         end if;
         -- pass the token
         tokB <= tokAatB;
      end if;
   end process P_B;

   P_A : process ( clkA ) is
   begin
      if ( rising_edge( clkA ) ) then
         if ( tokA = tokBatA ) then
            -- just received the token; latch values
            datA <= dinA;
            douA <= datB;
         end if;
         -- flip and pass the token
         tokA <= not tokBatA;
      end if;
   end process P_A;
    
end architecture Impl;

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity tb is end entity tb;

architecture sim of tb is
  signal clkA : std_logic := '0';
  signal clkB : std_logic := '0';
  signal run  : boolean   := true;
  signal cnt  : unsigned(15 downto 0) := (others => '0');
begin
  process is begin
    wait for 1 us;
    clkA <= not clkA;
    if ( not run ) then wait; end if;
  end process;

  process is begin
    wait for 11.234 us;
    clkB <= not clkB;
    if ( not run ) then wait; end if;
  end process;

  process ( clkA ) is
  begin
    if ( rising_edge( clkA ) ) then cnt <= cnt + 1; end if;
  end process;

  U_DUT : entity work.SynchronizerVec
    generic map (
      W_A2B_G => 16
    )
    port map (
      clkA => clkA,
      clkB => clkB,
      dinA => std_logic_vector(cnt)
    );
end architecture sim;
