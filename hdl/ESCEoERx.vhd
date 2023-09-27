------------------------------------------------------------------------------
--      Copyright (c) 2022-2023 by Paul Scherrer Institute, Switzerland
--      All rights reserved.
--  Authors: Till Straumann
--  License: PSI HDL Library License, Version 2.0 (see License.txt)
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.ESCBasicTypesPkg.all;
use work.Lan9254Pkg.all;
use work.Lan9254ESCPkg.all;
use work.ESCMbxPkg.all;
use work.IPAddrConfigPkg.all;

entity ESCEoERx is
   generic (
      CLOCK_FREQ_G      : real;
      RX_TIMEOUT_G      : real := 0.1;
      STORE_AND_FWD_G   : boolean
   );
   port (
      clk               : in  std_logic;
      rst               : in  std_logic;

      mbxMstIb          : in  Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      mbxRdyIb          : out std_logic;

      mbxMstOb          : out Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      mbxRdyOb          : in  std_logic          := '1';

      eoeMstOb          : out Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      eoeErrOb          : out std_logic;
      eoeRdyOb          : in  std_logic := '1';
      eoeFrameSz        : out unsigned(10 downto 0);

      debug             : out std_logic_vector(15 downto 0);

      addrCfg           : out IPAddrConfigReqType;
      addrCfgAck        : in  IPAddrConfigAckType := IP_ADDR_CONFIG_ACK_ASSERT_C;

      stats             : out StatCounterArray(2 downto 0)
   );
end entity ESCEoERx;

architecture rtl of ESCEoERx is

   constant FRAME_TIMEOUT_C : natural := natural( RX_TIMEOUT_G * CLOCK_FREQ_G ) + 1; -- avoid zero

   subtype FrameTimeoutType is natural range 0 to FRAME_TIMEOUT_C;

   type StateType is (IDLE, HDR, FWD, GET_PARAMS, GET_MAC, GET_IP, RESP, DROP);

   subtype DelayArray is Slv16Array(1 downto 0);


   type RegType is record
      state                   : StateType;
      frameType               : std_logic_vector(3 downto 0);
      framePort               : std_logic_vector(3 downto 0);
      lastFrag                : std_logic;
      timeAppend              : std_logic;
      timeRequest             : std_logic;
      delayedData             : DelayArray;
      delayedValid            : std_logic_vector(1 downto 0);
      fragNo                  : unsigned(5 downto 0);
      frameOff                : unsigned(5 downto 0);
      frameNo                 : unsigned(3 downto 0);
      wordCount               : natural range 0 to 2;
      hasMac                  : boolean;
      macAddr                 : Slv16Array(2 downto 0);
      macAddrVld              : std_logic;
      macAddrTmp              : Slv16Array(1 downto 0);
      hasIp                   : boolean;
      ip4Addr                 : Slv16Array(1 downto 0);
      ip4AddrTmp              : Slv16Array(0 downto 0);
      ip4AddrVld              : std_logic;
      rspMst                  : Lan9254StrmMstType;
      rspStatus               : std_logic_vector(15 downto 0);
      eoeErr                  : std_logic;
      drained                 : std_logic;
      frameTimeout            : FrameTimeoutType;
      numFrags                : StatCounterType;
      numFrams                : StatCounterType;
      numDrops                : StatCounterType;
   end record RegType;

   constant REG_INIT_C        : RegType := (
      state                   => IDLE,
      frameType               => (others => '0'),
      framePort               => (others => '0'),
      lastFrag                => '0',
      timeAppend              => '0',
      timeRequest             => '0',
      delayedData             => (others => (others => '0')),
      delayedValid            => (others => '0'),
      fragNo                  => (others => '0'),
      frameOff                => (others => '0'),
      frameNo                 => (others => '0'),
      wordCount               => 0,
      hasMac                  => false,
      macAddr                 => (others => (others => '0')),
      macAddrVld              => '0',
      macAddrTmp              => (others => (others => '0')),
      hasIp                   => false,
      ip4Addr                 => (others => (others => '0')),
      ip4AddrVld              => '0',
      ip4AddrTmp              => (others => (others => '0')),
      rspMst                  => LAN9254STRM_MST_INIT_C,
      rspStatus               => (others => '0'),
      eoeErr                  => '0',
      drained                 => '1',
      frameTimeout            => 0,
      numFrags                => STAT_COUNTER_INIT_C,
      numFrams                => STAT_COUNTER_INIT_C,
      numDrops                => STAT_COUNTER_INIT_C
   );

   signal r                   : RegType := REG_INIT_C;
   signal rin                 : RegType;

   signal eoeMst              : Lan9254StrmMstType;
   signal eoeRdyLoc           : std_logic;

begin

   debug( 5 downto  0) <= std_logic_vector( r.fragNo  );
   debug(11 downto  6) <= std_logic_vector( r.frameOff );

   debug(14 downto 12) <= std_logic_vector( to_unsigned( StateType'pos( r.state ), 3 ) );
--   debug(15          ) <= r.timeAppend;
   debug(15          ) <= r.eoeErr;

   P_COMB : process ( r, mbxMstIb, eoeRdyLoc, mbxRdyOb, addrCfgAck ) is
      variable v   : RegType;
      variable m   : Lan9254StrmMstType;
      variable rdy : std_logic;
   begin
      v       := r;
      m       := LAN9254STRM_MST_INIT_C;
      m.data  := mbxMstIb.data;
      m.ben   := mbxMstIb.ben;
      m.last  := mbxMstIb.last;
      m.usr(MBX_TYP_EOE_C'range) := MBX_TYP_EOE_C;
      m.valid := '0';
      rdy     := '1';

      if ( r.frameTimeout /= 0 ) then
         v.frameTimeout := r.frameTimeout - 1;
      end if;

      if ( addrCfgAck.macAddrAck = '1' ) then
         v.macAddrVld := '0';
      end if;

      if ( addrCfgAck.ip4AddrAck = '1' ) then
         v.ip4AddrVld := '0';
      end if;

      C_STATE : case ( r.state ) is

         when IDLE =>
            v.drained   := '1';
            v.wordCount := 0;
            if ( ( mbxMstIb.valid and rdy ) = '1' ) then
               if ( mbxMstIb.last = '1' ) then
                  -- too short; drop
                  v.state          := IDLE;
               else
                  v.frameType      := mbxMstIb.data( 3 downto  0);
                  v.framePort      := mbxMstIb.data( 7 downto  4);
                  v.lastFrag       := mbxMstIb.data( 8          );
                  v.timeAppend     := mbxMstIb.data( 9          );
                  v.timeRequest    := mbxMstIb.data(10          );
                  if (    ( EOE_TYPE_FRAG_C            = v.frameType )
                       or ( EOE_TYPE_SET_IP_PARM_REQ_C = v.frameType ) ) then
                     v.state       := HDR;
report "FRAME TYPE " & toString(v.frameType);
                  else
-- FIXME: handle sending response!
report "UNSUPPORTED EeE FRAME TYPE " & toString(v.frameType);
                     v.state       := RESP;
                     v.rspStatus   := EOE_ERR_CODE_UNSUP_FRAME_TYPE_C;
                     v.drained     := '0';
                  end if;
               end if;
               v.delayedValid := (others => '0');
            end if;

         when HDR =>
            if ( ( mbxMstIb.valid and rdy ) = '1' ) then
               if ( mbxMstIb.last = '1' ) then
                  -- too short; drop
                  if ( EOE_TYPE_SET_IP_PARM_REQ_C = r.frameType ) then
                     v.rspStatus := EOE_ERR_CODE_UNSPEC_ERROR_C;
                     v.state     := RESP;
                  else 
                     v.state          := IDLE;
                  end if;
               else
                  v.fragNo         := unsigned(mbxMstIb.data( 5 downto  0));
                  v.frameOff       := unsigned(mbxMstIb.data(11 downto  6));
                  v.frameNo        := unsigned(mbxMstIb.data(15 downto 12));
                  if ( EOE_TYPE_FRAG_C = v.frameType ) then
                     v.state          := FWD;
                     v.frameTimeout   := FRAME_TIMEOUT_C;
                  else
                     v.state          := GET_PARAMS;
report "SET_IP_PARAMS";
                  end if;
                  if ( v.fragNo /= r.fragNo ) then
report "Unexpected fragment # " & integer'image(to_integer(v.fragNo)) & " exp " & integer'image(to_integer(r.fragNo));
                     v.state   := DROP;
                     v.drained := '0';
                     v.eoeErr  := '1';
                  end if;
                  if ( ( v.fragNo /= 0 ) and ( v.frameNo /= r.frameNo ) ) then
report "Unexpected frame # " & integer'image(to_integer(v.frameNo)) & " exp " & integer'image(to_integer(r.frameNo));
                     v.state   := DROP;
                     v.drained := '0';
                     v.eoeErr  := '1';
                  end if;
               end if;
            end if;
 
         when FWD =>
            rdy     := eoeRdyLoc;
            m.last  := r.lastFrag and mbxMstIb.last;
            if ( r.timeAppend = '0' or r.lastFrag = '0' ) then
               m.valid := mbxMstIb.valid;
            else
               -- delay output data by two words in order to strip the time-stamp
               -- note that we can use the un-delayed 'ben' directly (assuming
               -- only the last 'ben' is relevant)
               m.valid := r.delayedValid(1);
               m.data  := r.delayedData (1);
               if ( ( mbxMstIb.valid and eoeRdyLoc ) = '1' ) then
                  v.delayedValid := r.delayedValid(r.delayedValid'left - 1 downto 0) & mbxMstIb.valid;
                  v.delayedData  := r.delayedData (r.delayedData'left  - 1 downto 0) & mbxMstIb.data;
               end if;
            end if;
            if ( ( mbxMstIb.valid and eoeRdyLoc and mbxMstIb.last ) = '1' ) then
               v.numFrags := r.numFrags + 1;
               v.state    := IDLE;
               if ( r.lastFrag = '1' ) then
                  v.numFrams := r.numFrams + 1;
                  v.fragNo   := to_unsigned(0, v.fragNo'length);
                  v.frameNo  := r.frameNo + 1;
               else
                  v.fragNo   := r.fragNo + 1;
               end if;
            elsif ( r.frameTimeout = 0 ) then
               v.eoeErr := '1';
               v.state  := DROP;
            end if;

         when GET_PARAMS =>
            if ( ( mbxMstIb.valid and rdy ) = '1' ) then
               if ( mbxMstIb.last = '1' ) then
                  -- too short; drop
                  v.state     := RESP;
                  v.rspStatus := EOE_ERR_CODE_UNSPEC_ERROR_C;
               else
                  if ( 0 = r.wordCount ) then
                     v.hasMac    := ( mbxMstIb.data(0) = '1' );
                     v.hasIp     := ( mbxMstIb.data(1) = '1' );
                     v.wordCount := 1;
                  else
                     v.wordCount := 0;
                     v.state     := GET_MAC;
                  end if;
               end if;
            end if;

         when GET_MAC =>
            if ( ( mbxMstIb.valid and rdy ) = '1' ) then

               if ( mbxMstIb.last = '1' ) then
                  v.state     := RESP;
                  -- reset if this is the last word
                  v.rspStatus := EOE_ERR_CODE_UNSPEC_ERROR_C;
               end if;

               if ( 2 = r.wordCount ) then
                  if ( r.hasMac ) then
                     v.macAddr(1 downto 0) := r.macAddrTmp(1 downto 0);
                     v.macAddr(         2) := mbxMstIb.data;
                     v.macAddrVld          := '1';
report "SET IP PARAMS -- NEW MAC";
                  end if;
                  v.wordCount    := 0;
                  v.state        := GET_IP;
               else
                  v.macAddrTmp( r.wordCount ) := mbxMstIb.data;
                  v.wordCount                 := r.wordCount + 1;
               end if;
                  
            end if;

         when GET_IP =>
            if ( ( mbxMstIb.valid and rdy ) = '1' ) then

               if ( mbxMstIb.last = '1' ) then
                  v.state     := RESP;
                  -- reset if this is the last word
                  v.rspStatus := EOE_ERR_CODE_UNSPEC_ERROR_C;
               end if;

               if ( 1 = r.wordCount ) then
                  v.rspStatus  := EOE_ERR_CODE_SUCCESS_C;
                  if ( r.hasIp ) then
report "SET IP PARAMS -- NEW IP: "
       & integer'image(to_integer(unsigned(mbxMstIb.data (15 downto  8))))  & "."
       & integer'image(to_integer(unsigned(mbxMstIb.data ( 7 downto  0))))  & "."
       & integer'image(to_integer(unsigned(r.ip4AddrTmp(0)(15 downto  8)))) & "."
       & integer'image(to_integer(unsigned(r.ip4AddrTmp(0)( 7 downto  0)))) ;
                     if ( ( r.ip4AddrTmp(0) /= x"0000" ) or ( mbxMstIb.data /= x"0000" ) ) then
                        -- while EOE provides the MAC address in 'network' order
                        -- it uses little-endian for the IPV4 address. Internally we
                        -- use network-byte order so we swap here
                        v.ip4Addr(1) := bswap( r.ip4AddrTmp(0) );
                        v.ip4Addr(0) := bswap( mbxMstIb.data   );
                        v.ip4AddrVld := '1';
                     else
                        v.rspStatus  := EOE_ERR_CODE_UNSUP_DHCP_C;
                     end if;
                  end if;
                  v.wordCount     := 0;
                  v.state         := RESP;
                  v.drained       := mbxMstIb.last;
               else
                  v.ip4AddrTmp(0) := mbxMstIb.data;
                  v.wordCount    := 1;
               end if;

            end if;

         when RESP =>
            if ( '0' = r.rspMst.valid ) then
                  v.rspMst.data( 3 downto 0)        := EOE_TYPE_SET_IP_PARM_RSP_C;
                  v.rspMst.data( 7 downto 4)        := x"0";  -- port
                  v.rspMst.data(          8)        := '1';   -- last
                  v.rspMst.data(15 downto 9)        := (others => '0');
                  v.rspMst.ben                      := "11";
                  v.rspMst.last                     := '0';
                  v.rspMst.usr(MBX_TYP_EOE_C'range) := MBX_TYP_EOE_C;
                  v.rspMst.valid                    := '1';
            elsif ( mbxRdyOb = '1' ) then
               if ( r.rspMst.last = '1' ) then
                  v.rspMst.last  := '0';
                  v.rspMst.valid := '0';
                  if ( r.drained = '1' ) then
                     v.state := IDLE;
                  else
                     v.state := DROP;
                  end if;
               else
                  v.rspMst.data := r.rspStatus;
                  v.rspMst.last := '1';
               end if;
            end if;

         when DROP =>
            m.valid  := r.eoeErr;
            m.last   := r.eoeErr;
            v.fragNo := (others => '0');
            rdy      := not r.drained;
            if ( (r.eoeErr and eoeRdyLoc ) = '1' ) then
               v.eoeErr := '0';
            end if;
            if ( ( mbxMstIb.valid and rdy and mbxMstIb.last ) = '1' ) then
               v.drained := '1';
            end if;
            if ( ( v.drained and not v.eoeErr ) = '1' ) then
               if ( EOE_TYPE_SET_IP_PARM_REQ_C /= r.frameType ) then
                  v.numDrops := r.numDrops + 1;
               end if;
               v.state    := IDLE;
            end if;

      end case C_STATE;

      mbxRdyIb <= rdy;
      eoeMst   <= m;
      rin      <= v;
   end process P_COMB;

   P_SEQ  : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

   GEN_NO_STORE : if ( not STORE_AND_FWD_G ) generate
      eoeMstOb   <= eoeMst;
      eoeRdyLoc  <= eoeRdyOb;
      eoeErrOb   <= r.eoeErr;
      eoeFrameSz <= (others => '0');
   end generate GEN_NO_STORE;

   GEN_STORE : if ( STORE_AND_FWD_G ) generate
      signal rstBuf : std_logic;
      signal errAck : std_logic := '0';
      signal eoeRdy : std_logic;
   begin

      rstBuf     <= rst or r.eoeErr;
      eoeErrOb   <= '0';
      eoeRdyLoc  <= eoeRdy or errAck;

      P_ERRACK : process ( clk ) is
      begin
         if ( rising_edge( clk ) ) then
            if ( rst = '1' ) then
               errAck <= '0';
            elsif ( r.eoeErr = '1' ) then
               errAck <= not errAck;
            end if;
         end if;
      end process P_ERRACK;

      U_STORE : entity work.StrmFrameBuf
         port map (
            clk        => clk,
            rst        => rstBuf,

            strmMstIb  => eoeMst,
            strmRdyIb  => eoeRdy,

            strmMstOb  => eoeMstOb,
            strmRdyOb  => eoeRdyOb,
            frameSize  => eoeFrameSz
         );

   end generate GEN_STORE;

   mbxMstOb            <= r.rspMst;

   addrCfg.macAddr     <= r.macAddr(2) & r.macAddr(1) & r.macAddr(0);
   addrCfg.macAddrVld  <= r.macAddrVld;
   addrCfg.ip4Addr     <= r.ip4Addr(1) & r.ip4Addr(0);
   addrCfg.ip4AddrVld  <= r.ip4AddrVld;

   stats(0)            <= r.numFrags;
   stats(1)            <= r.numFrams;
   stats(2)            <= r.numDrops;

end architecture rtl;
