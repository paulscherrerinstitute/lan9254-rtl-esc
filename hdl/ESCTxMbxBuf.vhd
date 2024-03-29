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

use work.Lan9254Pkg.all;
use work.Lan9254ESCPkg.all;
use work.ESCMbxPkg.all;

-- TX mailbox buffer (holding copy for repeat request)

entity ESCTxMbxBuf is
   generic (
      MBX_NUM_PAYLOAD_WORDS_G : natural
   );
   port (
      clk                     : in  std_logic;
      rst                     : in  std_logic;
      raddr                   : in  natural range 0 to MBX_NUM_PAYLOAD_WORDS_G + MBX_HDR_SIZE_C/2 - 1;
      rdat                    : out std_logic_vector(15 downto 0);
      waddr                   : in  natural range 0 to MBX_NUM_PAYLOAD_WORDS_G + MBX_HDR_SIZE_C/2 - 1;
      -- byte-enable for hi-byte; only used to determine length of last write
      wbeh                    : in  std_logic;
      lena                    : in  std_logic;
      tena                    : in  std_logic;
      htyp                    : in  std_logic_vector( 3 downto 0);
      mlen                    : in  unsigned        (15 downto 0);
      wena                    : in  std_logic;
      wdat                    : in  std_logic_vector(15 downto 0);
      wrdy                    : out std_logic;
      ecMstAck                : in  std_logic;
      ecMstRep                : in  std_logic;
      haveBackup              : out boolean
   );
end entity ESCTxMbxBuf;

architecture rtl of ESCTxMbxBuf is

   constant MBX_HDR_WSIZ_C : natural := MBX_HDR_SIZE_C / 2;
   constant MBX_WSIZ_C     : natural := MBX_NUM_PAYLOAD_WORDS_G + MBX_HDR_WSIZ_C;

   subtype MbxIdxType  is natural range 0 to MBX_WSIZ_C - 1;


   type    MbxWrdArray is array (MbxIdxType)                            of std_logic_vector(15 downto 0);
   type    MbxHdrArray is array (natural range 0 to MBX_HDR_WSIZ_C - 1) of std_logic_vector(15 downto 0);

   type    MbxBufType is record
      hdr : MbxHdrArray;
      buf : MbxWrdArray;
   end record MbxBufType;

   type    MbxBufArray is array (natural range 0 to 1) of MbxBufType;

   type    RegType is record
      wrBuf        : natural range 0 to 1;
      rdy          : std_logic;
      haveBackup   : boolean;
      cnt          : unsigned(2 downto 0);
   end record RegType;

   constant REG_INIT_C : RegType := (
      wrBuf        =>  0,
      rdy          => '1',
      haveBackup   => false,
      cnt          => "001"
   );

   -- initialize, mainly to avoid simulation warnings about
   -- undefined values which may be read when we read dummy
   -- values to trigger the SM.
   signal  mbx     : MbxBufArray := (
      others => (
           hdr => (others => (others => '0')),
           buf => (others => (others => '0'))
      )
   );

   signal  r       : RegType := REG_INIT_C;
   signal  rin     : RegType;

begin

   P_RDBUF : process (r, mbx, raddr) is
   begin
      if ( raddr < MBX_HDR_WSIZ_C ) then
         rdat <= mbx(r.wrBuf).hdr(raddr);
      else
         rdat <= mbx(r.wrBuf).buf(raddr);
      end if;
   end process P_RDBUF;

   P_WRBUF : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( ( not ecMstRep and ( ecMstAck or r.rdy ) ) = '1' ) then
            if ( lena = '1' ) then
               -- parallel write of header
               mbx(r.wrBuf).hdr(0)                <= std_logic_vector( mlen );
            end if;
            if ( tena = '1' ) then
               mbx(r.wrBuf).hdr(1)                <= ( others => '0' );
               mbx(r.wrBuf).hdr(2)                <= ( others => '0' );
               mbx(r.wrBuf).hdr(2)(MBX_CNT_RNG_T) <= std_logic_vector( r.cnt );
               mbx(r.wrBuf).hdr(2)(MBX_TYP_RNG_T) <= htyp;
            end if;
            if ( wena = '1' ) then
               if ( waddr >= MBX_HDR_WSIZ_C ) then
                  mbx(r.wrBuf).buf(waddr) <= wdat;
               else
                  -- indexed write of header
                  mbx(r.wrBuf).hdr(waddr) <= wdat;
               end if;
            end if;
          end if;
      end if;
   end process P_WRBUF;

   P_COMB  : process ( r, tena, wbeh, waddr, wena, ecMstAck, ecMstRep ) is
      variable v : RegType;
   begin
      v      := r;

      if ( ecMstAck = '1' ) then
         v.rdy        := '1';
         v.wrBuf      := 1 - r.wrBuf;
         v.haveBackup := true;
      end if;

      if ( ( ecMstRep = '1' ) and r.haveBackup ) then
         -- restore buffer
         v.wrBuf := 1 - r.wrBuf;
         v.rdy   := '0';
      elsif ( v.rdy = '1' ) then
         if ( tena  = '1' ) then
            if ( ( r.cnt = 7 ) or ( r.cnt = 0 ) ) then
               v.cnt := "001";
            else
               v.cnt := r.cnt + 1;
            end if;
         end if;
         if ( wena = '1' ) then
            if ( ( waddr = MBX_WSIZ_C - 1 ) and ( wbeh = '1' ) ) then
               v.rdy := '0';
            end if;
         end if;
      end if;

      rin <= v;
   end process P_COMB;

   P_SEQ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

   wrdy       <= r.rdy;
   haveBackup <= r.haveBackup;

end architecture rtl;
