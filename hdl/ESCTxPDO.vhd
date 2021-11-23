library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.ESCBasicTypesPkg.all;
use work.Lan9254Pkg.all;
use work.Lan9254ESCPkg.all;

entity ESCTxPDO is
   generic (
      TXPDO_BURST_MAX_G         : natural :=  8; -- HBI bus cycles
      TXPDO_BURST_GAP_G         : natural := 10; -- clock cycles
      TXPDO_UPDATE_DECIMATION_G : natural        -- clock cycles
   );
   port (
      clk         : in  std_logic;
      rst         : in  std_logic;
      stop        : in  std_logic; -- reset but wait for HBI access to terminate

      smLen       : in  ESCVal16Type      := ESC_SM3_LEN_C;
      cfgVld      : in  std_logic         := '1';
      cfgAck      : out std_logic;

      txPDOMst    : in  Lan9254PDOMstType := LAN9254PDO_MST_INIT_C;
      txPDORdy    : out std_logic;

      req         : out Lan9254ReqType;
      rep         : in  Lan9254RepType    := LAN9254REP_INIT_C
   );
end entity ESCTxPDO;

architecture rtl of ESCTxPDO is

   function min(a,b : natural) return natural is
   begin
      if ( a < b ) then return a; else return b; end if;
   end function min;

   constant TXPDO_BURST_MAX_C : natural := min( TXPDO_BURST_MAX_G, TXPDO_UPDATE_DECIMATION_G );

   type StateType is ( CONFIG, IDLE, PROC );

   type RegType is record
      state                : StateType;
      ctlReq               : Lan9254ReqType;
      smLenOdd             : boolean;
      endWaddr             : unsigned(txPDOMst.wrdAddr'range);
      txPDORdy             : std_logic;
      txPDOBst             : natural range 0 to TXPDO_BURST_MAX_C;
      txPDOSnt             : natural range 0 to (to_integer(unsigned(ESC_SM3_LEN_C)) - 1)/2;
      txPDODcm             : natural range 0 to TXPDO_UPDATE_DECIMATION_G;
      decim                : natural range 0 to 500;
      cfgAck               : std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state                => CONFIG,
      ctlReq               => LAN9254REQ_INIT_C,
      smLenOdd             => false,
      endWaddr             => (others => '0'),
      txPDORdy             => '0',
      txPDOBst             => 0,
      txPDOSnt             => 0,
      txPDODcm             => 0,
      decim                => 0,
      cfgAck               => '0'
   );

   signal       r          : RegType := REG_INIT_C;
   signal       rin        : RegType;

begin

   P_COMB : process ( r, txPDOMst, rep, rst, stop, smLen, cfgVld ) is
      variable v : RegType;
   begin
      v     := r;

      if ( r.txPDODcm > 0 ) then
         v.txPDODcm := r.txPDODcm - 1;
      end if;

      case ( r.state ) is
         when CONFIG =>
            if ( r.cfgAck = '0' ) then
               v.cfgAck   := '1';
            elsif ( cfgVld = '1' ) then
               v.cfgAck   := '0';
               v.smLenOdd := (smLen(0) = '1' );
               v.endWaddr := resize( shift_right( unsigned(smLen) - 1, 1 ), v.endWaddr'length );
               v.state    := IDLE;
            end if;

         when IDLE =>
            if ( r.txPDODcm = 0 ) then
               v.txPDORdy := '1';
               v.state    := PROC;
               v.txPDOBst := TXPDO_BURST_MAX_C;
            end if;

         when PROC =>
            if ( r.txPDORdy = '1' ) then

               -- read from TXPDO master pending
               if ( txPDOMst.valid  = '1' ) then
                  v.txPDORdy := '0';

if ( r.decim = 0 ) then
report "UPDATE_TXPDO " & toString(std_logic_vector(txPDOMst.wrdAddr)) & " LST: " & std_logic'image(txPDOMst.last) & " BEN " & toString(txPDOMst.ben) & " DAT " & toString(txPDOMst.data);
v.decim := 20;
else
v.decim := r.decim - 1;
end if;

                  if ( txPDOMst.wrdAddr <= r.endWaddr ) then
                     v.ctlReq.addr := (txPDOMst.wrdAddr & "0") + unsigned(ESC_SM3_SMA_C(v.ctlReq.addr'range));
                     v.ctlReq.data := ( x"0000" & txPDOMst.data );
                     v.ctlReq.be   := HBI_BE_W0_C;

                     if ( txPDOMst.ben(0) = '0' ) then
                        v.ctlReq.be(0) := not HBI_BE_ACT_C;
                     end if;

                     -- if last byte make sure proper byte-enable is deasserted
                     if (    ( txPDOMst.ben(1) = '0'       )
                          or (    ( r.smLenOdd       )
                              and ( txPDOMst.wrdAddr = r.endWaddr )
                             )
                        ) then
                        v.ctlReq.be(1) := not HBI_BE_ACT_C;
                     end if;

                     -- => initiate lan9254 register write operation
                     lan9254HBIWrite( v.ctlReq, rep );

                  else 
                     -- illegal address; drop
                     v.txPDORdy := '1';
                  end if;
               else
                  -- nothing to send ATM
               end if;
            elsif ( rep.valid = '1' ) then
               -- write to lan9254 done
               v.ctlReq.valid := '0';

               if ( r.txPDOBst = 0 ) then
                  v.state    := IDLE;
                  v.txPDODcm := TXPDO_BURST_GAP_G;
               else
                  v.txPDORdy := '1';
                  v.txPDOBst := r.txPDOBst - 1;
               end if;
               if ( r.txPDOSnt = to_integer( r.endWaddr ) ) then
                  v.txPDOSnt := 0;
                  v.txPDODcm := TXPDO_UPDATE_DECIMATION_G;
                  v.state    := IDLE;
               else
                  v.txPDOSnt := r.txPDOSnt + 1;
               end if;
            end if;
      end case;

      if ( ( rst or ( not r.ctlReq.valid and stop ) ) = '1' ) then
         v := REG_INIT_C;
      end if;

      rin   <= v;
   end process P_COMB;

   P_SEQ : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         r <= rin;
      end if;
   end process P_SEQ;

   req      <= r.ctlReq;
   txPDORdy <= r.txPDORdy;
   cfgAck   <= r.cfgAck;

end architecture rtl;
