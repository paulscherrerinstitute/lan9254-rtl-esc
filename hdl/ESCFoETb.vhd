library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.ESCBasicTypesPkg.all;
use work.Lan9254Pkg.all;
use work.Lan9254ESCPkg.all;
use work.ESCMbxPkg.all;

entity ESCFoETb is
end entity ESCFoETb;

architecture rtl of ESCFoETb is

   constant N_MBX_C          : natural            := 2;

   constant MBX_SIZE_C       : natural            := 8;

   constant PG_SIZE_G        : natural            := 4;

   constant MEM_SIZE_C       : natural            := 12;

   type   DataArray         is array(natural range <>) of std_logic_vector(7 downto 0);

   constant EMPTY_C          : DataArray(0 downto 1) := (others => (others => '0'));

   constant DEPTH_C          : natural            := (PG_SIZE_G);

   signal clk                : std_logic          := '0';
   signal rst                : std_logic          := '1';

   signal run                : boolean            := true;

   signal txMbxMst           : Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
   signal txMbxRdy           : std_logic;

   signal rxMbxMst           : Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
   signal rxMbxRdy           : std_logic          := '0';

   signal foeMst             : Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
   signal foeRdy             : std_logic          := '1';

   signal mbxErr             : MbxErrorType;
   signal mbxErrRdy          : std_logic          := '1';

   signal foeBusy            : std_logic          := '0';
   signal foeErr             : std_logic;
   signal foeAbort           : std_logic          := '0';
   signal foeDone            : std_logic          := '0';
   signal foeDoneAck         : std_logic;

   signal emptySlots         : unsigned(numBits(DEPTH_C) - 1 downto 0);
   signal fullSlots          : unsigned(numBits(DEPTH_C) - 1 downto 0);
 
   signal mbxMuxMstIb        : Lan9254StrmMstArray(N_MBX_C - 1 downto 0);
   signal mbxMuxRdyIb        : std_logic_vector   (N_Mbx_C - 1 downto 0);

   signal foeFileIdx         : natural; 

   signal numOps             : natural            := 0;

   signal fifoRst            : std_logic;

   signal foeData            : std_logic_vector(7 downto 0);

   signal rcvData            : DataArray( 0 to 256 );

   signal tstData            : DataArray( 0 to MEM_SIZE_C ) := (
      x"AA",
      x"BB",
      x"CC",
      x"DD",
      x"EE",
      x"FF",
      others => x"00"
   );

   signal tstData1          : DataArray( 0 to MEM_SIZE_C - 1 ) := (
      others => (others => 'X')
   );

   type RdrStateType is (IDLE, ERASE, WAIT_DATA, RDEN, READ, RDELAY, DONE);

   type RegType is record
      state    :  RdrStateType;
      count    :  natural;
      pgCount  :  natural;
      lastSeen :  boolean;
      rdEn     :  std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state    => IDLE,
      count    => 0,
      pgCount  => 0,
      lastSeen => false,
      rdEn     => '0'
   );

   signal foeReg : RegType := REG_INIT_C;

   procedure waitResp(
      signal   r   : inout std_logic;
      variable typ : out   std_logic_vector( 3 downto 0);
      variable opc : out   std_logic_vector( 7 downto 0);
      variable val : out   std_logic_vector(31 downto 0)
   ) is
      variable cnt : natural;
   begin
      r   <= '1';
      cnt := 0;
      typ := (others => 'X');
      opc := (others => 'X');
      val := (others => 'X');
      report "Mbx RESPONSE";
      L_PROC : while true loop
         wait until rising_edge( clk );
         while ( (r and rxMbxMst.valid) = '0' ) loop
            wait until rising_edge( clk );
         end loop;
         if    ( cnt = 0 ) then
            typ := rxMbxMst.usr;    
            opc := rxMbxMst.data(7 downto 0);
         elsif ( cnt = 1 ) then
            val(15 downto  0) := rxMbxMst.data;
         elsif ( cnt = 2 ) then
            val(31 downto 16) := rxMbxMst.data;
         end if;
         cnt := cnt + 1;
         report "  DATA 0x" & toString( rxMbxMst.data ) & " -- USR 0x" & toString( rxMbxMst.usr );
         if ( rxMbxMst.last = '1' ) then
            r <= '0';
            wait until rising_edge( clk );
            exit L_PROC;
         end if;
      end loop L_PROC;
   end procedure waitResp;

   procedure sendFrame(
      signal   m        : inout Lan9254StrmMstType;
      constant d        : in    DataArray                     := EMPTY_C;
      constant v        : in    std_logic_vector(31 downto 0) := (others => '0');
      constant op       : in    std_logic_vector( 7 downto 0) := FOE_OP_DATA_C;
      constant trunc    : in    integer                       := -1
   ) is
      variable inc : natural;
      variable snt : natural;
      variable lim : natural;
   begin
      snt := 0;
      inc := 2;
      if ( trunc >= 0 ) then
         lim := trunc;
      else
         lim := 6 + d'length;
      end if;
      m.valid <= '1';
      m.last  <= '0';
      m.ben   <= "11";
      while ( snt < lim ) loop
         if ( lim - snt <= 2 ) then
            if ( lim - snt < 2 ) then
               m.ben <= "01";
               inc          := 1;
            end if;
            m.last <= '1';
         end if;
         case ( snt ) is
            when 0 =>
               m.data <= x"00" & op;
            when 2 =>
               m.data <= v(15 downto  0);
            when 4 =>
               m.data <= v(31 downto 16);
            when others =>
               m.data <= (others => 'X');
               if ( snt + 1 - 6 <= d'length ) then
                 m.data( 7 downto  0) <= d(snt + 0 - 6 + d'left);
               end if;
               if ( snt + 2 - 6 <= d'length ) then
                 m.data(15 downto  8) <= d(snt + 1 - 6 + d'left);
               end if;
         end case;
         wait until rising_edge( clk );
         while ( ( m.valid and txMbxRdy ) = '0' ) loop
            wait until rising_edge( clk );
         end loop;
         snt := snt + inc;
      end loop;
      m.valid <= '0';
      wait until rising_edge( clk );
   end procedure sendFrame;

   procedure xFrame(
      signal   mIb      : inout Lan9254StrmMstType;
      signal   rOb      : inout std_logic;
      constant d        : in    DataArray                     := EMPTY_C;
      constant v        : in    std_logic_vector(31 downto 0) := (others => '0');
      constant expOp    : in    std_logic_vector( 7 downto 0) := FOE_OP_ACK_C;
      constant expVal   : in    std_logic_vector(31 downto 0) := (others => 'X');
      constant op       : in    std_logic_vector( 7 downto 0) := FOE_OP_DATA_C;
      constant trunc    : in    integer                       := -1
   ) is
      variable typ  : std_logic_vector( 3 downto 0);
      variable opc  : std_logic_vector( 7 downto 0);
      variable val  : std_logic_vector(31 downto 0);
   begin
      opc := FOE_OP_BUSY_C;
      while ( opc = FOE_OP_BUSY_C ) loop
         sendFrame(mIb, d, v, op, trunc);
         waitResp(rOb, typ, opc, val);
         if ( trunc < 6 and trunc >= 0 ) then
            assert typ = MBX_TYP_ERR_C               severity failure;
            assert opc = MBX_ERR_CODE_SIZETOOSHORT_C severity failure;
         else
            assert typ = MBX_TYP_FOE_C               severity failure;
         end if;
      end loop;
      assert opc = expOp severity failure;
      if ( expVal(0) /= 'X' ) then
         assert val = expVal  severity failure;
      else
         assert val = v       severity failure;
      end if;
   end procedure xFrame;

   procedure sendData(
      signal   mIb      : inout Lan9254StrmMstType;
      signal   rOb      : inout std_logic;
      constant d        : in    DataArray                    := EMPTY_C;
      constant trunc    : in    integer                      := -1
   ) is
      variable pkt   : unsigned(31 downto 0);
      variable snt   : natural;
      variable len   : natural;
      variable spc   : boolean;
      variable expOp : std_logic_vector( 7 downto 0);
      variable expVl : std_logic_vector(31 downto 0);
      constant SZ_C : natural := MBX_SIZE_C - 6;
   begin
report integer'image(d'low)& " -> " & integer'image(d'high);
      snt := 0;
      pkt := to_unsigned( 1, pkt'length );
      spc := false;
      while ( snt < d'length ) loop
         len := d'length - snt;
         -- send 'special' empty message if last fragment is full
         spc := (len = SZ_C) and ( trunc < 0 );
         if (len > SZ_C) then
            len := SZ_C;
         end if;
         expOp := FOE_OP_ACK_C;
         expVl := std_logic_vector(pkt);
         if ( snt + len > MEM_SIZE_C ) then
            expOp := FOE_OP_ERR_C;
            expVl := x"0000" & FOE_ERR_CODE_DISKFULL_C;
         end if;
         xFrame( mIb, rOb, d(snt to snt + len - 1), v => std_logic_vector(pkt), trunc => trunc, expOp => expOp, expVal => expVl );
         pkt := pkt + 1;
         snt := snt + len;
      end loop;
      if ( spc ) then
         xFrame( mIb, rOb, v => std_logic_vector(pkt) );
      end if;
   end procedure sendData;

begin

   P_CLK : process is
   begin
      if ( run ) then
         clk <= not clk;
         wait for 5 us;
      else
         wait;
      end if;
   end process P_CLK;

   P_INI : process is
   begin
      for i in tstData1'range loop
         tstData1(i) <= "10" & std_logic_vector( to_unsigned( i, 6 ) );
      end loop;
      wait;
   end process P_INI;

   P_DRV : process is
   begin
      wait until rising_edge( clk );
      wait until rising_edge( clk );
      rst <= '0';
      wait until rising_edge( clk );
      xFrame( txMbxMst, rxMbxRdy, ( 0 => x"00"), op => FOE_OP_WRQ_C,
              expOp  => FOE_OP_ERR_C,
              expVal => (x"0000" & FOE_ERR_CODE_NOTFOUND_C)
      );

      xFrame( txMbxMst, rxMbxRdy, ( 0 => x"41"), op => FOE_OP_WRQ_C);
      sendData( txMbxMst, rxMbxRdy, tstData(0 to 3 ) );

      xFrame( txMbxMst, rxMbxRdy, op => FOE_OP_DATA_C,
              expOp  => FOE_OP_ERR_C,
              expVal => (x"0000" & FOE_ERR_CODE_ILLEGAL_C)
      );

      xFrame( txMbxMst, rxMbxRdy, ( 0 => x"41"), op => FOE_OP_WRQ_C);
      sendData( txMbxMst, rxMbxRdy, tstData(0 to 2) );

      xFrame( txMbxMst, rxMbxRdy, ( 0 => x"41"), op => FOE_OP_WRQ_C);
      sendData( txMbxMst, rxMbxRdy, tstData );

      xFrame( txMbxMst, rxMbxRdy, ( 0 => x"41"), op => FOE_OP_WRQ_C);
      sendData( txMbxMst, rxMbxRdy, tstData1 );

      while ( numOps < 6 ) loop
         wait until rising_edge( clk );
      end loop;
      run <= false;
      report "Test PASSED";
      wait;
   end process P_DRV;

   U_DUT : entity work.ESCFoE
      generic map (
         FILE_MAP_G => ( 0 => x"41" )
      )
      port map (
         clk               => clk,
         rst               => rst,

         mbxMstIb          => txMbxMst,
         mbxRdyIb          => txMbxRdy,

         mbxMstOb          => mbxMuxMstIb(0),
         mbxRdyOb          => mbxMuxRdyIb(0),

         mbxErrMst         => mbxErr,
         mbxErrRdy         => mbxErrRdy,

         -- mailbox size without mailbox header (but including FOE header)
         mbxSize           => to_unsigned(MBX_SIZE_C, 16),

         foeMst            => foeMst,
         foeRdy            => foeRdy,
         foeBusy           => foeBusy,
         -- we detected an error
         foeErr            => foeErr,
         -- downstream error
         foeAbort          => foeAbort,
         foeDone           => foeDone,
         foeDoneAck        => foeDoneAck,
         foeFile0WrEn      => '1',
         foeFileIdx        => foeFileIdx,
         debug             => open

      );

   U_ERR : entity work.ESCTxMbxErr
      port map (
         clk               => clk,
         rst               => rst,

         errIb(0)          => mbxErr,
         rdyIb(0)          => mbxErrRdy,

         mbxOb             => mbxMuxMstIb(1),
         rdyOb             => mbxMuxRdyIb(1)
      );

   U_MUX : entity work.ESCTxMbxMux
      generic map (
         NUM_STREAMS_G     => N_Mbx_C
      )
      port map (
         clk               => clk,
         rst               => rst,
         mbxIb             => mbxMuxMstIb,
         rdyIb             => mbxMuxRdyIb,

         mbxOb             => rxMbxMst,
         rdyOb             => rxMbxRdy
      );

   U_FIFO : entity work.StrmFifoSync
      generic map (
         -- depth in bytes
         DEPTH_G  => DEPTH_C
      )
      port map (
         clk               => clk,
         rst               => fifoRst,

         strmMstIb         => foeMst,
         strmRdyIb         => foeRdy,

         emptySlots        => emptySlots,
         fullSlots         => fullSlots,

         -- data available on cycle after rdEn is asserted
         dataOut           => foeData,
         rdEn              => foeReg.rdEn
      );

   P_BUSY : process ( emptySlots ) is
   begin
      if ( emptySlots < MBX_SIZE_C - 6 ) then
         foeBusy <= '1';
      else
         foeBusy <= '0';
      end if;
   end process P_BUSY;

   P_FIFORST : process ( rst, foeReg ) is
   begin
      fifoRst <= rst;
      foeDone <= '0';
      if ( foeReg.state = DONE ) then
         foeDone <= '1';
         fifoRst <= '1';
      end if;
   end process P_FIFORST;

   P_FOE  : process ( clk ) is
      variable v       : std_logic_vector(15 downto 0);
      variable busyCnt : natural;
      variable rcvCnt  : natural := 0;
      variable tmp8    : std_logic_vector( 7 downto 0);
   begin
      if ( rising_edge( clk ) ) then
         if ( ( foeMst.last and foeMst.valid and foeRdy ) = '1' ) then
            foeReg.lastSeen <= true;
         end if;

         case ( foeReg.state ) is
            when IDLE =>
               if ( foeErr = '1' ) then
                  foeReg.state <= DONE;
               elsif ( fullSlots > 0 ) then
                  foeReg.count    <= 0;
                  foeReg.pgCount  <= 0;
                  foeReg.state    <= ERASE;
                  foeReg.lastSeen <= false;
               end if;

            when ERASE =>
               if ( foeReg.count < 500 ) then
                  foeReg.count <= foeReg.count + 1;
               else
                  foeReg.count <= 0;
                  foeReg.state <= WAIT_DATA;
               end if;

            when WAIT_DATA =>
               if ( foeErr = '1' ) then
                  foeReg.state <= DONE;
               elsif ( ( fullSlots >= PG_SIZE_G ) or foeReg.lastSeen ) then
                  if ( fullSlots = 0 ) then
                     foeReg.state <= DONE;
                  else
                     foeReg.rdEn  <= '1';
                     foeReg.state <= RDEN;
                     if ( fullSlots >= PG_SIZE_G ) then
                        foeReg.pgCount <= PG_SIZE_G - 1;
                     else
                        foeReg.pgCount <= to_integer( fullSlots - 1 );
                     end if;
                  end if;
               end if;

            when RDEN =>
               if ( foeReg.pgCount = 0 ) then
                  foeReg.rdEn <= '0';
               end if;
               foeReg.state <= READ;

            when READ =>
               if ( foeErr = '1' ) then
                  foeReg.state <= DONE;
               elsif ( foeReg.count >= MEM_SIZE_C ) then
                  foeAbort     <= '1';
                  foeReg.state <= DONE;
               else
                  report "FOE READ 0x" & toString( foeData );
                  rcvData(foeReg.count) <= foeData;
                  foeReg.count          <= foeReg.count   + 1;
                  if ( foeReg.pgCount = 0 ) then
                     foeReg.state   <= RDELAY;
                     foeReg.pgCount <= 100;
                  else
                     if ( foeReg.pgCount = 1 ) then
                        foeReg.rdEn    <= '0';
                     end if;
                     foeReg.pgCount <= foeReg.pgCount - 1;
                  end if;
               end if;

            when RDELAY =>
               if ( foeReg.pgCount = 0 ) then
                  foeReg.state <= WAIT_DATA;
               else
                  foeReg.pgCount <= foeReg.pgCount - 1;
               end if;

            when DONE =>
               if ( foeDoneAck = '1' ) then
                  if ( foeErr = '0' ) then
                     for i in 0 to foeReg.count - 1 loop
                        if ( numOps /= 5 ) then
                           tmp8 := tstData(i);
                        else
                           tmp8 := tstData1(i);
                        end if;
                        assert ( rcvData(i) = tmp8 )
                           report "numOps: " & integer'image(numOps) & ", count: " & integer'image(foeReg.count) & ", ERR: " & std_logic'image(foeErr)
                           severity failure;
                     end loop;
                  end if;
                  rcvData      <= (others => (others => 'X'));
                  foeAbort     <= '0';
                  foeReg.state <= IDLE;
                  foeReg.rdEn  <= '0';
                  numOps       <= numOps + 1;
               end if;
          
         end case;

         if ( rst = '1' ) then
            foeReg <= REG_INIT_C;
         end if;
      end if;
   end process P_FOE;

   P_FIDX : process ( foeMst, foeFileIdx ) is
   begin
      if ( foeMst.valid = '1' ) then
         assert foeFileIdx = 0 severity failure;
      end if;
   end process P_FIDX;

end architecture rtl;