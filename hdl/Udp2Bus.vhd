------------------------------------------------------------------------------
--      Copyright (c) 2022-2023 by Paul Scherrer Institute, Switzerland
--      All rights reserved.
--  Authors: Till Straumann
--  License: PSI HDL Library License, Version 2.0 (see License.txt)
------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Lan9254Pkg.all;
use     work.Udp2BusPkg.all;

use     work.IlaWrappersPkg.all;

-- bus access via UDP

-- The following protocol is being used (UDP payload)
--
-- packet is a sequence of little-endian 16-bit words
--
--    REQUEST               :=  request-header , { request-data }
--
--    16-bit request header:
--        bit pos:
--        15..12: RESERVED -- set to '0'.
--        11..8 : sequence number; two subsequently received requests with the same sequence number
--                are interpreted as a 'retry'. The second request is not executed by a cached reply
--                is re-sent.
--         7..4 : command:
--                    0      -> ILLEGAL
--                    1      -> check protocol version
--                    2      -> data-transfer
--                    others -> RESERVED
--         3..0 : protocol version; currently supported: 1
--
-- COMMANDS:
--
--   Check version (1): used to 'seed' the sequence number (ensure a subsequent transfer uses a fresh number)
--   =================  also used to check the protocol version.
--
-- REPLY: the request-header is returned verbatim in the reply
--   EXCEPT: - version check command: the version in the reply is the version supported by firmware
--           - illegal command:       the ILLEGAL command is returned
--
--   Data Transfer (2): The header is followed by a sequence of read- or write- commands. Each of these commands
--   =================  has its own header:
--
--   data-xfer:=  request-header, { command }
--   command  :=  read-command | { write-command , write-data }
--
--   the command header consists of two 16-bit words:
--      word1: address (lower 16-bits)
--      word2: 
--        bit pos:
--        15      :    read/write bit; if '1' this is a read command, otherwise a write command.
--        14..12  :    byte-lane encoding
--        11.. 4  :    burst count (actual count - 1, i.e., 0 is a single transfer, 0xff a burst of 256 transfers)
--        3 .. 0  :    high 4 bits of address.
--
--   The address is a **double-word** address, i.e., a byte address is obtained by shifting left by two bits.
--   Individual byte lanes are accessed by using the byte-lane descriptor (bits 14..12):
--       000      :    byte-lane  0       (bits  7.. 0)
--       001      :    byte-lane  1       (bits 15.. 8)
--       010      :    byte-lane  2       (bits 23..16)
--       011      :    byte-lane  3       (bits 31..24)
--       100      :    byte-lanes 0 and 1 (bits 15.. 0)
--       101      :    byte-lanes 2 and 3 (bits 31..16)
--       110      :    byte-lanes 0-3     (bits 31.. 0)
--       111      :    RESERVED
--   Note that mis-aligned word- and double-word access is not supported.
--
--   write-data:
--       a) 8-bit  write data (lane descriptor 0..3) still occupies a 16-bit word in the request; only bits (7..0) are used.
--       b) 16-bit write data (lane descriptor 4..5) uses a single 16-bit word
--       c) 32-bit write data (lane descriptor 6   ) uses two 16-bit words (little-endian, i.e., least-significant word first)
--
--  Burst Transfer 
--      - burst transfers use the same lane desriptor for each transfer.
--
--  Examples:
--      write '0xda' to byte-address 21, then read-back 3 32-bit words from address 16
--
--      0x3421  - request header; sequence number 0x34, read/write request: 2, protocol version: 1
--      0x0005  - lower-bits of address 21 (= word address 21/4 = 5)
--      0x1000  - write request (bit 15 clear), access byte-lane 1 (byte/address modulo 4), burst count 0, high-address bits 0x0
--      0x0004  - lower-bits of addrss 16 (= word address 16/4 = 4)
--      0xe020  - read request (bit 15 set), lane-descriptor: "110" = 32-bit, burst count 2 (3 - 1), high-address bits 0x0
--
-- The above message is in little-endian format, i.e., would have to be sent as 0x21, 0x34, 0x05, 0x00, ... 0xe0.
--
-- REPLY:
--
--  data-xfer-reply:  request-header-echo, { readback-data }, status
--
--  readback data is a sequence of 16-bit words
--    8-bit read-back data is aligned to bits 7..0 (bits 15..8 unused)
--   16-bit read-back data (as everyting else is little-endian)
--   32-bit read-back data is returned as two 16-bit words in little-endian format (least-significant word first)
--  no data is returned for write transfers (but success is reflected by status)
--
--  status:
--        bit pos:
--        10..0  : number of successful transfers executed  
--        14..11 : RESERVED
--        15     : Error flag (error was encountered)
--
--  a transfer request is aborted when an error is encountered. By checking the number of successful transfers
--  the user may determine which transfer failed.
--    - each read/write transfer whether part of a burst or not counts as one transfer. E.g., the reply to the
--      example request above would return a number of 4 (one 8-bit write plus 3 32-bit reads).
--
-- CAVEAT:
--    if the sequence number matches the previous sequence number then the cached reply is returned
--    without checking that the actual commands in the request match the previous request.
--    This may lead to unexpected results if the user forgets to increment the sequence number.
entity Udp2Bus is
   generic (
      MAX_FRAME_SIZE_G : natural;
      GEN_ILA_G        : boolean := true
   );
   port (
      clk         : in  std_logic;
      rst         : in  std_logic;

      req         : out Udp2BusReqType;
      rep         : in  Udp2BusRepType     := UDP2BUSREP_INIT_C;

      strmMstIb   : in  Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      strmRdyIb   : out std_logic;

      strmMstOb   : out Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      strmRdyOb   : in  std_logic          := '1';

      ilaTrgIb    : in  std_logic          := '0';
      ilaAckIb    : out std_logic          := '1';
      ilaTrgOb    : out std_logic          := '0';
      ilaAckOb    : in  std_logic          := '1';

      frameSize   : out unsigned(10 downto 0)
   );
end entity Udp2Bus;

architecture rtl of Udp2Bus is

   constant PROTO_VER_C : std_logic_vector(3 downto 0) := "0001";
   constant MSG_NON_C   : std_logic_vector(7 downto 4) := "0000";
   constant MSG_VER_C   : std_logic_vector(7 downto 4) := "0001";
   constant MSG_RDW_C   : std_logic_vector(7 downto 4) := "0010";

   constant RDW_IDX_C   : natural := 15;
   constant BEH_IDX_C   : natural := 14;
   constant BEL_IDX_C   : natural := 12;
   constant BTH_IDX_C   : natural := 11;
   constant BTL_IDX_C   : natural :=  4;
   constant ADH_IDX_C   : natural :=  3;
   constant ADL_IDX_C   : natural :=  0;

   constant MAX_PAYLOAD_WORDS_C : natural := MAX_FRAME_SIZE_G / 2;

   function cmd2be(constant cmd : std_logic_vector(15 downto 0))
   return std_logic_vector is
   begin
      case to_integer(unsigned(cmd(BEH_IDX_C downto BEL_IDX_C))) is
         when 0      => return "0001";
         when 1      => return "0010";
         when 2      => return "0100";
         when 3      => return "1000";
         when 4      => return "0011";
         when 5      => return "1100";
         when others => return "1111";
      end case;
   end function cmd2be;

   function cmd2len(constant cmd : std_logic_vector(15 downto 0))
   return positive is
      variable n : natural;
   begin
      n := to_integer(unsigned(cmd(BEH_IDX_C downto BEL_IDX_C)));
      if     ( n < 4 ) then
         return 1;
      elsif  ( n < 6 ) then
         return 2;
      else
         return 4;
      end if;
   end function cmd2len;

   function cmdLenIs1(constant cmd : std_logic_vector(15 downto 0))
   return boolean is
      variable n : natural;
   begin
      n := to_integer(unsigned(cmd(BEH_IDX_C downto BEL_IDX_C)));
      return ( n < 4 );
   end function cmdLenIs1;

   function getBurst(constant cmd : std_logic_vector(15 downto 0))
   return unsigned is
   begin
      return unsigned(cmd(BTH_IDX_C downto BTL_IDX_C));
   end function getBurst;

   type StateType is (IDLE, CMD1, CMD2, CMD3, CMD4, XFER, XFER2, STATUS, REPLY);

   -- memory buffer needs a minimal delay between write and readback when
   -- messages are small.
   constant REPLAY_DELAY_C : natural := 2;

   type RegType is record
      state           : StateType;
      req             : Udp2BusReqType;
      rdy             : std_logic;
      sig             : std_logic_vector(11 downto 0);
      skip            : boolean;
      numCmds         : unsigned( 9 downto 0);
      numWrds         : unsigned( 9 downto 0);
      err             : std_logic;
      len1            : boolean;
      done            : std_logic;
      burst           : unsigned( 7 downto 0);
      hiword          : std_logic_vector(15 downto 0);
      replyDelay      : std_logic_vector(REPLAY_DELAY_C - 1 downto 0);
   end record RegType;

   constant REG_INIT_C : RegType := (
      state           => IDLE,
      req             => UDP2BUSREQ_INIT_C,
      rdy             => '1',
      sig             => (others => '0'),
      skip            => false,
      numCmds         => (others => '0'),
      numWrds         => (others => '0'),
      err             => '0',
      len1            => false,
      done            => '0',
      burst           => (others => '0'),
      hiword          => (others => '0'),
      replyDelay      => (others => '0')
   );

   signal r           : RegType := REG_INIT_C;
   signal rin         : RegType;

   signal memMstIb    : Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
   signal memRdyIb    : std_logic;
   signal memMstOb    : Lan9254StrmMstType;
   signal memRdyOb    : std_logic := '0';
   signal memReplay   : std_logic := '0';

   signal strmMstObLoc: Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
   
   signal frameSizeLoc: unsigned(10 downto 0);

begin

   GEN_NO_ILA : if ( not GEN_ILA_G ) generate
      ilaTrgOb <= ilaTrgIb;
      ilaAckIb <= ilaAckOb;
   end generate GEN_NO_ILA;

   GEN_ILA : if ( GEN_ILA_G ) generate

      signal probe0      : std_logic_vector(63 downto 0) := (others => '0');
      signal probe1      : std_logic_vector(63 downto 0) := (others => '0');
      signal probe2      : std_logic_vector(63 downto 0) := (others => '0');
      signal probe3      : std_logic_vector(63 downto 0) := (others => '0');

      function to_sl(c : boolean) return std_logic is
      begin
         if ( c ) then return '1'; else return '0'; end if;
      end function to_sl;

   begin

      U_UDP_ILA : component Ila_256
         port map (
            clk          => clk,
            probe0       => probe0,
            probe1       => probe1,
            probe2       => probe2,
            probe3       => probe3,
            trig_out     => ilaTrgOb,
            trig_out_ack => ilaAckOb,
            trig_in      => ilaTrgIb,
            trig_in_ack  => ilaAckIb
         );

      probe0(  3 downto  0 ) <= std_logic_vector( to_unsigned( StateType'pos( r.state ), 4 ) );

      probe0(            4 ) <= strmMstIb.valid;
      probe0(            5 ) <= strmMstIb.last;
      probe0(            6 ) <= r.rdy;

      probe0(            7 ) <= memMstIb.valid;
      probe0(            8 ) <= memMstIb.last;
      probe0(            9 ) <= memRdyIb;

      probe0(           10 ) <= memMstOb.valid;
      probe0(           11 ) <= memMstOb.last;
      probe0(           12 ) <= memRdyOb;

      probe0(           13 ) <= strmMstObLoc.valid;
      probe0(           14 ) <= strmMstObLoc.last;
      probe0(           15 ) <= strmRdyOb;

      probe0(           16 ) <= r.req.valid;
      probe0(           17 ) <= rep.valid;

      probe0(           18 ) <= r.done;
      probe0(           19 ) <= to_sl(r.skip);

      probe0( 29 downto 20 ) <= std_logic_vector( r.numCmds );
      probe0( 39 downto 30 ) <= std_logic_vector( r.numWrds );
      probe0( 55 downto 40 ) <= strmMstIb.data;
      probe0( 63 downto 56 ) <= (others => '0');

      probe1( 10 downto  0 ) <= std_logic_vector( frameSizeLoc );
      probe1(           11 ) <= memReplay;
      probe1( 23 downto 12 ) <= r.sig;
      probe1( 63 downto 24 ) <= (others => '0');

   end generate GEN_ILA;

   P_COMB : process ( r, rep, strmMstIb, strmRdyOb, memRdyIb, memMstOb ) is
      variable v      : RegType;
      variable replay : std_logic;
   begin

      v                  := r;
      memMstIb           <= LAN9254STRM_MST_INIT_C;
      memMstIb.ben       <= "11";
      replay             := '0';
      strmMstObLoc       <= memMstOb;
      strmMstObLoc.valid <= '0';
      memRdyOb           <= '0';

      v.replyDelay  := r.replyDelay(r.replyDelay'left - 1 downto 0) & "0";

      case ( r.state ) is
         when IDLE  =>
            -- strmRdyIb = '1' at this point
            if ( strmMstIb.valid = '1' ) then
               v.skip    := ( strmMstIb.last = '0' );
               v.err     := '0';
               v.numCmds := (others => '0');
               v.numWrds := to_unsigned( 2, v.numWrds'length ); -- header and footer
               if ( not r.skip ) then
                  -- give time copy data to storage in case we have a replay or short command
                  v.replyDelay   := (others => '1');
                  -- write header to memory
                  memMstIb.data  <= strmMstIb.data;
                  memMstIb.valid <= '1';
                  -- record this message's signature
                  v.sig          := strmMstIb.data(11 downto 0);
                  if    ( strmMstIb.data(MSG_VER_C'range) = MSG_VER_C ) then
                     -- supply the protocol version we support
                     memMstIb.data(PROTO_VER_C'range) <= PROTO_VER_C;
                     memMstIb.last                    <= '1';
                  elsif ( strmMstIb.data(7 downto 0) = MSG_RDW_C & MSG_VER_C ) then
                     if ( r.sig = v.sig ) then
                        -- same signature; replay from memory
                        replay           := '1';
                        memMstIb.valid   <= '0';
                     else
                        -- ordinary R/W command
                        if ( v.skip ) then
                           v.state       := CMD1;
                           v.skip        := false;
                        else
                           -- empty RDWR cmd
                           v.state       := STATUS;
                           v.rdy         := '0';
                           memMstIb.last <= '1';
                        end if;
                     end if;
                  else
                     -- unsupported command or version
                     memMstIb.data(PROTO_VER_C'range) <= PROTO_VER_C;
                     memMstIb.data(MSG_NON_C'range)   <= MSG_NON_C;
                     memMstIb.last                    <= '1';
                     v.sig(MSG_NON_C'range)           := MSG_NON_C;
                     v.err                            := '1';
                  end if;
               end if;

               if ( ( not v.skip ) and ( v.state = IDLE ) ) then
                  -- last word of skipped message; we could have skipped the payload because
                  --  a) VER command with (unexpected payload)
                  --  b) RDW command on replay
                  --  c) illegal command
                  --  d) empty RDWR command
                  v.rdy   := '0';
                  v.state := REPLY;
               end if;
            end if;

         when CMD1 | CMD2 | CMD3 | CMD4   =>
            if ( strmMstIb.valid = '1' ) then
               case ( r.state ) is
                  when CMD1        =>
                     v.state                    := CMD2;
                     v.req.dwaddr(15 downto  0) := strmMstIb.data;
                  when CMD2        =>
                     v.req.dwaddr(19 downto 16) := strmMstIb.data(ADH_IDX_C downto ADL_IDX_C);
                     v.req.be                   := cmd2be( strmMstIb.data );
                     v.req.rdnwr                := strmMstIb.data( RDW_IDX_C );
                     v.len1                     := cmdLenIs1( strmMstIb.data );
                     v.burst                    := getBurst( strmMstIb.data );
                     if ( v.req.rdnwr = '1' ) then
                        v.state     := XFER;
                     else
                        v.state     := CMD3;
                     end if;
                  when CMD3        =>
                     -- replicate data so any byte-enable combo is fine
                     if ( r.len1 ) then
                        v.req.data( 7 downto  0) := strmMstIb.data(7 downto 0);
                        v.req.data(15 downto  8) := strmMstIb.data(7 downto 0);
                        v.req.data(23 downto 16) := strmMstIb.data(7 downto 0);
                        v.req.data(31 downto 24) := strmMstIb.data(7 downto 0);
                        v.state                  := XFER;
                     else
                        v.req.data               := strmMstIb.data & strmMstIb.data;
                        if ( ( v.req.be(3) and v.req.be(1) ) = '1' ) then
                           -- 32-bit transfer
                           v.state := CMD4;
                        else
                           v.state := XFER;
                        end if;
                     end if;
                  when others      =>
                     v.req.data(31 downto 16) := strmMstIb.data;
                     v.state                  := XFER;
               end case;

               if ( v.state = XFER ) then
                  v.done      := strmMstIb.last;
                  v.req.valid := '1';
                  v.rdy       := '0';
               elsif ( strmMstIb.last = '1' ) then
                  -- incomplete message; flag error and send reply
                  v.done      := '1';
                  v.err       := '1';
                  v.state     := STATUS;
                  v.rdy       := '0';
               end if;

            end if;

         when XFER  =>
            if ( ( rep.valid and r.req.valid ) = '1' ) then
               v.req.valid := '0';
               if ( rep.berr = '0' ) then
                  -- keep track of number of commands successfully executed
                  v.numCmds := r.numCmds + 1;
                  -- by default proceed to read the next command
                  if ( r.burst /= 0 ) then
                     -- increment address by shifting byte-lanes and incrementing
                     -- the double-word address when the lanes roll over.
                     if ( r.len1 ) then
                        v.req.be := r.req.be(r.req.be'left-1 downto 0) & r.req.be(r.req.be'left);
                     elsif ( ( r.req.be(0) and r.req.be(2) ) = '0' ) then
                        -- 16-bit; negating be equals rotation by 16 bits
                        v.req.be := not r.req.be;
                     end if;
                     if ( v.req.be(0) = '1' ) then
                        v.req.dwaddr   := std_logic_vector( unsigned(r.req.dwaddr) + 1 );
                     end if;
                     v.burst        := r.burst - 1;
                     if ( r.req.rdnwr = '1' ) then
                        v.req.valid := '1';
                     else
                        v.state     := CMD3;
                     end if;
                  else
                     v.state        := CMD1;
                  end if;
                  if ( r.req.rdnwr = '1' ) then
                     if ( r.numWrds >= MAX_PAYLOAD_WORDS_C ) then
                        v.err := '1';
                     else
                        -- write read reply to memory
                        memMstIb.valid <= '1';
                        v.numWrds     := r.numWrds + 1;
                        if    ( r.req.be(0) = '1' ) then
                           memMstIb.data             <= rep.rdata(15 downto 0);
                           if ( r.req.be(2) = '1' ) then
                              if ( r.numWrds >= MAX_PAYLOAD_WORDS_C - 1 ) then
                                 v.err := '1';
                              else
                                 v.numWrds := r.numWrds + 2;
                                 -- 32-bit transfer; must store 2nd word
                                 v.state     := XFER2;
                                 v.hiword    := rep.rdata(31 downto 16);
                                 -- cancel burst; re-issue in XFER2 state
                                 v.burst     := r.burst;
                                 v.req.valid := '0';
                              end if;
                           end if;
                        elsif ( r.req.be(1) = '1' ) then
                           memMstIb.data(7 downto 0) <= rep.rdata(15 downto  8);
                        elsif ( r.req.be(2) = '1' ) then
                           memMstIb.data             <= rep.rdata(31 downto 16);
                        else
                           memMstIb.data(7 downto 0) <= rep.rdata(31 downto 24);
                        end if;
                     end if;
                  end if;
               end if;
               -- check if we have to end this transaction
               if ( ( (v.err or rep.berr) = '1' ) or ( (r.done = '1') and (v.state /= XFER2) and ( (r.burst = 0) or (r.req.rdnwr = '0') ) ) ) then
                  v.err   := v.err or rep.berr;
                  if ( ( r.req.rdnwr = '0' ) and ( r.burst /= 0 ) ) then
                     v.err := '1';
                  end if;
                  v.state := STATUS;
                  if ( r.done = '0' ) then
                     -- if we are not done and there was an error 
                     -- we are going to discard input in the 'STATUS' state
                     v.rdy := '1';
                  end if;
               end if;
               if ( v.state = CMD1 or v.state = CMD3 ) then
                  v.rdy   := '1';
               end if;
            end if;

         when XFER2 =>
            memMstIb.data  <= r.hiword;
            memMstIb.valid <= '1';
            if ( (r.done = '1') and ( (r.burst = 0) or (r.req.rdnwr = '0') ) ) then
               if ( ( r.req.rdnwr = '0' ) and ( r.burst /= 0 ) ) then
                  v.err := '1';
               end if;
               v.state := STATUS;
            else
               if ( r.burst /= 0 ) then
                  -- dwaddr has already been incremented in XFER state
                  v.burst := r.burst - 1;
                  if ( r.req.rdnwr = '1' ) then
                     v.state     := XFER;
                     v.req.valid := '1';
                  else
                     v.state := CMD3;
                     v.rdy   := '1';
                  end if;
               else
                  v.state := CMD1;
                  v.rdy   := '1';
               end if;
            end if;

         when STATUS =>
            if ( r.done = '0' ) then
               -- must discard remaining input
               if ( ( strmMstIb.valid and strmMstIb.last ) = '1' ) then
                  v.done := '1';
                  v.rdy  := '0';
               end if;
            else
               -- write status footer to memory
               memMstIb.data                  <= (15 => r.err, others => '0');
               memMstIb.data(r.numCmds'range) <= std_logic_vector(r.numCmds);
               memMstIb.valid                 <= '1';
               memMstIb.last                  <= '1';
               v.state                        := REPLY;
               -- delay in case the reply is short
               v.replyDelay                   := (others => '1');
            end if;

         when REPLY =>
            if ( r.replyDelay(r.replyDelay'left) = '0' ) then
               strmMstObLoc.valid <= memMstOb.valid;
               memRdyOb           <= strmRdyOb;
               if ( ( memMstOb.valid and memMstOb.last and strmRdyOb ) = '1' ) then
                  v.rdy   := '1';
                  v.state := IDLE;
               end if;
            end if;
      end case;

      memReplay <= replay;
      rin       <= v;
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

   U_MEM_BUF : entity work.StrmFrameBuf
      port map (
         clk          => clk,
         rst          => rst,
         restore      => memReplay,
         strmMstIb    => memMstIb,
         strmRdyIb    => memRdyIb,
         strmMstOb    => memMstOb,
         strmRdyOb    => memRdyOb,
         frameSize    => frameSizeLoc
      );

   frameSize <= frameSizeLoc;
   strmMstOb <= strmMstObLoc;
   strmRdyIb <= r.rdy;
   req       <= r.req;

end architecture rtl;
