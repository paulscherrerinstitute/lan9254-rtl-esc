library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.Lan9254Pkg.all;
use work.ESCMbxPkg.EOE_MAX_FRAME_SIZE_C;

-- Buffer a frame
-- NOTE: produces incorrect results for frames of length 1 if strmRdyOb = '1' 
--       on the first cycle strmMstOb.valid = '1'. This is because there is
--       a two cycle delay (1 for writing, 1 for reading). Not a problem
--       for longer frames; if frames of length 1 are to be expected then
--       strmMstOb.valid must be blanked for 1 cycle when a short frame
--       is received.

entity StrmFrameBuf is
   port (
      clk         : in  std_logic;
      rst         : in  std_logic;

      restore     : in  std_logic             := '0';

      strmMstIb   : in  Lan9254StrmMstType    := LAN9254STRM_MST_INIT_C;
      strmRdyIb   : out std_logic;

      -- frameSz is considered 'valid' when strmMstOb.valid = '1'
      frameSize   : out unsigned(10 downto 0) := (others => '0');
      strmMstOb   : out Lan9254StrmMstType    := LAN9254STRM_MST_INIT_C;
      strmRdyOb   : in  std_logic             := '1'
   );
end entity StrmFrameBuf;

architecture rtl of StrmFrameBuf is

   subtype  FrameSizeType     is unsigned(10 downto 0);
   constant FRAME_SIZE_ZERO_C :  FrameSizeType := (others => '0');

   function idx(constant p : FrameSizeType) return natural is
   begin
      return to_integer(p(p'left downto 1));
   end function idx;

   type MemArray is array (0 to (EOE_MAX_FRAME_SIZE_C + 1)/2 - 1) of std_logic_vector(15 downto 0);      

   attribute RAM_STYLE        : string;


   signal   frameSz           : FrameSizeType      := FRAME_SIZE_ZERO_C;
   signal   frameEnd          : FrameSizeType      := FRAME_SIZE_ZERO_C;
   signal   frameSzPrev       : FrameSizeType      := FRAME_SIZE_ZERO_C;
   signal   frameEndPrev      : FrameSizeType      := FRAME_SIZE_ZERO_C;
   signal   strmMst           : Lan9254StrmMstType := LAN9254STRM_MST_INIT_C;
   signal   canRestore        : boolean            := false;

   signal   mem               : MemArray := (others => (others => '0'));
   attribute RAM_STYLE of mem : signal is "block";

   signal rdp                 : FrameSizeType := FRAME_SIZE_ZERO_C;
   signal nrp                 : FrameSizeType := FRAME_SIZE_ZERO_C;

begin

   nrp            <= rdp + 2;
   strmRdyIb      <= not strmMst.valid;
   strmMst.ben(0) <= '1';

   P_RAMRD : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( ( strmMst.valid and strmRdyOb ) = '1' ) then
            strmMst.data      <= mem( idx(nrp) );
            if ( ( nrp >= frameEnd ) ) then
               strmMst.ben(1) <= not frameSz(0);
               strmMst.last   <= '1';
            else
               strmMst.ben(1) <= '1';
               strmMst.last   <= '0';
            end if;
         else
            strmMst.data      <= mem( idx(rdp) );
            if ( ( rdp >= frameEnd ) ) then
               strmMst.ben(1) <= not frameSz(0);
               strmMst.last   <= '1';
            else
               strmMst.ben(1) <= '1';
               strmMst.last   <= '0';
            end if;
         end if;
      end if;
   end process P_RAMRD;

   P_RDWR : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            strmMst.valid <= '0';
            frameSzPrev  <= FRAME_SIZE_ZERO_C;
            frameEndPrev <= FRAME_SIZE_ZERO_C;
            frameSz      <= FRAME_SIZE_ZERO_C;
            frameEnd     <= FRAME_SIZE_ZERO_C;
            rdp          <= FRAME_SIZE_ZERO_C;
            canRestore   <= false;
         else
            if ( strmMst.valid = '0' ) then --write
               rdp <= FRAME_SIZE_ZERO_C;
               if ( strmMstIb.valid = '1' ) then
                  canRestore            <= false;
                  mem( idx( frameSz ) ) <= strmMstIb.data;
                  frameEnd              <= frameSz;
                  if ( strmMstIb.last = '1' ) then
                     strmMst.valid      <= '1';
                  end if;
                  if ( frameSz < EOE_MAX_FRAME_SIZE_C - 1 ) then
                     if ( ( strmMstIb.last = '1' ) and ( strmMstIb.ben(1) = '0' ) ) then
                        frameSz <= frameSz + 1;
                     else
                        frameSz <= frameSz + 2;
                     end if;
                  end if;
               elsif ( ( restore = '1' ) and canRestore ) then
                  strmMst.valid <= '1';
                  canRestore    <= false;
                  frameSz       <= frameSzPrev;
                  frameEnd      <= frameEndPrev;
               end if;
            else -- readout
               if ( strmRdyOb = '1' ) then
                  if ( strmMst.last = '1' ) then
                     strmMst.valid <= '0';
                     frameSzPrev   <= frameSz;
                     frameSz       <= FRAME_SIZE_ZERO_C;
                     frameEndPrev  <= frameEnd;
                     frameEnd      <= FRAME_SIZE_ZERO_C;
                     canRestore    <= true;
                  else
                     rdp           <= nrp;
                  end if;
               end if;
            end if;
         end if;
      end if;
   end process P_RDWR;

   frameSize <= frameSz;
   strmMstOb <= strmMst;

end architecture rtl;
