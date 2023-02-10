library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.Lan9254Pkg.all;

entity Lan9254HbiTb is
end entity Lan9254HbiTb;

-- Test bed for Lan9254Hbi (HBI interface to LAN9254)

architecture rtl of Lan9254HbiTb is

   constant CLOCK_FREQ_C : real := 1.0E8;

   signal   clk          : std_logic := '0';
   signal   rst          : std_logic := '0';
   signal   run          : boolean   := true;

   signal   ob           : Lan9254ReqType := LAN9254REQ_INIT_C;
   signal   ib           : Lan9254RepType := LAN9254REP_INIT_C;

   signal   hbiOut       : Lan9254HBIOutType;

   constant N_SIM_REGS_C : natural := 4;
   type     Slv32Array   is array (natural range <>) of std_logic_vector(31 downto 0);

   type HBIMemType is record
      mem                : Slv32Array(natural range 0 to N_SIM_REGS_C - 1);
      aptr               : integer;
      lrs                : std_logic;
      lws                : std_logic;
      lal                : std_logic;
      hbi                : Lan9254HBIInpType;
   end record HBIMemType;

   constant HBIMEM_INIT_C : HBIMemType := (
      mem               => (
         0 => not x"03020100",
         1 => not x"07060504",
         2 => not x"0B0A0908",
         3 => not x"0F0E0D0C"
      ),
      aptr              => -1,
      lrs               => '1',
      lws               => '1',
      lal               => '1',
      hbi               => LAN9254HBIINP_INIT_C
   );

   signal m              : HBIMemType := HBIMEM_INIT_C;

   signal min            : HBIMemType;

   signal hbus_i         : std_logic_vector(15 downto 0);
   signal hbus_o         : std_logic_vector(15 downto 0);

begin

   P_BUS : process (hbiOut, m) is
      variable v    : std_logic_vector(15 downto 0);
      variable wadr : natural;
      variable w    : std_logic_vector(31 downto 0);
      variable sw   : std_logic_vector( 1 downto 0);
   begin
      v := (others => 'X');
      wadr := m.aptr/4;
      if ( wadr >= m.mem'low and wadr <= m.mem'high ) then
         w := m.mem(wadr);
      else
         w := (others => 'X');
      end if;
      sw(0) := (hbiOut.rs or hbiOut.cs);
      for i in v'range loop
         sw(1) := hbiOut.ad_t(i);
         case ( sw ) is
            when "11" => v(i) := 'Z';
            when "01" => v(i) := hbiOut.ad(i);
            when "10" =>
               assert ( wadr >= m.mem'low and wadr <= m.mem'high ) report "invalid memory address" severity failure;
               if ( m.aptr - 4*wadr /= 0 ) then
                  v(i) := w(16 + i);
               else
                  v(i) := w(     i);
               end if;
               for lane in 1 downto 0 loop
                  if ( hbiOut.be(lane) = '1' ) then
                     v( 8*lane + 7 downto 8*lane ) := (others => 'X');
                  end if;
               end loop;
            when others =>
               assert false report "multiple bus drivers" severity failure;
         end case;
      end loop;
      hbus_i <= v;
   end process P_BUS;

   P_CLK : process is
   begin
      if ( not run ) then wait; end if;
      wait for (1.0/CLOCK_FREQ_C/2.0) * 1 sec;
      clk <= not clk;
   end process P_CLK;

   P_MEM : process(m, hbiOut, hbus_i) is
      variable v    : HBIMemType;
      variable act  : natural;
      variable wadr : natural;
      variable cs   : std_logic;
   begin
      v := m;

      cs := hbiOut.cs;

      v.hbi.ad := hbus_i;

      v.lrs := hbiOut.rs;
      v.lws := hbiOut.ws;
      v.lal := hbiOut.ale(0);

      if ( cs = '0' ) then
         act:= 0;
         if ( hbiOut.ws     = '0' ) then act := act + 1; end if;
         if ( hbiOut.rs     = '0' ) then act := act + 1; end if;
         if ( hbiOut.ale(0) = '0' ) then act := act + 1; end if;
         assert act <= 1
            report "FAILURE - only one of ws/rs/al must be active concurrently"
            severity failure;
      end if;

      if ( hbiOut.ale(0) = '1' and m.lal = '0' ) then
         v.aptr := to_integer( unsigned(hbiOut.ad(12 downto 0) & '0') );
      end if;

      if ( hbiOut.rs = '1' and m.lrs = '0' ) then
         v.aptr := -1;
      end if;

      if ( hbiOut.ws = '1' and m.lws = '0' ) then
         wadr := m.aptr/4;
         assert ( wadr >= m.mem'low and wadr <= m.mem'high ) report "invalid memory address" severity failure;
         if ( m.aptr - 4*wadr = 0 ) then
            if ( hbiOut.be(1) = '0' ) then
               v.mem(wadr)(15 downto  8) := hbus_i(15 downto 8);
            end if;
            if ( hbiOut.be(0) = '0' ) then
               v.mem(wadr)( 7 downto  0) := hbus_i( 7 downto 0);
            end if;
         else
            if ( hbiOut.be(1) = '0' ) then
               v.mem(wadr)(31 downto 24) := hbus_i(15 downto 8);
            end if;
            if ( hbiOut.be(0) = '0' ) then
               v.mem(wadr)(23 downto 16) := hbus_i( 7 downto 0);
            end if;
         end if;
         v.aptr := -1;
         -- if CS is raised concurrently with WS then ignore it here
         cs     := '0';
      end if;

      if ( cs = '1' ) then
         v := m;
      end if;

      min <= v;
   end process P_MEM;

   P_SEQ : process (clk ) is
   begin
      if ( rising_edge ( clk ) ) then
         if ( rst = '1' ) then
            m <= HBIMEM_INIT_C;
         else
            m <= min;
         end if;
      end if;
   end process P_SEQ;

   P_TST : process is

      variable exp : std_logic_vector(31 downto 0);
      variable s   : string(32 downto 1);
      variable rep : Lan9254RepType;

      procedure read(
         signal   o : inout Lan9254ReqType;
         signal   i : in    Lan9254RepType;
         variable r : out   Lan9254RepType;
         constant a : in    std_logic_vector(15 downto 0);
         constant b : in    std_logic_vector( 3 downto 0)
      ) is
         variable hbo : Lan9254ReqType;
      begin
         hbo := o;
         lan9254HBIRead( hbo, ib, a, b );
         o <= hbo;
         while ( (o.valid and i.valid) = '0' ) loop
            wait until rising_edge(clk);
         end loop;
         r        := i;
         o.valid <= '0';
         wait until rising_edge(clk);
      end procedure read;

      procedure write(
         signal   o : inout Lan9254ReqType;
         signal   i : in    Lan9254RepType;
         constant a : in    std_logic_vector(15 downto 0);
         constant d : in    std_logic_vector(31 downto 0);
         constant b : in    std_logic_vector( 3 downto 0)
      ) is
         variable hbo : Lan9254ReqType;
         variable dt  : std_logic_vector(d'range);
      begin
         hbo := o;
         dt  := d;
         for j in b'range loop
            if b(j) = '1' then
               dt(4*j+3 downto 4*j) := (others => 'X');
            end if;
         end loop;
         lan9254HBIWrite( hbo, ib, a, dt, b );
         o <= hbo;
         while ( (o.valid and i.valid) = '0' ) loop
            wait until rising_edge(clk);
         end loop;
         o.valid <= '0';
         wait until rising_edge(clk);
      end procedure write;


   begin
      read( ob, ib, rep, x"0004", "0000");
      assert rep.rdata = not x"07060504" report "Read32 data mismatch" severity failure;

      read( ob, ib, rep, x"0004", "0011");

      exp := (others => 'X');
      exp(31 downto 16) := not x"0706";
      assert rep.rdata = exp report "Read16 data mismatch" severity failure;

      read( ob, ib, rep, x"0004", "1011");

      exp := (others => 'X');
      exp(23 downto 16) := not x"06";
      if ( ib.rdata /= exp ) then
         for i in ib.rdata'range loop
           s(i+1) := std_logic'image(ib.rdata(i))(2);
         end loop;
         report s;
         for i in ib.rdata'range loop
           s(i+1) := std_logic'image(exp(i))(2);
         end loop;
         report s;
      end if;
      assert ib.rdata = exp report "Read8 data mismatch" severity failure;

      write( ob, ib, x"0004", x"deadbeef", "0000" );

      read(  ob, ib, rep, x"0004", "0000");

      write( ob, ib, x"0004", x"20304050", "0011" );
      read(  ob, ib, rep, x"0004", "0000");

      assert ib.rdata = x"2030beef" report "Write16 failed" severity failure;

      write( ob, ib, x"0004", x"aabbccdd", "1011" );
      read(  ob, ib, rep, x"0004", "0000");

      assert ib.rdata = x"20bbbeef" report "Write8 failed" severity failure;

      report "Test Passed";
      run <= false;
      wait;
   end process P_TST;

   U_DUT : entity work.Lan9254Hbi
      generic map (
         CLOCK_FREQ_G => CLOCK_FREQ_C
      )
      port map (
         clk          => clk,
         cen          => '1',
         rst          => rst,

         req          => ob,
         rep          => ib,

         hbiOut       => hbiOut,
         hbiInp       => m.hbi
      );

end architecture rtl;
