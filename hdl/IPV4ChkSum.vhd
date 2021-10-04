library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity IPV4ChkSum is
   generic (
      RESET_VAL_G : std_logic_vector(15 downto 0) := (others => '0');
      BYTE_SWAP_G : boolean := true
   );
   port (
      clk         : in  std_logic;
      cen         : in  std_logic := '1';
      rst         : in  std_logic;

      data        : in  std_logic_vector(15 downto 0);

      chkSum      : out std_logic_vector(15 downto 0)
   );
end entity IPV4ChkSum;

architecture rtl of IPV4ChkSum is

   function swap(
      constant x : in  std_logic_vector(15 downto 0)
   ) return unsigned is
   begin
      if ( BYTE_SWAP_G ) then
         return unsigned(x(7 downto 0) & x(15 downto 8));
      else
         return unsigned(x);
      end if;
   end function swap;

   function to_integer(constant x : std_logic) return integer is
   begin
      if ( x = '1' ) then return 1; else return 0; end if;
   end function to_integer;

   constant RESET_VAL_C : unsigned(16 downto 0) := "0" & swap(RESET_VAL_G);

   signal   sum         : unsigned(16 downto 0) := RESET_VAL_C;

begin

   P_CKSUM : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            sum <= RESET_VAL_C;
         elsif ( cen = '1' ) then
            sum <= ('0' & sum(15 downto 0)) + ('0' & swap(data) ) + sum(16 downto 16);
         end if;
      end if;
   end process P_CKSUM;

   chkSum <= std_logic_vector( swap( std_logic_vector( sum(15 downto 0) ) ) );
   
end architecture rtl;

