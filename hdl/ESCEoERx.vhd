library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.Lan9254Pkg.all;
use work.Lan9254ESCPkg.all;
use work.ESCMbxPkg.all;

entity ESCEoERx is
   port (
      clk         : in  std_logic;
      rst         : in  std_logic;

      mbxMstIb    : in  Lan9254PDOMstType  := LAN9254PDO_MST_INIT_C;
      mbxRdyIb    : out std_logic;

      eoeMstOb    : out Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
      eoeErrOb    : out std_logic;
      eoeTEnOb    : out std_logic; -- frame contains time-stamp
      eoeRdyOb    : in  std_logic := '1'
   );
end entity ESCEoERx;

architecture rtl of ESCEoERx is

   type StateType is (IDLE, HDR, FWD, DROP);

   type RegType is record
      state                   : StateType;
      frameType               : std_logic_vector(3 downto 0);
      framePort               : std_logic_vector(3 downto 0);
      lastFrag                : std_logic;
      timeAppend              : std_logic;
      timeRequest             : std_logic;
      fragNo                  : unsigned(5 downto 0);
      frameOff                : unsigned(5 downto 0);
      frameNo                 : unsigned(3 downto 0);
      eoeErr                  : std_logic;
      drained                 : std_logic;
   end record RegType;

   constant REG_INIT_C        : RegType := (
      state                   => IDLE,
      frameType               => (others => '0'),
      framePort               => (others => '0'),
      lastFrag                => '0',
      timeAppend              => '0',
      timeRequest             => '0',
      fragNo                  => (others => '0'),
      frameOff                => (others => '0'),
      frameNo                 => (others => '0'),
      eoeErr                  => '0',
      drained                 => '1'
   );

   signal r                   : RegType := REG_INIT_C;
   signal rin                 : RegType;

begin

   P_COMB : process ( r, mbxMstIb, eoeRdyOb ) is
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

      C_STATE : case ( r.state ) is

         when IDLE =>
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
                  v.fragNo         := to_unsigned(0, v.fragNo'length);
                  if ( EOE_TYPE_FRAG_C = v.frameType ) then
                     v.state       := HDR;
report "FRAME TYPE FRAG" & toString(v.frameType);
                  else
-- FIXME: handle sending response!
report "UNSUPPORTED EeE FRAME TYPE " & toString(v.frameType);
                     v.state       := DROP;
                     v.drained     := '0';
                  end if;
               end if;
            end if;

         when HDR =>
            if ( ( mbxMstIb.valid and rdy ) = '1' ) then
               if ( mbxMstIb.last = '1' ) then
                  -- too short; drop
                  v.state          := IDLE;
               else
                  v.fragNo         := unsigned(mbxMstIb.data( 5 downto  0));
                  v.frameOff       := unsigned(mbxMstIb.data(11 downto  6));
                  v.frameNo        := unsigned(mbxMstIb.data(15 downto 12));
 --- TODO : CHECK
                  v.state          := FWD;
                  if ( v.fragNo /= r.fragNo ) then
report "Unexpected fragment # " & integer'image(to_integer(v.fragNo)) & " exp " & integer'image(to_integer(r.fragNo));
                     if ( v.fragNo /= 0 ) then
                        v.state  := DROP;
                        v.eoeErr := '1';
                     end if;
                  end if;
                  if ( ( v.fragNo /= 0 ) and ( v.frameNo /= r.frameNo ) ) then
report "Unexpected frame # " & integer'image(to_integer(v.frameNo)) & " exp " & integer'image(to_integer(r.frameNo));
                     v.state  := DROP;
                     v.eoeErr := '1';
                  end if;
               end if;
            end if;
 
         when FWD =>
            m.valid := mbxMstIb.valid;
            rdy     := eoeRdyOb;
            m.last  := r.lastFrag and mbxMstIb.last;
            if ( ( mbxMstIb.valid and eoeRdyOb and mbxMstIb.last ) = '1' ) then
               v.state := IDLE;
            end if;

         when DROP =>
            m.valid := r.eoeErr;
            m.last  := r.eoeErr;
            if ( (r.eoeErr and eoeRdyOb ) = '1' ) then
               v.eoeErr := '0';
            end if;
            if ( ( mbxMstIb.valid and rdy and mbxMstIb.last ) = '1' ) then
               v.drained := '1';
            end if;
            if ( ( v.drained and not v.eoeErr ) = '1' ) then
               v.state := IDLE;
            end if;

      end case C_STATE;

      mbxRdyIb <= rdy;
      eoeMstOb <= m;
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

   eoeErrOb <= r.eoeErr;
   eoeTEnOb <= r.timeAppend;

end architecture rtl;
