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
use work.ESCFoEPkg.all;

-- FoE Write-File supported only at this point

entity ESCFoE is
   generic (
      -- provide an array of 'filenames' (just the first character is compared)
      -- that can be written.
      -- The selection (if any valid filename was received) is presented
      -- on 'foeFileIdx'.
      FILE_MAP_G        : FoEFileArray
   );
   port (
      clk               : in  std_logic;
      rst               : in  std_logic;

      -- mailbox interface
      mbxMstIb          : in  Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      mbxRdyIb          : out std_logic;

      mbxMstOb          : out Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      mbxRdyOb          : in  std_logic          := '1';

      -- non-FOE mailbox error is flagged here (header too short)
      mbxErrMst         : out MbxErrorType;
      mbxErrRdy         : in  std_logic;

      -- mailbox size without mailbox header (but including FOE header)
      -- this is required by FOE -- any message (including zero-length)
      -- that is smaller terinates the FOE write transaction
      mbxSize           : in  unsigned(15 downto 0);

      -- downstream interface; this data must be consumed
      -- quickly to avoid EtherCAT timeouts; while the entire
      -- datagram must be consumed without stalling (in most cases
      -- a suitably sized FIFO is used downstream) the downstream
      -- entity may assert 'foeBusy' to indicate to EtherCAT that
      -- more data cannot be accepted.
      --
      --  e.g:  foeBusy <= '1' when fifoAvailableSpace >= mbxSize else '0';
      --
      -- note that foeMst.last is asserted for one (empty, i.e., ben = "00")
      -- beat to indicate that all data has been transferred.
      -- I.e., 'foeMst' presents a defragmented stream (but the byte-enables
      -- must be considered) of data.
      foeMst            : out Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      -- ready handshake
      foeRdy            : in  std_logic := '1';
      foeBusy           : in  std_logic := '0';
      -- we detected an error
      -- if an error is flagged then processing of the 'foeMst' data
      -- must be aborted and all data discarded (e.g., by resetting the
      -- fifo).
      foeAbort          : out std_logic;
      -- downstream error; the downstream entity may assert this
      -- if there are too much data. This will cause a DISKFULL error.
      foeError          : in  FoeErrorType;
      -- every write operation terminates with a (foeDone and foeDoneAck) = '1'
      -- handshake. An operation terminates
      --   - after foeMst.last is seen
      --   - after foeAbort is seen
      --   - after foeError has been processed
      foeDone           : in  std_logic := '1';
      foeDoneAck        : out std_logic;
      -- Indicate whether the files with 'wp = true' in FILE_MAP_G are write-
      -- protected (foeFileWP = '1').
      foeFileWP         : in  std_logic := '1';
      -- Index into FILE_MAP_G that should be written.
      -- This valid with the first beat on 'foeMst' until 'foeDone and foeDoneAck'
      foeFileIdx        : out natural range 0 to 15;

      debug             : out std_logic_vector(63 downto 0) := (others => '0')
   );
end entity ESCFoE;

architecture rtl of ESCFoE is

   type StateType is (IDLE, HDR, FWD, CHECK_LAST, DRAIN, MBXERR, RESP, DONE);

   type OpType    is (IDLE, WRITE, WAIT_LAST, WAIT_DONE);

   type RegType is record
      state                   : StateType;
      opState                 : OpType;
      mbxMstOb                : Lan9254StrmMstType;
      mbxRdyIb                : std_logic;
      err                     : MbxErrorType;
      packetNo                : unsigned(31 downto 0);
      count                   : unsigned(15 downto 0);
      foeFileIdx              : natural range FILE_MAP_G'range;
      foeAbort                : std_logic;
      busy                    : std_logic;
      foeDoneAck              : std_logic;
      foeMstValid             : std_logic;
   end record RegType;

   constant REG_INIT_C        : RegType := (
      state                   => IDLE,
      opState                 => IDLE,
      mbxMstOb                => LAN9254STRM_MST_INIT_C,
      mbxRdyIb                => '1',
      err                     => MBX_ERROR_INIT_C,
      packetNo                => (others => '0'),
      count                   => (others => '0'),
      foeFileIdx              => 0,
      foeAbort                => '0',
      busy                    => '0',
      foeDoneAck              => '0',
      foeMstValid             => '0'
   );

   function toupper(constant x : in std_logic_vector(7 downto 0))
   return std_logic_vector is
      variable v : unsigned(x'range);
   begin
      v := unsigned( x );
      if ( v > 96 and v < 123 ) then
         v(5) := '0';
      end if;
      return std_logic_vector( v );
   end function toupper;

   signal r                   : RegType := REG_INIT_C;
   signal rin                 : RegType;

   signal mbxRdyIbLoc         : std_logic;

   signal foeMstLoc           : Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;

begin

   debug(2 downto 0)          <= toSlv( StateType'pos( r.state ), 3 );
   debug(3)                   <= mbxRdyOb;
   debug(5 downto 4)          <= toSlv( OpType'pos( r.opState ), 2  );
   debug(6)                   <= r.mbxMstOb.valid;
   debug(7)                   <= r.mbxMstOb.last;
   debug(23 downto  8)        <= r.mbxMstOb.data;
   debug(39 downto 24)        <= mbxMstIb.data;
   debug(40)                  <= mbxMstIb.valid;
   debug(41)                  <= mbxMstIb.last;
   debug(42)                  <= mbxRdyIbLoc;
   debug(43)                  <= r.err.vld;
   debug(44)                  <= mbxErrRdy;
   debug(45)                  <= foeMstLoc.valid;
   debug(46)                  <= foeMstLoc.last;
   debug(47)                  <= foeRdy;
   debug(48)                  <= r.foeAbort;
   debug(49)                  <= r.foeDoneAck;
   debug(50)                  <= foeDone;
   debug(51)                  <= foeBusy;
   debug(55 downto 52)        <= foeError(3 downto 0);
   debug(63 downto 56)        <= (others => '0');

   P_COMB : process ( r, mbxMstIb, mbxRdyOb, mbxSize, mbxErrRdy, foeRdy, foeBusy, foeError, foeDone, foeFileWP ) is
      variable v   : RegType;
   begin
      v := r;

      if ( ( mbxMstIb.valid and r.mbxRdyIb and mbxMstIb.last ) = '1' ) then
         v.mbxRdyIb := '0';
      end if;

      if ( ( foeDone and r.foeDoneAck ) = '1' ) then
         v.foeDoneAck := '0';
         v.foeAbort   := '0';
         v.opState    := IDLE;
      end if;

      if ( ( r.foeMstValid and foeRdy ) = '1' ) then
         v.foeMstValid := '0';
      end if;

      foeMstLoc         <= mbxMstIb;
      foeMstLoc.valid   <= r.foeMstValid;
      foeMstLoc.ben     <= "00";
      if ( r.opState = WAIT_LAST ) then
         foeMstLoc.last <= '1';
      else
         foeMstLoc.last <= '0';
      end if;

      mbxRdyIbLoc    <= r.mbxRdyIb;

      v.mbxMstOb.ben                      := "11";
      v.mbxMstOb.usr(MBX_TYP_FOE_C'range) := MBX_TYP_FOE_C;

      C_STATE : case ( r.state ) is

         when IDLE =>
            v.err.code := (others => '0');
            v.count    := to_unsigned( 0, v.count'length );
            v.mbxRdyIb := '1';
            v.state    := HDR;
            v.busy     := '0';

         when HDR =>
            if ( ( mbxMstIb.valid and r.mbxRdyIb ) = '1' ) then

               v.count          := r.count + 2;

               if ( ( r.count = 0 ) and ( r.foeAbort = '1' ) ) then
                  -- a previous error is still pending and has not been acked
                  -- by the downstream module;
                  v.err.code        := FOE_ERR_CODE_ILLEGAL_C;
                  v.state           := DRAIN;
               elsif ( mbxMstIb.last = '1' or mbxMstIb.ben /= "11" ) then
                  -- by default drop short messages
                  -- too short; drop
                  v.err.code        := MBX_ERR_CODE_SIZETOOSHORT_C;
                  v.foeAbort        := '1';
                  v.state           := DRAIN;
               end if;

               if ( ( r.count = 0 ) and ( v.foeAbort = '0' ) ) then
                  if    ( ( mbxMstIb.data(7 downto 0) = FOE_OP_WRQ_C  ) and (r.opState = IDLE  ) ) then
                     v.packetNo := to_unsigned( 0, v.packetNo'length );
                  elsif ( ( mbxMstIb.data(7 downto 0) = FOE_OP_DATA_C ) and (r.opState = WRITE ) ) then
                     if ( foeBusy = '1' ) then
                        v.busy     := '1';
                        v.state    := DRAIN;
                     elsif ( foeError /= FOE_NO_ERROR_C ) then
                        v.err.code  := FOE_ERR_CODE_DISKFULL_C;
                        v.foeAbort  := '1';
                        v.state     := DRAIN;
                     else
                        v.packetNo  := r.packetNo + 1;
                     end if;
                  elsif ( ( mbxMstIb.data(7 downto 0) = FOE_OP_DATA_C ) and (r.opState = WAIT_LAST ) ) then
                     if ( foeError /= FOE_NO_ERROR_C ) then
                        v.err.code  := FOE_ERR_CODE_DISKFULL_C;
                        v.foeAbort  := '1';
                     end if;
                     v.busy  := not foeDone;
                     v.state := DRAIN;
                  else
                     v.err.code := FOE_ERR_CODE_ILLEGAL_C;
                     v.foeAbort := '1';
                     v.state    := DRAIN;
                  end if;
               elsif ( ( r.count = 2 ) and ( v.foeAbort = '0' ) ) then
                  if ( r.opState = WRITE ) then
                     if ( std_logic_vector( r.packetNo(15 downto  0) ) /= mbxMstIb.data ) then
                        v.err.code := FOE_ERR_CODE_PACKETNO_C;
                        v.foeAbort := '1';
                        v.state    := DRAIN;
                     end if;
                  end if;
               elsif ( ( r.count = 4 ) and ( mbxMstIb.ben = "11" ) ) then
                  -- 'last' may be set if this is an empty last data message
                  if ( r.opState = WRITE ) then
                     if ( std_logic_vector( r.packetNo(31 downto 16) ) /= mbxMstIb.data ) then
                        v.err.code := FOE_ERR_CODE_PACKETNO_C;
                        v.foeAbort := '1';
                        v.state    := DRAIN;
                     else
                        v.foeAbort := '0';
                        v.err.code := (others => '0');
                        if ( mbxMstIb.last = '0' ) then
                           v.state := FWD;
                        else
                           v.state := CHECK_LAST;
                        end if;
                     end if;
                  end if;
               elsif ( (r.count = 6) and (r.opState = IDLE) and (mbxMstIb.ben(0) = '1') ) then
                  -- exception for single-char file-name; we don't care about 'last' or ben(1)
                  -- WRITE - check filename
                  v.err.code := FOE_ERR_CODE_NOTFOUND_C;
                  v.foeAbort := '1';
                  v.state    := DRAIN;

                  L_FILEN : for i in FILE_MAP_G'range loop
                     if (   ( FILE_MAP_G(i).id = FOE_FILE_ID_WILDCARD_C )
                         or ( FILE_MAP_G(i).id = toupper( mbxMstIb.data(7 downto 0) ) ) ) then
                        if ( ( foeFileWP = '1' ) and FILE_MAP_G(i).wp ) then
                           v.err.code    := FOE_ERR_CODE_NORIGHTS_C;
                        else
                           v.err.code    := (others => '0');
                           v.foeAbort    := '0';
                           v.foeFileIdx  := i;
                        end if;
                        exit L_FILEN;
                     end if;
                  end loop L_FILEN;
               elsif ( v.foeAbort = '0' ) then
                  -- don't think we can ever get here
                  v.err.code := FOE_ERR_CODE_VENDOR_C;
                  v.foeAbort := '1';
                  v.state    := DRAIN;
               end if;
         end if;

         when FWD =>
            foeMstLoc.valid <= mbxMstIb.valid;
            foeMstLoc.ben   <= mbxMstIb.ben;
            mbxRdyIbLoc     <= foeRdy;
            if ( (mbxMstIb.valid and foeRdy) = '1' )then
               if ( ( mbxMstIb.ben = "01" ) or ( mbxMstIb.ben = "10" ) ) then
                  v.count := r.count + 1;
               elsif ( mbxMstIb.ben = "11" ) then
                  v.count := r.count + 2;
               end if;
               if ( mbxMstIb.last = '1' ) then
                  v.state := CHECK_LAST;
               end if;
            end if;

         when CHECK_LAST =>
            if ( r.count < mbxSize ) then
               -- hold off the final ACK until all writing is done
               v.opState     := WAIT_LAST;
               v.busy        := not foeDone;
               -- emit an empty word so they can see 'last'
               v.foeMstValid := '1';
            end if;
            v.state := RESP;

         when DRAIN =>
            if ( r.mbxRdyIb = '0' ) then
               if ( ( r.foeAbort = '1' ) and ( v.err.code(15) = '0' )  ) then
                  -- mailbox error
                  v.err.vld        := '1';
                  v.state          := MBXERR;
               else
                  v.state          := RESP;
               end if;
            end if;

         when MBXERR =>
            if ( ( r.err.vld and mbxErrRdy ) = '1' ) then
               v.err.vld := '0';
               v.state   := DONE;
            end if;

         when RESP =>
            if ( r.mbxMstOb.valid = '0' ) then
               v.count          := to_unsigned( 0, v.count'length );
               v.mbxMstOb.valid := '1';
               v.mbxMstOb.last  := '0';
               if     ( r.foeAbort = '1' ) then
                  v.packetNo      := resize( unsigned( r.err.code ), v.packetNo'length );
                  v.mbxMstOb.data := x"00" & FOE_OP_ERR_C;
               elsif  ( r.busy = '1' ) then
                  v.mbxMstOb.data := x"00" & FOE_OP_BUSY_C;
                  v.mbxMstOb.last := '1';
               else
                  v.mbxMstOb.data := x"00" & FOE_OP_ACK_C;
               end if;
            elsif ( mbxRdyOb = '1' ) then
               if ( r.mbxMstOb.last = '1' ) then
                  -- done sending reply
                  v.mbxMstOb.valid := '0';
                  v.state          := IDLE;
                  if    ( r.foeAbort = '1' ) then
                     v.state := DONE;
                  elsif ( r.opState = IDLE ) then
                     -- sent ACK to the write request; transition into WRITE opState
                     v.opState := WRITE;
                  elsif ( r.opState = WAIT_LAST ) then
                     if ( r.busy = '0' ) then
                        -- if we just sent a BUSY reply then we are not done!
                        v.state   := DONE;
                     end if;
                  end if;
               else
                  v.count := r.count + 1;
                  if     ( r.count = 0 ) then
                     v.mbxMstOb.data := std_logic_vector( r.packetNo(15 downto  0) );
                  else
                     v.mbxMstOb.data := std_logic_vector( r.packetNo(31 downto 16) );
                     v.mbxMstOb.last := '1';
                  end if;
               end if;
            end if;

        when DONE =>
           v.foeDoneAck := '1';
           v.opState    := WAIT_DONE;
           v.state      := IDLE;

      end case C_STATE;

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

   mbxMstOb    <= r.mbxMstOb;
   mbxErrMst   <= r.err;
   mbxRdyIb    <= mbxRdyIbLoc;
   foeAbort    <= r.foeAbort;
   foeDoneAck  <= r.foeDoneAck;
   foeFileIdx  <= r.foeFileIdx;
   foeMst      <= foeMstLoc;

end architecture rtl;
