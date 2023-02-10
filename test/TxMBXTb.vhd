library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.ESCBasicTypesPkg.all;
use work.Lan9254Pkg.all;
use work.Lan9254ESCPkg.all;
use work.EEEmulPkg.all;
use work.EEPROMContentPkg.all;
use work.ESCMBXPkg.all;

entity TxMBXTb is
end entity TxMBXTb;

architecture rtl of TxMBXTb is

   type   Slv16Array is array (natural range <>) of std_logic_vector(15 downto 0);

   type   TestDrvType is record
      len    : natural range 0 to to_integer(unsigned(ESC_SM1_LEN_C));
      prefix : unsigned        (15 downto 0);
      cnt    : unsigned        ( 2 downto 0);
      typ    : std_logic_vector( 3 downto 0);
   end record TestDrvType;

   type   TestVecArray is array ( natural range <> ) of TestDrvType;

   procedure feed(
      signal   clk : in    std_logic;
      constant tst : in    TestDrvType;
      signal   mst : inout Lan9254StrmMstType;
      signal   rdy : in    std_logic
   ) is
   begin
      mst <= mst;
      for i in 1 to (tst.len + 1)/2 loop
         mst.data            <= std_logic_vector(tst.prefix + i);
         mst.valid           <= '1';
         mst.usr(3 downto 0) <= tst.typ;
         if ( i = ( tst.len + 1 )/2 ) then
           mst.last            <= '1';
           if ( tst.len mod 2 = 0 ) then
              mst.ben <= "11";
           else
              mst.ben <= "01";
           end if;
         else
           mst.ben             <= "11";
           mst.last            <= '0';
         end if;
         wait until rising_edge( clk );
         while ( ( mst.valid and rdy ) = '0' ) loop
            wait until rising_edge( clk );
         end loop;
      end loop;
      mst.valid <= '0';
   end procedure feed;

   procedure fakeSM01(
      signal   req : in    LAN9254ReqType;
      signal   rep : inout LAN9254RepType;
      variable ok  : out   boolean;
      constant rpt : std_logic;
      constant act : std_logic_vector(3 downto 0) := "0011"
   ) is
   begin
      ok  := true;
      rep <= rep;
      if ( req.rdnwr = '1' ) then
         if    (   req.addr = x"0800" ) then
            if ( req.be = HBI_BE_W0_C ) then
               rep.rdata(15 downto  0)  <= ESC_SM0_SMA_C;
            else
               rep.rdata(31 downto 16)  <= ESC_SM0_LEN_C;
            end if;
         elsif (   req.addr = x"0808" ) then
            if ( req.be = HBI_BE_W0_C ) then
               rep.rdata(15 downto  0)  <= ESC_SM1_SMA_C;
            else
               rep.rdata(31 downto 16)  <= ESC_SM1_LEN_C;
            end if;
         elsif (   req.addr = x"0810" ) then
            if ( req.be = HBI_BE_W0_C ) then
               rep.rdata(15 downto  0)  <= ESC_SM2_SMA_C;
            else
               rep.rdata(31 downto 16)  <= ESC_SM2_LEN_C;
            end if;
         elsif (   req.addr = x"0818" ) then
            if ( req.be = HBI_BE_W0_C ) then
               rep.rdata(15 downto  0)  <= ESC_SM3_SMA_C;
            else
               rep.rdata(31 downto 16)  <= ESC_SM3_LEN_C;
            end if;
         elsif (   req.addr = x"0804" ) then
            if ( req.be(0) = HBI_BE_ACT_C ) then
               rep.rdata(7 downto 0) <= ESC_SM0_SMC_C;
            end if;
            if ( req.be(2) = HBI_BE_ACT_C ) then
               rep.rdata(16 + EC_SM_ACT_IDX_C) <= act(0);
            end if;
         elsif (   req.addr = x"080C" ) then
            if ( req.be(0) = HBI_BE_ACT_C ) then
               rep.rdata(7 downto 0) <= ESC_SM1_SMC_C;
            end if;
            if ( req.be(2) = HBI_BE_ACT_C ) then
               rep.rdata(16 + EC_SM_ACT_DIS_IDX_C) <= act(1);
               rep.rdata(16 + EC_SM_ACT_RPT_IDX_C) <= rpt;
            end if;
         elsif (   req.addr = x"0814" ) then
            if ( req.be(0) = HBI_BE_ACT_C ) then
               rep.rdata(7 downto 0) <= ESC_SM2_SMC_C;
            end if;
            if ( req.be(2) = HBI_BE_ACT_C ) then
               rep.rdata(16 + EC_SM_ACT_IDX_C) <= act(2);
            end if;
         elsif (   req.addr = x"081C" ) then
            if ( req.be(0) = HBI_BE_ACT_C ) then
               rep.rdata(7 downto 0) <= ESC_SM3_SMC_C;
            end if;
            if ( req.be(2) = HBI_BE_ACT_C ) then
               rep.rdata(16 + EC_SM_ACT_IDX_C) <= act(3);
            end if;
         else
            ok := false;
         end if;
      else
         if    ( req.addr = x"0800" ) then
         elsif ( req.addr = x"0804" ) then
         elsif ( req.addr = x"0808" ) then
         elsif ( req.addr = x"080c" ) then
         elsif ( req.addr = x"0810" ) then
         elsif ( req.addr = x"0814" ) then
         elsif ( req.addr = x"0818" ) then
         elsif ( req.addr = x"081c" ) then
         else
            ok := false;
         end if;
      end if;
   end procedure fakeSM01;

   procedure escSetState(
      signal   clk : in    std_logic;
      signal   req : in    LAN9254ReqType;
      signal   rep : inout LAN9254RepType;
      signal   rpt : inout std_logic;
      constant st  : in    ESCStateType
   ) is
      variable don   : std_logic;
      variable stat  : std_logic;
      variable i     : natural;
      variable ok    : boolean;
   begin
     rep  <= rep;
     rpt  <= rpt;
     don  := '0';
     stat := '1';
     while ( don = '0' ) loop
        if ( req.valid = '1' ) then
           rep.valid <= '1';
           rep.rdata <= (others => '0');
           fakeSM01( req, rep, ok, rpt );
           if ( not ok ) then
              if ( req.rdnwr = '1' ) then
                 if ( req.addr = x"220" ) then
                    rep.rdata( EC_AL_EREQ_CTL_IDX_C ) <= stat;
                 elsif (   req.addr = x"0120" ) then
                    rep.rdata( 3 downto 0 ) <= toSlv( st );
                    stat := '0';
                 else
                    assert false report "escSetState: READ from unexpected address " & toString(req.addr) severity failure;
                 end if;
              else
                 if    ( req.addr = x"0204" ) then
                 elsif ( req.addr = x"305C" ) then
                 elsif ( req.addr = x"3054" ) then
                 elsif ( req.addr = x"0134" ) then
                 elsif ( req.addr = x"0130" ) then
                    if ( req.data(3 downto 0) = toSlv( st ) ) then
                       don := '1';
                    end if;
                 else
                    assert false report "escSetState: WRITE to unexpected address " & toString(req.addr) severity failure;
                 end if;
              end if;
           end if;
           wait until rising_edge( clk );
           rep.valid <= '0';
        end if;
        wait until rising_edge( clk );
     end loop;
   end procedure escSetState;


   procedure mbxRep(
      signal   clk : in    std_logic;
      signal   req : in    LAN9254ReqType;
      signal   rep : inout LAN9254RepType;
      signal   rpt : inout std_logic
   ) is
      variable don   : std_logic;
      variable stat  : std_logic;
      variable smok  : boolean;
   begin
     rep  <= rep;
     rpt  <= rpt;
     don  := '0';
     stat := '1';
     rpt  <= not rpt;
     wait until rising_edge( clk );
     while ( don = '0' ) loop
        if ( req.valid = '1' ) then
           rep.valid <= '1';
           rep.rdata <= (others => '0');
           fakeSM01( req, rep, smok, rpt );
           if ( not smok ) then
              if ( req.rdnwr = '1' ) then
                 if ( req.addr = x"220" ) then
                    rep.rdata( EC_AL_EREQ_SMA_IDX_C ) <= stat;
                 elsif (   req.addr = x"0824" ) then
                 elsif (   req.addr = x"082C" ) then
                 elsif (   req.addr = x"0834" ) then
                 elsif (   req.addr = x"083C" ) then
                    don := '1';
                 else
                    assert false report "mbxRep: READ from unexpected address " & toString(req.addr) severity failure;
                 end if;
              else
                 if    ( req.addr = x"ffff" ) then
                 else
                    assert false report "mbxRep: WRITE to unexpected address " & toString(req.addr) severity failure;
                 end if;
              end if;
           end if;
           wait until rising_edge( clk );
           rep.valid <= '0';
        end if;
        wait until rising_edge( clk );
     end loop;
   end procedure mbxRep;

   procedure mbxAck(
      signal   clk : in    std_logic;
      signal   req : in    LAN9254ReqType;
      signal   rep : out   LAN9254RepType;
      signal   rdy : in    std_logic
   ) is
      variable waddr : unsigned(req.addr'range);
      variable don   : std_logic;
      variable ack   : std_logic;
   begin

     ack := '1';
     don := '0';

     while ( don = '0' ) loop
        if ( req.valid = '1' ) then
           rep.valid <= '1';
           rep.rdata <= (others => '0');
           if ( req.rdnwr = '1' ) then
              if ( req.addr = x"220" ) then
                 rep.rdata( EC_AL_EREQ_SM1_IDX_C ) <= ack;
              elsif (   req.addr = x"080C" ) then
                 ack := '0';
              else
                 assert false report "mbxACK: READ from unexpected address " & toString(req.addr) severity failure;
              end if;
           else
              waddr := unsigned(ESC_SM1_SMA_C(waddr'range));
              waddr(1) := '0';
              if ( req.addr = waddr ) then
                 don := '1';
              else
                 assert false report "mbxACK: WRITE to unexpected address " & toString(req.addr) severity failure;
              end if;
           end if;
           wait until rising_edge( clk );
           rep.valid <= '0';
        end if;
        wait until rising_edge( clk );
     end loop;
    end procedure mbxAck;

   procedure check(
      signal   clk : in    std_logic;
      constant tst : in    TestDrvType;
      signal   req : in    LAN9254ReqType;
      signal   rep : out   LAN9254RepType;
      constant rpt : in    boolean := false
   ) is
      variable tmp   : natural;
      variable idx   : natural;
      variable lidx  : natural;
      variable ldat  : natural;
      variable expad : unsigned(15 downto 0);
      variable expbe : std_logic_vector(3 downto 0);
      variable expdt : unsigned(15 downto 0);
      variable lst1b : boolean;
      variable timo  : natural;
   begin
      ldat := tst.len + MBX_HDR_SIZE_C - 1;
      lidx := to_integer( unsigned ( ESC_SM1_LEN_C ) ) - 1;
      assert ( ldat <= lidx ) report "test data too long" severity failure;
      if ( ldat < lidx ) then
         lidx := ldat + 4;
      end if;
      ldat := ldat/2;
      lidx := lidx/2;

      idx  := 0;
      timo := 200;

      while ( timo > 0 ) loop
         
         while ( req.valid = '0' and timo > 0 ) loop
            wait until rising_edge(clk);
            if ( idx >= lidx ) then
               timo := timo - 1;
            end if;
         end loop;
         rep.valid <= '1';
         rep.berr  <= (others => '0');

         tmp := idx;
         if ( idx = ldat + 1 ) then
            tmp := 0;
         elsif ( idx = ldat + 2 ) then
            tmp := (to_integer(unsigned(ESC_SM1_LEN_C)) - 1)/2;
         end if;

         expad := to_unsigned( 2*tmp, expad'length ) + unsigned(ESC_SM1_SMA_C);
         assert expad(0) = '0' report "misaligned write address" severity failure;
         expbe := HBI_BE_W0_C;
         lst1b := ( idx = (MBX_HDR_SIZE_C + tst.len - 1)/2 ) and (tst.len mod 2 /= 0) and not rpt;
         if ( expad(1) = '1' ) then
            expad(1) := '0';
            if ( lst1b ) then
               expbe := HBI_BE_B2_C;
            else
               expbe := HBI_BE_W1_C;
            end if;
         else
            if ( lst1b ) then
               expbe := HBI_BE_B0_C;
            else
               expbe := HBI_BE_W0_C;
            end if;
         end if;
         if ( req.rdnwr = '1' ) then
            if (   req.addr = x"0220" ) then
               rep.rdata <= x"0000_0000";
            else
               assert false report "READ from unexpected address " & toString(req.addr) severity failure;
            end if;
         else
            if (   req.addr = x"0204" 
                or req.addr = x"305C"
                or req.addr = x"3054"
                or req.addr = x"0130"
                or req.addr = x"0134"
                or ( ( req.addr = x"080c" ) and rpt )
               ) then
               -- skip write
            elsif ( expad = req.addr ) then
               assert idx <= lidx    report "UNEXPECTED EXTRA TRANSFER" severity failure;
               assert req.be = expbe report "BYTE_ENABLE mismatch, addr " & toString(req.addr) & " got " & toString(req.be) & " exp " & toString(expbe) severity failure;
               if ( idx <= ldat ) then
                  if    ( idx = 0 ) then
                     if ( rpt ) then
                        expdt := to_unsigned(tst.len, expdt'length);
                     else
                        expdt := unsigned(ESC_SM1_LEN_C) - MBX_HDR_SIZE_C;
                     end if;
                  elsif ( idx = 1 ) then
                     expdt := (others => '0');
                  elsif ( idx = 2 ) then
                     expdt := (others => '0');
                     expdt(MBX_TYP_RNG_T) := unsigned(tst.typ);
                     expdt(MBX_CNT_RNG_T) := tst.cnt;
                  else
                     expdt := tst.prefix + idx - MBX_HDR_SIZE_C/2 + 1;
                  end if;
               elsif ( idx = ldat + 1 ) then
                  expdt := to_unsigned(tst.len, expdt'length);
               elsif ( idx = ldat + 2 ) then
                  if ( req.be(0) = HBI_BE_ACT_C ) then
                     expdt := unsigned(req.data(15 downto  0));
                  else
                     expdt := unsigned(req.data(31 downto 16));
                  end if;
               end if;
               
               if ( req.be(0) = HBI_BE_ACT_C ) then
                  assert( req.data(7 downto 0) = std_logic_vector(expdt(7 downto 0)) ) report "WDATA MISMATCH @ " & toString(req.addr) & "got xx" & toString(req.data(7 downto 0)) & " exp xx" & toString(expdt(7 downto 0)) severity failure;
               elsif( req.be(2) = HBI_BE_ACT_C ) then
                  assert( req.data(23 downto 16) = std_logic_vector(expdt(7 downto 0)) ) report "WDATA MISMATCH @ " & toString(req.addr) & "got xx" & toString(req.data(23 downto 16)) & " exp xx" & toString(expdt(7 downto 0)) severity failure;
               else
                  assert false report "No B0 lane active" severity failure;
               end if;
               if ( req.be(1) = HBI_BE_ACT_C ) then
                  assert( req.data(15 downto 8) = std_logic_vector(expdt(15 downto 8)) ) report "WDATA MISMATCH @ " & toString(req.addr) & "got " & toString(req.data(15 downto 8)) & "xx exp " & toString(expdt(15 downto 8)) & "xx" severity failure;
               elsif( req.be(3) = HBI_BE_ACT_C ) then
                  assert( req.data(31 downto 24) = std_logic_vector(expdt(15 downto 8)) ) report "WDATA MISMATCH @ " & toString(req.addr) & "got " & toString(req.data(31 downto 24)) & "xx exp " & toString(expdt(15 downto 8)) & "xx" severity failure;
               end if;
               idx := idx + 1;
               if ( idx = ldat + 1 and rpt ) then
                  idx := idx + 1;
               end if;
report "passed EXPAD " & toString(expad) & " BE " & toString(expbe) & " DAT " & toString(expdt);
            else
               assert false report "WRITE to unexpected address " & toString(req.addr) & " (expected " & toString(expad) & ")" severity failure;
            end if;
         end if;
         wait until rising_edge(clk);
         rep.valid <= '0';
         wait until rising_edge(clk);
      end loop;
       
   end procedure check;

   constant testVec : TestVecArray := (
      0 => (
         len    => 4,
         prefix => x"AA00",
         cnt    => "001",
         typ    => x"0"
      ),
      1 => (
         len    => 1,
         prefix => x"BB00",
         cnt    => "010",
         typ    => x"3"
      ),
      2 => (
         len    => to_integer(unsigned(ESC_SM1_LEN_C)) - MBX_HDR_SIZE_C - 1,
         prefix => x"CC00",
         cnt    => "011",
         typ    => x"2"
      ),
      3 => (
         len    => to_integer(unsigned(ESC_SM1_LEN_C)) - MBX_HDR_SIZE_C,
         prefix => x"DD00",
         cnt    => "100",
         typ    => x"1"
      ),
      4 => (
         len    => 2,
         prefix => x"EE00",
         cnt    => "101",
         typ    => x"8"
      )
   );

   signal clk                : std_logic          := '0';
   signal rst                : std_logic          := '0';

   signal req                : LAN9254ReqType     := LAN9254REQ_INIT_C;
   signal rep                : LAN9254RepType     := LAN9254REP_INIT_C;

   signal run                : boolean            := true;

   signal txMBXMst           : Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
   signal txMBXRdy           : std_logic;

   signal passed             : natural            := testVec'low;

   signal rptToggle          : std_logic          := '1';

 
begin

   rep.berr  <= (others => '0');

   P_CLK : process is
   begin
      if ( run ) then
         clk <= not clk;
         wait for 5 us;
      else
         wait;
      end if;
   end process P_CLK;

   P_CHECK : process is
   begin
report "entering P_CHECK";
      for i in 1 to 10 loop
         wait until rising_edge(clk);
      end loop;
      escSetState( clk, req, rep, rptToggle, PREOP );
      for  i in testVec'range loop
        check( clk, testVec(i), req, rep );
        if ( i = 4 ) then
           mbxRep( clk, req, rep, rptToggle );
           check( clk, testVec(3), req, rep, rpt => true );
           mbxAck( clk, req, rep, txMbxRdy );
           check( clk, testVec(4), req, rep, rpt => true );
           mbxAck( clk, req, rep, txMbxRdy );
        else 
           mbxAck( clk, req, rep, txMbxRdy );
           if ( i = 1 ) then
              mbxRep( clk, req, rep, rptToggle );
              check( clk, testVec(i), req, rep, rpt => true );
              mbxAck( clk, req, rep, txMbxRdy );
           end if;
        end if;
        passed <= passed + 1;
      end loop;
      wait;
   end process P_CHECK;

   P_DRV : process is
   begin
      for t in testVec'range loop
         feed( clk, testVec(t), txMBXMst, txMBXRdy );
         while ( t >= passed ) loop
            wait until rising_edge( clk );
         end loop;
      end loop;

      for i in 1 to 20 loop
         wait until rising_edge( clk );
      end loop;

      run <= false;
      wait;
   end process P_DRV;

   U_DUT : entity work.Lan9254ESC
      generic map (
         CLK_FREQ_G           => 0.0,
         TXMBX_TEST_G         => true,
         REG_IO_TEST_ENABLE_G => false
      )
      port map (
         clk          => clk,
         rst          => rst,

         req          => req,
         rep          => rep,

         txMBXMst     => txMBXMst,
         txMBXRdy     => txMBXRdy
      );

end architecture rtl;
