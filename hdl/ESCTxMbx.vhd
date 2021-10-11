library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.Lan9254Pkg.all;
use work.Lan9254ESCPkg.all;
use work.ESCMbxPkg.all;

entity ESCTxMbx is
   port (
      clk             : in  std_logic;
      rst             : in  std_logic;
      mbxRst          : in  std_logic;

      txMBXMst        : in  LAN9254StrmMstType := LAN9254STRM_MST_INIT_C;
      txMBXRdy        : out std_logic;

      req             : out Lan9254ReqType;
      rep             : in  Lan9254RepType    := LAN9254REP_INIT_C;

      ack             : out std_logic;

      txMBXBufHaveBup : out boolean
   );
end entity ESCTxMbx;

architecture rtl of ESCTxMbx is
   constant TXMBX_MAXWORDS_C         : natural := to_integer( unsigned( ESC_SM1_LEN_C ) )/2;
   constant TXMBX_PAYLOAD_MAXWORDS_C : natural := TXMBX_MAXWORDS_C - ( MBX_HDR_SIZE_C / 2 );

   type     StateType is ( IDLE, PROC );

   type     RegType  is record
      state                : StateType;
      ctlReq               : Lan9254ReqType;
      txMBXStrb            : std_logic;
      txMBXLEna            : std_logic;
      txMBXTEna            : std_logic;
      txMBXLen             : unsigned(15 downto 0);
      txMBXWAddr           : natural range 0 to TXMBX_MAXWORDS_C - 1;
      txMBXRdy             : std_logic;
      txMBXReplay          : boolean;
      txMBXLast            : std_logic;
      txMBXMRep            : std_logic; -- FIXME
      txMBXMAck            : std_logic; -- FIXME
      txMBXOverrun         : std_logic;
      beh                  : std_logic;
      ack                  : std_logic;
   end record RegType;

   constant REG_INIT_C      : RegType := (
      state                => IDLE,
      ctlReq               => LAN9254REQ_INIT_C,
      txMBXStrb            => '0',
      txMBXLEna            => '0',
      txMBXTEna            => '0',
      txMBXLen             => (others => '0'),
      txMBXWAddr           =>  0,
      txMBXRdy             => '0',
      txMBXMRep            => '0',
      txMBXMAck            => '0',
      txMBXReplay          => false,
      txMBXLast            => '0',
      txMBXOverrun         => '0',
      beh                  => '1',
      ack                  => '0'
   );

   signal r                : RegType := REG_INIT_C;
   signal rin              : RegType;

   signal     txMBXBufWBEh    : std_logic;
   signal     txMBXBufWEna    : std_logic;
   signal     txMBXBufWRdy    : std_logic;
   signal     txMBXBufRDat    : std_logic_vector(15 downto 0);

begin

   txMBXBufWEna <= ( txMBXMst.valid and r.txMBXRdy and not r.txMBXOverrun ) or r.txMBXStrb;
   txMBXBufWBEh <= ( not r.txMBXRdy ) or txMBXMst.ben(1);

   P_COMB : process ( r, rep, txMBXMst, txMBXBufWRdy, txMBXBufRDat ) is
      variable v : RegType;
   begin
      v := r;

      v.ack := '0';

      C_STATE : case ( r.state ) is
         when IDLE =>


         when PROC =>
            HANDLE_TXMBX : if ( r.txMBXRdy = '1' ) then
               -- this case handles reading the txMBXMst stream into 
               -- the ESCTxMbxBuf buffer memory
               if ( txMBXMst.valid = '1' ) then
                  if ( r.txMBXOverrun = '0' ) then
                     -- stop the input stream until the current word
                     -- has also been written into the LAN9254
                     v.txMBXRdy    := '0';
                     -- remember the 'last' flag
                     v.txMBXLast   := txMBXMst.last;
                     v.ctlReq.be   := HBI_BE_W0_C;
                     -- honor the byte-enable (we look at the hi-byte only)
                     -- this is only relevant for the very last byte. If the
                     -- message is just one byte short of the full mailbox
                     -- capacity then writing one byte beyond the message length
                     -- would trigger the sync-manager and we don't want that
                     -- to happen since we first must write the correct length
                     -- to the message header.
                     -- It also doesn't matter if we write the high-byte to the
                     -- buffer memory -- but the 'be' we set here is later
                     -- used by the HBI write-cycle where it matters (A).
                     if ( txMBXMst.ben(1) = '0' ) then
                        v.ctlReq.be(1) := not HBI_BE_ACT_C;
                     end if;
                     v.beh         := txMBXMst.ben(1);
                  elsif ( txMBXMst.last = '1' ) then
                     -- ERROR RETURN (overrun drained)
                     v.state       := IDLE;
                     v.txMbxReplay := false;
                     v.ack         := '1';
                     v.txMBXRdy    := '0';
                  end if;
               end if;
            elsif ( rep.valid = '1' ) then
               v.ctlReq.valid := '0';
               -- this case is reached after a word has been written to the LAN9254
               v.ctlReq.be    := HBI_BE_W0_C;
               if ( r.txMBXLast = '1' ) then
                  -- the last word has just been written; first we handle the special
                  -- case when the message length is identical with the mailbox capacity.
                  -- If this is true then the sync-manager has just been triggered. Since
                  -- we initially wrote the full-capacity to the header's length field the
                  -- everything is fine and we are left with no more work to do.
                  -- If, OTOH, the message length is just one byte short of the capacity
                  -- then the SM has not been triggered yet and we must proceed like with
                  -- any other message length (write correct length to the header and trigger
                  -- SM by writing the last byte).
                  -- We find out whether the last byte was part of the message or not by
                  -- inspecting the 'beh' flag (note that r.ctlReq.be() has
                  -- been modified for word-aligned access, see lan9254HBIWrite()).
                  -- This is where the information set at point (A) above matters...
                  if ( ( r.txMBXWAddr = TXMBX_MAXWORDS_C - 1 ) and ( r.beh = '1' ) ) then
                        -- message spans full mailbox capacity => ALL DONE
                        v.state       := IDLE;
                        v.txMBXReplay := false;
                  else
                     -- message was shorter than the full capacity. We must write the true
                     -- length to the header and eventually kick the sync-manager
                     if ( ( r.txMBXWAddr /= 0 ) and not r.txMBXReplay ) then
                        -- we get here after the last message word was written to the lan9254
                        -- r.txMBXWAddr therefore contains the correct length of the message
                        -- (in words). We must write twice this value (plus info about the last byte)
                        -- to the message header (nothing to do during a replay since the correct value
                        -- is already in buffer memory). Schedule that for next cycle:
                        -- target address is 0
                        v.txMBXWAddr := 0;
                        -- compute the length
                        if ( r.beh = '1' ) then
                           v.txMBXLen   :=  to_unsigned(r.txMBXWAddr - (MBX_HDR_SIZE_C/2) + 1, v.txMBXLen'length - 1 ) & "0";
                        else
                           v.txMBXLen   :=  to_unsigned(r.txMBXWAddr - (MBX_HDR_SIZE_C/2)    , v.txMBXLen'length - 1 ) & "1";
                        end if;
                        -- enable writing txMBXLen to the header.
                        v.txMBXLEna     := '1';
                     else
                        -- header has been written or we are in a replay (in which case we skip directly here)
                        -- must kick the SM by writing to the last address
                        v.txMBXWAddr := TXMBX_MAXWORDS_C - 1;
                        if ( not r.txMBXReplay ) then
                           -- if we are doing a 'normal' send then issue a write to the last
                           -- word of the ESCTxMbxBuf which will cause it to swap buffers and clear the 'rdy' flag.
                           -- If we are in replay mode then the ESCTxMbxBuf is already in 'not rdy' mode.
                           v.txMBXStrb  := '1';
                        end if;
                     end if;
                  end if;
               elsif ( r.txMBXWAddr = TXMBX_MAXWORDS_C - 1 ) then
                  -- message too long -> DRAIN
                  v.txMBXOverrun := '1';
                  v.txMBXRdy     := '1';
               else
                  -- 'normal' write (i.e., not last word) to the LAN9254 has finished; compute the next memory address
                  if ( r.txMBXWAddr = 0 ) then
                     -- remember length when doing a replay
                     v.txMBXLen := unsigned( txMBXBufRDat );
                  end if;
                  if ( r.txMBXReplay and ( r.txMBXLen +  MBX_HDR_SIZE_C - 4 ) <= ( to_unsigned(r.txMBXWAddr, r.txMBXLen'length - 1) & "0" ) ) then
                     -- if we are in replay mode then use the length information from the header (stored in txMBXLen)
                     -- to raise the 'last' flag.
                     v.txMBXLast := '1';
                  end if;
                  v.txMBXWAddr   := r.txMBXWAddr + 1;
                  if ( ( r.txMBXWAddr >= MBX_HDR_SIZE_C/2 - 1 ) and not r.txMBXReplay ) then
                     -- if we are not in replay mode and beyond the header then
                     -- we are ready to read the next word from the txMBXMst stream
                     -- (and we'll end up in the first branch of this big 'if' statement).
                     v.txMBXRdy := '1';
                  end if;
               end if;
            elsif ( r.txMBXLEna = '0' ) then -- must wait until msg length is written to the buffer
               -- schedule next write to the LAN9254. Note that we always 'write-through' the 
               -- ESCTxMbxBuf buffer memory; i.e,. data are store there (first branch of the 'HANDLE_TXMBX'
               -- statement.
               lan9254HBIWrite(
                  v.ctlReq,
                  rep,
                  std_logic_vector( unsigned(ESC_SM1_SMA_C) + (to_unsigned(r.txMBXWAddr, ESC_SM1_SMA_C'length - 1) & "0") ),
                  x"0000" & txMBXBufRDat,
                  r.ctlReq.be
               );
            end if HANDLE_TXMBX;
      end case C_STATE;

      if ( ( rst = '1' ) or ( ( v.ctlReq.valid = '0' ) and ( mbxRst = '1' ) ) ) then
         v := REG_INIT_C;
      end if;

      rin <= v;

   end process P_COMB;

   req      <= r.ctlReq;
   ack      <= r.ack;
   txMBXRdy <= r.txMBXRdy;

   U_MBX_BUF : entity work.ESCTxMbxBuf
      generic map (
         MBX_NUM_PAYLOAD_WORDS_G => TXMBX_PAYLOAD_MAXWORDS_C
      )
      port map (
         clk         => clk,
         rst         => mbxRst,

         raddr       => r.txMBXWAddr,
         rdat        => txMBXBufRDat,

         tena        => r.txMBXTEna,
         htyp        => txMBXMst.usr(3 downto 0),
         lena        => r.txMBXLEna,
         mlen        => r.txMBXLen,

         wena        => txMBXBufWEna,
         wdat        => txMBXMst.data,
         wrdy        => txMBXBufWRdy,
         waddr       => r.txMBXWAddr,
         wbeh        => txMBXBufWBEh,

         ecMstAck    => r.txMBXMAck,
         ecMstRep    => r.txMBXMRep,
         haveBackup  => txMBXBufHaveBup
      );

end architecture rtl;
