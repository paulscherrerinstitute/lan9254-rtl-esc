library ieee;
use     ieee.std_logic_1164.all;

library unisim;
use     unisim.vcomponents.all;

entity DeviceDna7 is
   port (
      clk : in  std_logic; -- 100MHz max
      rst : in  std_logic;

      dna : out std_logic_vector(56 downto 0);
      vld : out std_logic
   );
end entity DeviceDna7;

architecture rtl of DeviceDna7 is

   constant SREG_LEN_C  : natural                                   := dna'length + 1;
   constant SREG_INIT_C : std_logic_vector(SREG_LEN_C - 1 downto 0) := ( 0 => '1', others => '0' );
   signal   sreg        : std_logic_vector(SREG_LEN_C - 1 downto 0) := SREG_INIT_C;
   signal   dnaVld      : std_logic                                 := '0';
   signal   dnaRead     : std_logic                                 := '1';
   signal   dnaShift    : std_logic;
   signal   dnaOut      : std_logic;
begin

   dnaShift <= not dnaRead and not dnaVld;

   dnaVld   <= sreg( sreg'left );

   U_DNA_PORT : DNA_PORT
      generic map (
         SIM_DNA_VALUE => x"000_0000_dead_beef"
      )
      port map (
         CLK    => clk,
         DIN    => '0',
         READ   => dnaRead,
         SHIFT  => dnaShift,
         DOUT   => dnaOut
      );

   P_READ_DNA : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            dnaRead <= '1';
            sreg    <= SREG_INIT_C;
         else
            if ( '0' = dnaVld ) then
               if ( dnaRead = '1' ) then
                  dnaRead <= '0';
               else
                  sreg    <= sreg(sreg'left - 1 downto 0) & dnaOut;
               end if;
            end if;
         end if;
      end if;
   end process P_READ_DNA;

   dna <= sreg(dna'range);
   vld <= dnaVld;

end architecture rtl;
