library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Lan9254Pkg.all;
use     work.Udp2BusPkg.all;

-- bus access via UDP

entity Udp2Bus is
   port (
      clk         : in  std_logic;
      rst         : in  std_logic;

      req         : out Udp2BusReqType;
      rep         : in  Udp2BusRepType     := UDP2BUSREP_INIT_C;

      strmMstIb   : in  Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      strmRdyIb   : out std_logic;

      strmMstOb   : out Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      strmRdyOb   : in  std_logic          := '1';

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
   constant ADH_IDX_C   : natural := 11;
   constant ADL_IDX_C   : natural :=  0;

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

   type StateType is (IDLE, CMD1, CMD2, CMD3, CMD4, XFER, XFER2, STATUS, REPLY);

   -- memory buffer needs a minimal delay between write and readback when
   -- messages are small.
   constant REPLAY_DELAY_C : natural := 2;

   type RegType is record
      state           : StateType;
      req             : Udp2BusReqType;
      memMst          : Lan9254StrmMstType;
      rdy             : std_logic;
      sig             : std_logic_vector(11 downto 0);
      skip            : boolean;
      numCmds         : unsigned( 9 downto 0);
      err             : std_logic;
      len1            : boolean;
      done            : std_logic;
      hiword          : std_logic_vector(15 downto 0);
      replyDelay      : std_logic_vector(REPLAY_DELAY_C - 1 downto 0);
   end record RegType;

   constant REG_INIT_C : RegType := (
      state           => IDLE,
      req             => UDP2BUSREQ_INIT_C,
      memMst          => LAN9254STRM_MST_INIT_C,
      rdy             => '1',
      sig             => (others => '0'),
      skip            => false,
      numCmds         => (others => '0'),
      err             => '0',
      len1            => false,
      done            => '0',
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

begin

   P_COMB : process ( r, rep, strmMstIb, strmRdyOb, memRdyIb, memMstOb ) is
      variable v      : RegType;
      variable replay : std_logic;
   begin

      v               := r;
      memMstIb        <= LAN9254STRM_MST_INIT_C;
      memMstIb.ben    <= "11";
      replay          := '0';
      strmMstOb       <= memMstOb;
      strmMstOb.valid <= '0';
      memRdyOb        <= '0';

      v.replyDelay  := r.replyDelay(r.replyDelay'left - 1 downto 0) & "0";

      case ( r.state ) is
         when IDLE  =>
            -- strmRdyIb = '1' at this point
            if ( strmMstIb.valid = '1' ) then
               v.skip    := ( strmMstIb.last = '0' );
               v.err     := '0';
               v.numCmds := (others => '0');
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
                     v.req.dwaddr(27 downto 16) := strmMstIb.data(ADH_IDX_C downto ADL_IDX_C);
                     v.req.be                   := cmd2be( strmMstIb.data );
                     v.req.rdnwr                := strmMstIb.data( RDW_IDX_C );
                     v.len1                     := cmdLenIs1( strmMstIb.data );
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
                  v.state   := CMD1;
                  if ( r.req.rdnwr = '1' ) then
                     -- write read reply to memory
                     memMstIb.valid <= '1';
                     if    ( r.req.be(0) = '1' ) then
                        memMstIb.data             <= rep.rdata(15 downto 0);
                        if ( r.req.be(2) = '1' ) then
                           -- 32-bit transfer; must store 2nd word
                           v.state    := XFER2;
                           v.hiword   := rep.rdata(31 downto 16);
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
               if ( ( rep.berr = '1' ) or ( (r.done = '1') and (v.state /= XFER2) ) ) then
                  v.err   := rep.berr;
                  v.state := STATUS;
                  if ( r.done = '0' ) then
                     -- if we are not done and there was an error 
                     -- we are going to discard input in the 'STATUS' state
                     v.rdy := '1';
                  end if;
               end if;
               if ( v.state = CMD1 ) then
                  v.rdy   := '1';
               end if;
            end if;

         when XFER2 =>
            memMstIb.data  <= r.hiword;
            memMstIb.valid <= '1';
            if ( r.done = '1' ) then
               v.state := STATUS;
            else
               v.state := CMD1;
               v.rdy   := '1';
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
               strmMstOb.valid <= memMstOb.valid;
               memRdyOb        <= strmRdyOb;
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
         frameSize    => frameSize
      );

   strmRdyIb <= r.rdy;
   req       <= r.req;

end architecture rtl;
