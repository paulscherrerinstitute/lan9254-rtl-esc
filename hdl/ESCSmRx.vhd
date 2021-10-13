library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.Lan9254Pkg.all;
use work.Lan9254ESCPkg.all;

-- state machine to receive data from a SM

-- NOTES:
-- * on the cycle after ACK the read request 'req.valid' becomes pending
--   and the first read will remove the interrupt condition.
-- * This module assumes the user muxes the HBI interface directly to
--   us. I.e., we take care of byte-lane adjustment for word-aligned access.

entity ESCSmRx is
   generic (
      SM_SMA_G       : unsigned(15 downto 0);
      SM_LEN_G       : unsigned(15 downto 0)
   );
   port (
      clk            : in  std_logic;
      rst            : in  std_logic;

      trg            : in  std_logic;
      len            : in  unsigned(15 downto 0);
      typ            : in  std_logic_vector(3 downto 0) := (others => '0');

      rxPDOMst       : out Lan9254PDOMstType;
      rxPDORdy       : in  std_logic;

      req            : out Lan9254ReqType;
      rep            : in  Lan9254RepType;

      debug          : out std_logic_vector(2 downto 0);

      stats          : out StatCounterArray(0 downto 0)
   );
end entity ESCSmRx;

architecture rtl of ESCSmRx is

   constant SM_END_ADDR_C  : Lan9254ByteAddrType := resize(SM_LEN_G - 1, Lan9254ByteAddrType'length);

   type StateType is ( IDLE, PROC, SM_RX_RELEASE );

   type RegType is record
      state           : StateType;
      rxStrm          : Lan9254PDOMstType;
      rxStrmEndAddr   : Lan9254ByteAddrType;
      ctlReq          : Lan9254ReqType;
      decim           : natural range 0 to 255;
      stalled         : natural range 0 to 255;
      numFrames       : StatCounterType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state           => IDLE,
      rxStrm          => LAN9254PDO_MST_INIT_C,
      rxStrmEndAddr   => (others => '0'),
      ctlReq          => LAN9254REQ_INIT_C,
      decim           => 0,
      stalled         => 0,
      numFrames       => STAT_COUNTER_INIT_C
   );

   function toWordAddr(constant a : unsigned) return Lan9254WordAddrType is
      variable v : Lan9254WordAddrType;
   begin
      v := resize( a( a'left downto 1 ), v'length );
      return v;
   end function toWordAddr;

   function toByteAddr(constant a : unsigned) return Lan9254ByteAddrType is
      variable v : Lan9254ByteAddrType;
   begin
      v := resize( a, v'length );
      return v;
   end function toByteAddr;

   function rxStreamEnd(constant r : RegType)
   return boolean is
   begin
      return r.rxStrm.wrdAddr = r.rxStrmEndAddr(r.rxStrmEndAddr'left downto 1);
   end function rxStreamEnd;

   procedure rxStreamSetupAndRead(
      variable v : inout RegType;
      signal   r : in    Lan9254RepType
   ) is
      variable be : std_logic_vector(3  downto 0);
      variable a  : std_logic_vector(15 downto 0);
   begin
      v              := v;
      v.rxStrm.ben   := "11";
      v.rxStrm.last  := '0';
      be             := HBI_BE_W0_C;

      if ( rxStreamEnd( v ) ) then
         v.rxStrm.last := '1';
         if ( v.rxStrmEndAddr(0) = '0' ) then
            v.rxStrm.ben(1) := '0';
            be              := HBI_BE_B0_C;
         end if;
      end if;

      a := std_logic_vector(SM_SMA_G + resize(v.rxStrm.wrdAddr & "0", a'length));
      lan9254HBIRead( v.ctlReq, r, a, be );
   end procedure rxStreamSetupAndRead;

   signal    r        : RegType := REG_INIT_C;
   signal    rin      : RegType;

   signal    is_stalled : std_logic;
  
begin

   P_COMB : process ( r, trg, len, typ, rxPDORdy, rep ) is
      variable v : RegType;
   begin
      v         := r;

      v.stalled := 0;
      if ( r.stalled > 50 ) then
         is_stalled <= '1';
      else
         is_stalled <= '0';
      end if;

      case ( r.state ) is

         when IDLE =>

            if ( trg = '1' ) then 
               v.rxStrmEndAddr          := toByteAddr( len - 1 );
               v.rxStrm.usr(3 downto 0) := typ;
               v.rxStrm.wrdAddr         := (others => '0');
               v.state                  := PROC;
               -- read cannot have completed at this point so we don't need to
               -- check rep.valid
               rxStreamSetupAndRead( v, rep );
            end if;

         when PROC =>

            if ( r.rxStrm.valid = '1' ) then
               -- write to RXPDO pending
               if ( rxPDORdy = '1' ) then
if ( r.decim = 0 ) then
report "STREAM_RX " & toString(std_logic_vector(r.rxStrm.wrdAddr)) & " LST: " & std_logic'image(r.rxStrm.last) & " BEN " & toString(r.rxStrm.ben) & " DAT " & toString(r.rxStrm.data);
v.decim := 200;
else
v.decim := r.decim - 1;
end if;
                  -- write to RXPDO complete
                  v.rxStrm.valid := '0';
                  if ( r.rxStrm.last = '1' ) then
                     -- last write completed; we are done
                     v.numFrames := r.numFrames + 1;
                     if ( r.rxStrmEndAddr /= SM_END_ADDR_C ) then
                        -- if we read less than the SM-covered area then
                        -- we must read the last byte to release the SM.
                        v.state  := SM_RX_RELEASE;
                     else
                        v.state  := IDLE;
                     end if;
                  else
                     -- next word
                     v.rxStrm.wrdAddr := r.rxStrm.wrdAddr + 1;
                  end if;
               else
                  if ( r.stalled < 255 ) then
                     v.stalled := r.stalled + 1;
                  end if;
               end if;
            else
               -- RXPDO write not onging and lan9254 register read not done
               -- => initiate next lan9254 register read operation and/or wait
               --    for completion
               rxStreamSetupAndRead( v, rep );
               if( rep.valid = '1' ) then
                  -- read from lan9254 complete; initiate write to RXPDO interface
                  v.rxStrm.data  := v.ctlReq.data(15 downto 0);
                  v.rxStrm.valid := '1';
               end if;
            end if;

      when SM_RX_RELEASE =>

         lan9254HBIRead( v.ctlReq, rep, std_logic_vector(SM_SMA_G + SM_END_ADDR_C), HBI_BE_B0_C );
         if ( '1' = rep.valid ) then
            v.state        := IDLE;
         end if;

      end case;

      rin     <= v;
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

   
   req      <= r.ctlReq;
   rxPDOMst <= r.rxStrm;

   debug(1 downto 0) <= std_logic_vector( to_unsigned( StateType'pos( r.state ), 2 ) );
   debug(2)          <= is_stalled;

   stats(0)          <= r.numFrames;

end architecture rtl;
