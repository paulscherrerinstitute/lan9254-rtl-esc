library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.Lan9254Pkg.all;
use work.Lan9254ESCPkg.all;
use work.EEEmulPkg.all;

entity Lan9254ESC is
   port (
      clk         : in  std_logic;
      rst         : in  std_logic;

      req         : out Lan9254ReqType;
      rep         : in  Lan9254RepType
   );
end entity Lan9254ESC;

architecture rtl of Lan9254ESC is

   type ControllerState is (
      POLL_AL_EVENT,
      READ_AL,
      EEP_EMUL,
      EEP_READ,
      EEP_WRITE,
      EVALUATE_TRANSITION,
      XACT,
      UPDATE_AS,
      CHECK_SM,
      EN_DIS_SM
   );

   -- we list BOOT last so the valid increments in state (except for boot)
   -- are always '1'
   type ESCStateType is (
      INIT,
      PREOP,
      SAFEOP,
      OP,
      BOOT
   );

   type RWXactType is record
      reg      : EcRegType;
      val      : std_logic_vector(31 downto 0);
      rdnwr    : boolean;
   end record RWXactType;

   constant RWXACT_INIT_C : RWXactType := (
      reg      => ( addr => (others => '0'), bena => (others => '0') ),
      val      => ( others => '0' ),
      rdnwr    => true
   );

   function RWXACT(
      constant reg : EcRegType;
      constant val : std_logic_vector := ""
   )
   return RWXactType is
      variable rv    : RWXactType;
   begin
      rv.reg   := reg;
      rv.rdnwr := (val'length = 0);
      rv.val   := (others => '0');
      if ( not rv.rdnwr ) then
         rv.val( val'length - 1 downto 0 ) := val;
      end if;
      return rv;
   end function RWXACT;

   type RWXactArray is array (natural range <>) of RWXactType;

   constant LD_XACT_MAX_C : natural := 3;
   constant XACT_MAX_C    : natural := 2**LD_XACT_MAX_C;

   type RWXactSeqType is record
      seq      : RWXactArray(0 to XACT_MAX_C - 1);
      idx      : unsigned(LD_XACT_MAX_C - 1 downto 0);
      num      : unsigned(LD_XACT_MAX_C - 1 downto 0);
      dly      : unsigned(                3 downto 0); -- FIXME
      don      : boolean;
      ret      : ControllerState;
   end record RWXactSeqType;

   constant RWXACT_SEQ_INIT_C : RWXactSeqType := (
      seq      => (others => RWXACT_INIT_C),
      idx      => (others => '0'),
      num      => (others => '0'),
      dly      => (others => '0'),
      don      => false,
      ret      => POLL_AL_EVENT
   );

   type RegType is record
      state    : ControllerState;
      reqState : ESCStateType;
      errAck   : std_logic;
      curState : ESCStateType;
      errSta   : std_logic;
      alErr    : ESCVal16Type;
      ctlReq   : Lan9254ReqType;
      program  : RWXactSeqType;
      sm23Ena  : std_logic;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state    => POLL_AL_EVENT,
      reqState => INIT,
      errAck   => '0',
      curState => INIT,
      errSta   => '0',
      alErr    => EC_ALER_OK_C,
      ctlReq   => LAN9254REQ_INIT_C,
      program  => RWXACT_SEQ_INIT_C,
      sm23Ena  => '0'
   );

   signal     r    : RegType := REG_INIT_C;
   signal     rin  : RegType; 

   procedure scheduleRegXact(
      variable endp : inout RegType;
      constant prog : in    RWXactArray;
      constant dly  : in    unsigned(3 downto 0) := x"0"  -- FIXME
   ) is
   begin
      endp.program.ret             := endp.state;
      endp.state                   := XACT;
      endp.program.seq(prog'range) := prog;
      endp.program.idx             := (others => '0');
      endp.program.num             := to_unsigned(prog'length - 1, endp.program.num'length);
      endp.program.dly             := dly;
      endp.program.don             := false;
      endp.ctlReq.valid            := '0';
   end procedure scheduleRegXact;

   procedure readReg (
      variable rdOut: inout Lan9254ReqType;
      signal   rdInp: in    Lan9254RepType;
      constant reg  : in    EcRegType;
      constant enbl : in    boolean                      := true
   ) is
   begin
      lan9254HBIRead( rdOut, rdInp, reg.addr, reg.bena, enbl );
   end procedure readReg;

   procedure writeReg(
      variable wrOut: inout Lan9254ReqType;
      signal   wrInp: in    Lan9254RepType;
      constant reg  : in    EcRegType;
      constant wrDat: in    std_logic_vector(31 downto 0);
      constant enbl : in    boolean                       := true
   ) is
   begin
      lan9254HBIWrite( wrOut, wrInp, reg.addr, wrDat, reg.bena, enbl );
   end procedure writeReg;

   function toSlv(constant arg : ESCStateType) return std_logic_vector is
      variable ret : std_logic_vector(3 downto 0);
   begin
      case arg is
         when INIT   => ret := "0001";
         when PREOP  => ret := "0010";
         when BOOT   => ret := "0011";
         when SAFEOP => ret := "0100";
         when OP     => ret := "1000";
      end case;
      return ret;
   end function toSlv;

begin

   P_COMB : process (r, rep) is
      variable v   : RegType;
      variable val : std_logic_vector(31 downto 0);
      variable xct : RWXactType;
   begin
      v             := r;
      v.program.don := false;
      val           := (others => '0');
      xct           := RWXACT_INIT_C;

      C_STATE : case r.state is

         when POLL_AL_EVENT =>
            if ( not r.program.don ) then
               scheduleRegXact( v, ( 0 => RWXACT( EC_REG_AL_EREQ_C ) ) );
            else
               if    ( r.program.seq(0).val(EC_AL_EREQ_CTL_IDX_C) = '1' ) then
                  v.state := READ_AL;
               elsif ( r.program.seq(0).val(EC_AL_EREQ_EEP_IDX_C) = '1' ) then
                  v.state := EEP_EMUL;
               end if;
            end if;

         when READ_AL =>
            -- read AL control reg
            if ( not r.program.don ) then
               scheduleRegXact( v, ( 0 => RWXACT( EC_REG_AL_CTRL_C ) ) );
            else
               v.errAck       := r.program.seq(0).val(4);
               if ( v.errAck = '1' ) then
                  v.errSta := '0';
                  v.errAck := '0';
                  v.alErr  := EC_ALER_OK_C;
               end if;
               case to_integer(unsigned(r.program.seq(0).val(3 downto 0))) is
                  when 1 => v.reqState := INIT; v.errSta := '0'; v.errAck := '0';
                  when 2 => v.reqState := PREOP;
                  when 3 => v.reqState := BOOT;
                  when 4 => v.reqState := SAFEOP;
                  when 8 => v.reqState := OP;
                  when others =>
                     assert false report "Invalid state in AL_CTRL: " & integer'image(to_integer(unsigned(r.program.seq(0).val(3 downto 0)))) severity failure;
                     v.reqState := INIT;
                     v.errSta   := '1';
                     v.alErr    := EC_ALER_UNKNOWNSTATE_C;
               end case;

               if ( v.reqState /= r.reqState or v.errSta /= r.errSta ) then
                  v.state := EVALUATE_TRANSITION;
               end if;
            end if;

         when EVALUATE_TRANSITION =>

            v.state := UPDATE_AS;

            if ( r.reqState = BOOT ) then
               if ( r.curState = INIT or r.curState = BOOT ) then
                  -- retrieve station address # NOT IMPLEMENTED
                  -- start boot mailbox       # NOT IMPLEMENTED
               else
                  if ( r.curState = OP ) then
                     -- stop output           # FIXME
                     v.reqState := SAFEOP;
                  end if;
                  v.errSta := '1';
                  v.alErr  := EC_ALER_INVALIDSTATECHANGE_C;
               end if;
            elsif ( r.curState = BOOT ) then
               if ( r.reqState = INIT ) then
                  -- stop boot mailbox       # NOT IMPLEMENTED
               else
                  -- stop boot mailbox       # SOES doesn't do that -- should we?
                  v.errSta    := '1';
                  v.reqState := PREOP;
                  v.alErr     := EC_ALER_INVALIDSTATECHANGE_C;
               end if;
            elsif ( ESCStateType'pos( r.reqState ) - ESCStateType'pos( r.curState ) >  1 ) then
                  v.errSta    := '1';
                  v.alErr     := EC_ALER_INVALIDSTATECHANGE_C;
            elsif ( ESCStateType'pos( r.reqState ) - ESCStateType'pos( r.curState ) >= 0 ) then
               if ( ( r.reqState = PREOP ) and ( r.curState /= PREOP ) ) then
                  -- start mailbox           # NOT IMPLEMENTED
               elsif ( ( r.reqState = SAFEOP ) ) then
                  v.state := CHECK_SM;
                  -- check SMs               # NOT IMPLEMENTED
                  -- start input             # NOT IMPLEMENTED
                  -- enable SM(2)            # NOT IMPLEMENTED
               elsif ( ( r.reqState = OP ) and ( r.curState /= OP ) ) then
                  -- start output            # NOT IMPLEMENTED
               end if;
            else -- state downshift
               if ( ( r.reqState < OP ) and ( r.curState = OP ) ) then
                  -- stop output             # NOT IMPLEMENTED
               end if;
               if ( ( r.reqState < SAFEOP ) and ( r.curState >= SAFEOP ) ) then
                  -- stop input              # NOT IMPLEMENTED
               end if;
               if ( ( r.reqState < PREOP  ) and ( r.curState >= PREOP  ) ) then
                  -- stop mailbox            # NOT IMPLEMENTED
               end if;
            end if;

         when XACT =>
            xct := r.program.seq(to_integer(r.program.idx));
            if ( xct.rdnwr ) then
               readReg( v.ctlReq, rep, xct.reg );
               if ( ( r.ctlReq.valid and rep.valid ) = '1' ) then
                  v.program.seq(to_integer(r.program.idx)).val := rep.rdata;
               end if;
            else
--report "WRITE " & integer'image(to_integer(unsigned(xct.reg.addr))) & " " & integer'image(to_integer(signed(xct.val)));
               writeReg( v.ctlReq, rep, xct.reg, xct.val );
            end if;
            if ( ( r.ctlReq.valid and rep.valid ) = '1' ) then
               v.ctlReq.valid := '0';
               if ( r.program.idx = r.program.num ) then
                  v.state        := r.program.ret;
                  v.program.don  := true;
               else
                  v.program.idx  := r.program.idx + 1;
               end if;
            end if;

         when UPDATE_AS =>
            report "entering UPDATE_AS";
            if ( not r.program.don ) then
               val(4)          := r.errSta;
               val(3 downto 0) := toSlv( r.reqState );
               scheduleRegXact(
                  v,
                  (
                     0 => RWXACT( EC_REG_AL_STAT_C, val     ),
                     1 => RWXACT( EC_REG_AL_ERRO_C, r.alErr )
                  )
               );
            else
               -- handle state transitions
               report "Transition from " & integer'image(ESCStateType'pos(r.curState)) & " => " & integer'image(ESCStateType'pos(r.reqState));
               v.curState := r.reqState;
               v.state    := POLL_AL_EVENT;
            end if;

         when CHECK_SM =>
            if ( not r.program.don ) then
               scheduleRegXact(
                  v,
                  (
                     0 => RWXACT( EC_REG_SM_PSA_F(2) ),
                     1 => RWXACT( EC_REG_SM_LEN_F(2) ),
                     2 => RWXACT( EC_REG_SM_CTL_F(2) ),
                     3 => RWXACT( EC_REG_SM_ACT_F(2) ),
                     4 => RWXACT( EC_REG_SM_PSA_F(3) ),
                     5 => RWXACT( EC_REG_SM_LEN_F(3) ),
                     6 => RWXACT( EC_REG_SM_CTL_F(3) ),
                     7 => RWXACT( EC_REG_SM_ACT_F(3) )
                  )
               );
            else
               v.state   := EN_DIS_SM;
               v.sm23Ena := '1';
               if (   ( (ESC_SM2_ACT_C or  r.program.seq(3).val(EC_SM_ACT_IDX_C)) = '0'   ) -- deactivated
                   or (    ( (ESC_SM2_ACT_C and r.program.seq(3).val(EC_SM_ACT_IDX_C)) = '1' )
                       and ( ESC_SM2_SMA_C     =  r.program.seq(0).val(ESC_SM2_SMA_C'range) )
                       and ( ESC_SM2_LEN_C     =  r.program.seq(1).val(ESC_SM2_LEN_C'range) )
                       and ( ESC_SM2_SMC_C     =  r.program.seq(2).val(ESC_SM2_SMC_C'range) ) )
               ) then
                  -- PASSED CHECK
               else
report "CHECK SM2 FAILED ACT: " & integer'image(to_integer( unsigned( r.program.seq(3).val ) ))
       & " PSA " & integer'image(to_integer( unsigned( r.program.seq(0).val ) ))
       & " LEN " & integer'image(to_integer( unsigned( r.program.seq(1).val ) ))
       & " CTL " & integer'image(to_integer( unsigned( r.program.seq(2).val ) ))
severity failure;
                  v.sm23Ena  := '0';
                  v.reqState := PREOP;
                  v.errSta   := '1';
                  v.alErr    := EC_ALER_INVALIDOUTPUTSM_C;
               end if;
               if (   ( (ESC_SM3_ACT_C or  r.program.seq(7).val(EC_SM_ACT_IDX_C)) = '0'   ) -- deactivated
                   or (    ( (ESC_SM3_ACT_C and r.program.seq(7).val(EC_SM_ACT_IDX_C)) = '1' )
                       and ( ESC_SM3_SMA_C     =  r.program.seq(4).val(ESC_SM3_SMA_C'range) )
                       and ( ESC_SM3_LEN_C     =  r.program.seq(5).val(ESC_SM3_LEN_C'range) )
                       and ( ESC_SM3_SMC_C     =  r.program.seq(6).val(ESC_SM3_SMC_C'range) ) )
               ) then
                  -- PASSED CHECK
               else
report "CHECK SM3 FAILED" severity failure;
                  if ( v.errSta = '0' ) then
                     v.sm23Ena  := '0';
                     v.reqState := PREOP;
                     v.errSta   := '1';
                     v.alErr    := EC_ALER_INVALIDINPUTSM_C;
                  end if;
               end if;
            end if;

         when EN_DIS_SM =>
            if ( not r.program.don ) then
               val := (0 => r.sm23Ena, others => '0');
               scheduleRegXact(
                  v,
                  (
                     0 => RWXACT( EC_REG_SM_PDI_F(2) ),
                     1 => RWXACT( EC_REG_SM_PDI_F(3) )
                  )
               );
            else
               v.state := UPDATE_AS;               
            end if;

         when EEP_EMUL =>
            if ( not r.program.don ) then
               -- read CSR last; we keep it in the same position;
               -- in case of a READ command it must be written last!
               scheduleRegXact(
                  v,
                  (
                     0 => RWXACT( EC_REG_EEP_DLO_C ),
                     1 => RWXACT( EC_REG_EEP_ADR_C ),
                     2 => RWXACT( EC_REG_EEP_CSR_C )
                  )
               );
            else
               case EE_CMD_GET_F( r.program.seq(2).val ) is
                  when EEPROM_WRITE_C =>
                     writeEEPROMEmul( r.program.seq(1).val, r.program.seq(0).val );
                     v.state := EEP_WRITE;

                  when EEPROM_READ_C | EEPROM_RELD_C  =>
                     readEEPROMEmul( r.program.seq(1).val, v.program.seq(0).val, v.program.seq(1).val );
                     v.state := EEP_READ;

                  when others  =>
                     report "UNSUPPORTED EE EMULATION COMMAND " & integer'image(to_integer(unsigned(r.program.seq(0).val)))
                        severity failure;
               end case;
            end if;

        when EEP_WRITE =>
            if ( not r.program.don ) then
               scheduleRegXact( v, ( 0 => RWXACT( EC_REG_EEP_CSR_C, r.program.seq(2).val ) ) );
            else
               v.state := POLL_AL_EVENT;
            end if;
                     
        when EEP_READ =>
            if ( not r.program.don ) then
--report "EEP_READ CSR" & integer'image(to_integer(signed(r.program.seq(0).val)));
--report "         VLO" & integer'image(to_integer(signed(r.program.seq(1).val)));
--report "         VHI" & integer'image(to_integer(signed(r.program.seq(2).val)));
               -- the EEPROM contents are now in r.program.seq(1/2).val
               scheduleRegXact(
                  v,
                  (
                     0 => RWXACT( EC_REG_EEP_DLO_C, r.program.seq(0).val ),
                     1 => RWXACT( EC_REG_EEP_DHI_C, r.program.seq(1).val ),
                     2 => RWXACT( EC_REG_EEP_CSR_C, r.program.seq(2).val )
                  )
               );
            else
               v.state := POLL_AL_EVENT;
            end if;

      end case C_STATE;

      rin <= v;

   end process P_COMB;

   P_SEQ : process (clk) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            r <= REG_INIT_C;
         else
            r <= rin;
         end if;
      end if;
   end process P_SEQ;

   req <= r.ctlReq;

end architecture rtl;
