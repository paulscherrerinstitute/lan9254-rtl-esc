------------------------------------------------------------------------------
--      Copyright (c) 2022-2023 by Paul Scherrer Institute, Switzerland
--      All rights reserved.
--  Authors: Till Straumann
--  License: PSI HDL Library License, Version 2.0 (see License.txt)
------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Udp2BusPkg.all;

entity Bus2BusAsyncAltTb is
end entity Bus2BusAsyncAltTb;
architecture Sim of Bus2BusAsyncAltTb is

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
    signal    req : inout Udp2BusReqType;
    constant  a   : in    natural;
    constant  v   : in    integer := -1
  ) is
  begin
    req        <= req;
    req.valid  <= '1';
    req.dwaddr <= std_logic_vector( to_unsigned( a, req.dwaddr'length ) );
    if ( v < 0 ) then
       req.rdnwr <= '1';
       req.data  <= (others => 'X');
       req.be    <= "0000";
    else
       req.rdnwr <= '0';
       req.data  <= std_logic_vector( to_unsigned( v, req.data'length ) );
       req.be    <= "0111";
    end if;
    ticki;
    while ( ( req.valid and repIb.valid ) = '0' ) loop
      ticki;
    end loop;
    assert repIb.berr = '0'
      report "Unexpected BERR"
      severity failure;
    assert (v >= 0) or to_integer(unsigned(not repIb.rdata)) = a
      report "Unexpected read data"
      severity failure;
    req.valid  <= '0';
    req.dwaddr <= (others => 'X');
    req.data   <= (others => 'X');
    req.be     <= (others => 'X');
    req.rdnwr  <= 'X';
  end procedure mst;

  procedure sub(
    signal    rep : inout Udp2BusRepType;
    constant  ea  : in    natural;
    constant  ed  : in    integer := -1;
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
    assert (ed < 0) = (reqOb.rdnwr = '1')
      report "unexpected RDNWR"
      severity failure;
    assert reqOb.rdnwr = '1' or reqOb.be = "0111"
      report "unexpected byte-enables"
      severity failure;
    assert to_integer(unsigned(reqOb.dwaddr)) = ea
      report "unexpected address"
      severity failure;
    assert reqOb.rdnwr = '1' or to_integer(unsigned(reqOb.data)) = ed
      report "unexpected data"
      severity failure;
    rep.valid <= '1';
    rep.berr  <= '0';
    if ( reqOb.rdnwr = '1' ) then
       rep.rdata <= not std_logic_vector( resize( unsigned(reqOb.dwaddr), rep.rdata'length ) );
    else
       rep.rdata <= (others => 'X');
    end if;
    ticko;
    rep.valid <= '0';
    ticko;
  end procedure sub;

  signal runI : boolean := true;
  signal runO : boolean := true;

  signal per  : time := 5 ns;

  constant N_PER : natural := 5;

begin

  process is begin
    wait for per;
    clkIb <= not clkIb;
    if ( not runI and not runO ) then
      wait;
    end if;
  end process;

  process is begin
    wait for 5 ns;
    clkOb <= not clkOb;
    if ( not runI and not runO ) then
      wait;
    end if;
  end process;

  P_MST : process is
  begin
    ticki;
    ticki;
    for p in 1 to N_PER loop
      case p is
        when 1 => per <= 1.123 ns;
        when 2 => per <= 4.896 ns;
        when 3 => per <= 5 ns;
        when 4 => per <= 5.123 ns;
        when others => per <= 22.33 ns;
      end case;
      ticki;
      mst( reqIb, 33, 44 );
      ticki;
      mst( reqIb, 22, -22 );
      ticki;
      -- back-to back
      for w in 0 to 2 loop
        mst( reqIb, 3, 4);
        mst( reqIb, 5, 6);
        mst( reqIb, 7, -7);
        mst( reqIb, 8, 9);
        mst( reqIb,10, -10);
        mst( reqIb,11, -11);
      end loop;
    end loop;
    runI <= false;
    wait;
  end process P_MST;

  P_SUB : process is
  begin
    ticko;
    ticko;
    for p in 1 to N_PER loop
      sub( repOb, 33, 44 ); ticko;
      sub( repOb, ea => 22, ed => -1 ); ticko;
      for w in 0 to 2 loop
        sub( repOb, 3,  4, w);
        sub( repOb, 5,  6, w);
        sub( repOb, 7, -1, w);
        sub( repOb, 8,  9, w);
        sub( repOb,10, -1, w);
        sub( repOb,11, -1, w);
      end loop;
    end loop;
    runO <= false;
    wait;
  end process P_SUB;

  P_MSG : process is
  begin
    wait until not runO and not runI;
    report "Test PASSED";
    wait;
  end process P_MSG;

--  U_DUT : entity work.Udp2BusAsync
--    port map (
--      clkIb => clkIb,
--      reqIb => reqIb,
--      repIb => repIb,
--
--      clkOb => clkOb,
--      reqOb => reqOb,
--      repOb => repOb
--    );
  U_DUT : entity work.Bus2BusAsync
    port map (
      clkMst => clkIb,
      reqMst => reqIb,
      repMst => repIb,

      clkSub => clkOb,
      reqSub => reqOb,
      repSub => repOb
    );
end architecture Sim;
