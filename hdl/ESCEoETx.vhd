library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.Lan9254Pkg.all;
use work.ESCMbxPkg.all;

-- Fragment an outbound ethernet frame

entity ESCEoETx is
   generic (
      -- max. mailbox payload size (excl. mailbox header, but including EoE header)
      MAX_FRAGMENT_SIZE_G : natural;
      -- unfortunately, EoE requires the frame size to
      -- be sent in the header; if this information is unknown
      -- then we must store and forward...
      STORE_AND_FWD_G     : boolean;
      -- just for testing the time-stamp stripping of the receiver
      -- NOTE: this doesn't handle the case correctly when adding
      --       the timestamp requires an additional fragmentation!
      --       FOR TESTING ONLY
      TEST_TIME_APPEND_G  : std_logic := '0'
   );
   port (
      clk         : in  std_logic;
      rst         : in  std_logic;

      -- eoeFrameSz is considered 'valid' when the first word
      -- in the eoeMstIb stream is valid. Ignored in store and fwd mode
      eoeFrameSz  : in  unsigned(10 downto 0) := (others => '0');
      eoeMstIb    : in  Lan9254StrmMstType    := LAN9254STRM_MST_INIT_C;
      eoeRdyIb    : out std_logic;

      mbxMstOb    : out Lan9254StrmMstType;
      mbxRdyOb    : in  std_logic             := '1';

      debug       : out std_logic_vector(31 downto 0)
   );
end entity ESCEoETx;

architecture rtl of ESCEoETx is

   constant MAX_FRAME_SIZE_C : natural := 1472; -- per 

   constant NUM_CHUNKS_C     : natural := (MAX_FRAGMENT_SIZE_G - EOE_HDR_SIZE_C)/32;
   constant CHUNK_SIZE_C     : natural := 32*NUM_CHUNKS_C;

   type StateType is ( IDLE, H1, H2, PLD, TS1, TS2 );

   subtype FrameSizeType is unsigned(10 downto 0);
   constant FRAME_SIZE_ZERO_C : FrameSizeType := (others => '0');

   type RegType   is record
      state    : StateType;
      fragNo   : unsigned( 5 downto 0);
      fragOff  : unsigned( 5 downto 0);
      frameNo  : unsigned( 3 downto 0);
      frameSz  : FrameSizeType;
      lstBen   : std_logic_vector(1 downto 0);
      pldCnt   : natural range 0 to CHUNK_SIZE_C - 2;
   end record RegType;

   function idx(constant p : FrameSizeType) return natural is
   begin
      return to_integer(p(p'left downto 1));
   end function idx;

   constant REG_INIT_C : RegType := (
      state    => IDLE,
      fragNo   => (others => '0'),
      fragOff  => (others => '0'),
      frameNo  => (others => '0'),
      frameSz  => FRAME_SIZE_ZERO_C,
      lstBen   => (others => '1'),
      pldCnt   => 0
   );

   signal   r        : RegType                       := REG_INIT_C;
   signal   rin      : RegType;

   signal   totalLen : unsigned(15 downto 0);

   signal   frameSz  : FrameSizeType      := FRAME_SIZE_ZERO_C;
   signal   eoeMst   : Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;

   signal   rdyLoc   : std_logic;

begin

   debug( 7 downto  0) <= std_logic_vector( to_unsigned( r.pldCnt, 8 ) );
   debug(15 downto  8) <= std_logic_vector( r.frameSz(7 downto 0 ) );
   debug(18 downto 16) <= std_logic_vector( to_unsigned( StateType'pos( r.state ), 3 ) );
   debug(19          ) <= r.lstBen(1);
   debug(25 downto 20) <= std_logic_vector( r.fragNo  );
   debug(31 downto 26) <= std_logic_vector( r.fragOff );

   G_NO_STORE : if ( not STORE_AND_FWD_G ) generate
      frameSz  <= eoeFrameSz;
      eoeMst   <= eoeMstIb;
      eoeRdyIb <= rdyLoc;
   end generate G_NO_STORE;

   G_STORE : if ( STORE_AND_FWD_G ) generate

      U_STORE : entity work.StrmFrameBuf
         port map (
            clk       => clk,
            rst       => rst,
            strmMstIb => eoeMstIb,
            strmRdyIb => eoeRdyIb,

            frameSize => frameSz,
            strmMstOb => eoeMst,
            strmRdyOb => rdyLoc
         );

   end generate G_STORE;

   P_COMB : process (r, eoeMst, frameSz, mbxRdyOb) is
      variable v        : RegType;
      variable m        : Lan9254StrmMstType;
      variable rdy      : std_logic;
      constant TS_LEN_C : FrameSizeType := ( 2 => TEST_TIME_APPEND_G, others => '0' );
   begin
      v   := r;
      m   := LAN9254STRM_MST_INIT_C;

      m.usr(MBX_TYP_EOE_C'range) := MBX_TYP_EOE_C;

      rdy := '0';

      case ( r.state ) is

         when IDLE =>
            v.pldCnt   := 0;
            if ( ( eoeMst.valid = '1' ) ) then
               if ( r.fragNo = 0 ) then
                  v.frameSz := frameSz + TS_LEN_C;
               end if;
               v.state   := H1;
            end if;

         when H1  =>
            m.data( 3 downto  0)   := EOE_TYPE_FRAG_C;
            m.data( 7 downto  4)   := (others => '0'); -- port
            if ( ( r.frameSz - (r.fragOff & "00000") ) <= CHUNK_SIZE_C ) then
               m.data(8)           := '1';
            else
               m.data(8)           := '0';
            end if;
            m.data(9)              := TEST_TIME_APPEND_G;
            m.data(15 downto 10)   := (others => '0'); -- other time related flags
            m.valid                := '1';
            m.ben                  := "11";
            if ( mbxRdyOb = '1' ) then
               v.state   := H2;
            end if;

         when H2  =>
            m.data(5 downto 0)     := std_logic_vector( r.fragNo );
            if ( r.fragNo = 0 ) then
               m.data(11 downto 6) := std_logic_vector( resize( shift_right(r.frameSz + 31, 5), 6));
            else
               m.data(11 downto 6) := std_logic_vector( r.fragOff );
            end if;
            m.data(15 downto 12)   := std_logic_vector( r.frameNo );
            m.valid                := '1';
            m.ben                  := "11";

            if ( mbxRdyOb = '1' ) then
               v.state := PLD;
            end if;

         when PLD =>

            rdy     := mbxRdyOb;
            m.data  := eoeMst.data;
            m.valid := eoeMst.valid;
            m.ben   := eoeMst.ben;

            if ( ( mbxRdyOb and eoeMst.valid) = '1' ) then
               if ( ( r.fragOff & "00000" ) + r.pldCnt + 2 >= r.frameSz - TS_LEN_C ) then
                  v.frameNo := r.frameNo + 1;
                  v.fragNo  := (others => '0');
                  v.fragOff := (others => '0');
                  if ( TEST_TIME_APPEND_G = '0' ) then
                     m.last    := '1';
                     v.state   := IDLE;
                  else
                     v.lstBen  := eoeMst.ben;
                     m.ben     := "11";
                     v.state   := TS1;
                     if ( eoeMst.ben(1) = '0' ) then
                        m.data(15 downto 8) := x"EF";
                     end if;
                  end if;
               elsif ( eoeMst.last = '1' ) then
                  -- short AKA aborted frame; we already sent our header with the frame length; try
                  -- to jam the receiver by forcing a new frame
                  m.last    := '1';
                  v.frameNo := r.frameNo + 1;
                  v.fragNo  := (others => '0');
                  v.fragOff := (others => '0');
                  v.state   := IDLE;
               elsif ( r.pldCnt = CHUNK_SIZE_C - 2 ) then -- should we pack the last fragment (make it > 32) ?
                  m.last    := '1';
                  v.fragNo  := r.fragNo + 1;
                  v.state   := IDLE;
                  v.fragOff := r.fragOff + NUM_CHUNKS_C;
               else
                  v.pldCnt  := r.pldCnt + 2;
               end if;
            end if;

         when TS1 =>
            if ( TEST_TIME_APPEND_G = '1' ) then
               if ( r.lstBen(1) = '0' ) then
                  m.data := x"ADBE";
               else
                  m.data := x"BEEF";
               end if;
               m.valid := '1';
               m.ben   := "11";
               if ( mbxRdyOb = '1' ) then
                  v.state := TS2;
               end if;
            end if;

         when TS2 =>
            if ( TEST_TIME_APPEND_G = '1' ) then
               if ( r.lstBen(1) = '0' ) then
                  m.data := x"00DE";
               else
                  m.data := x"DEAD";
               end if;
               m.valid := '1';
               m.ben   := r.lstBen;
               m.last  := '1';
               if ( mbxRdyOb = '1' ) then
                  v.state := IDLE;
               end if;
            end if;


      end case;

      rdyLoc   <= rdy;
      mbxMstOb <= m;
      rin      <= v;
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

end architecture rtl;
