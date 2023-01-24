library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Udp2BusPkg.all;

entity Udp2BusAsyncTb is
end entity Udp2BusAsyncTb;
architecture Sim of Udp2BusAsyncTb is

  signal clkIb     : std_logic := '0';
  signal clkOb     : std_logic := '0';

  signal reqIb     : Udp2BusReqType := UDP2BUSREQ_INIT_C;
  signal repIb     : Udp2BusRepType := UDP2BUSREP_INIT_C;
  signal reqOb     : Udp2BusReqType := UDP2BUSREQ_INIT_C;
  signal repOb     : Udp2BusRepType := UDP2BUSREP_INIT_C;

  procedure ticki is begin
    wait until rising_edge( clkIb );
  end procedure ticki;
  
  procedure ticko is begin
    wait until rising_edge( clkOb );
  end procedure ticko;

  procedure mst(
    signal req : inout Udp2BusReqType
  ) is
  begin
    req       <= req;
    req.valid <= '1';
    while ( ( req.valid and repIb.valid ) = '0' ) loop
      ticki;
    end loop;
    req.valid <= '0';
  end procedure mst;

  procedure sub(
    signal    rep : inout Udp2BusRepType;
    constant  w   : in    natural := 0
  ) is
    variable  ww  : natural;
  begin
    ww        := w;
    rep       <= rep;
    while ( reqOb.valid = '0' or ww > 0 ) loop
      if ( reqOb.valid = '0' ) then
        ww := w;
      else
        ww := ww - 1;
      end if;
      ticko;
    end loop;
    rep.valid <= '1';
    ticko;
    rep.valid <= '0';
  end procedure sub;

  signal runI : boolean := true;
  signal runO : boolean := true;

begin

  process is begin
    wait for 5 ns;
    clkIb <= not clkIb;
    if ( not runI and not runO ) then
      wait;
    end if;
  end process;

  process is begin
    wait for 9.1 ns;
    clkOb <= not clkOb;
    if ( not runI and not runO ) then
      wait;
    end if;
  end process;

  P_MST : process is
  begin
    mst( reqIb );
    ticki;
    runI <= false;
    wait;
  end process P_MST;

  P_SUB : process is
  begin
    sub( repOb );
    ticko;
    runO <= false;
    wait;
  end process P_SUB;


  U_DUT : entity work.Udp2BusAsync
    port map (
      clkIb => clkIb,
      reqIb => reqIb,
      repIb => repIb,

      clkOb => clkOb,
      reqOb => reqOb,
      repOb => repOb
    );
end architecture Sim;
