library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.Lan9254Pkg.all;

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
      POLL_AL,
      UPDATE_AS
   );

   type ESCStateType is (
      INIT,
      PREOP,
      BOOT,
      SAFEOP,
      OP
   );

   type RegType is record
      state    : ControllerState;
      reqState : ESCStateType;
      errAck   : std_logic;
      curState : ESCStateType;
      errSta   : std_logic;
      ctlReq   : Lan9254ReqType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state    => POLL_AL,
      reqState => INIT,
      errAck   => '0',
      curState => INIT,
      errSta   => '0',
      ctlReq   => LAN9254REQ_INIT_C
   );

   constant EC_REG_AL_CTRL_C : EcRegType := (
      addr     => x"0120",
      bena     => "0011"
   );

   constant EC_REG_AL_STAT_C : EcRegType := (
      addr     => x"0130",
      bena     => "0011"
   );

   signal     r    : RegType := REG_INIT_C;
   signal     rin  : RegType; 

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
   begin
      v   := r;

      case r.state is
         when POLL_AL =>
            -- poll AL control reg
            if ( r.ctlReq.valid = '0' ) then
               readReg( v.ctlReq, rep, EC_REG_AL_CTRL_C );
            elsif ( rep.valid = '1' ) then
               v.ctlReq.valid := '0';
               v.errAck       := rep.rdata(4);
               if ( v.errAck = '1' ) then
                  v.errSta := '0';
                  v.errAck := '0';
               end if;
               case to_integer(unsigned(rep.rdata(3 downto 0))) is
                  when 1 => v.reqState := INIT; v.errSta := '0'; v.errAck := '0';
                  when 2 => v.reqState := PREOP;
                  when 3 => v.reqState := BOOT;
                  when 4 => v.reqState := SAFEOP;
                  when 8 => v.reqState := OP;
                  when others =>
                     assert false report "Invalid state in AL_CTRL" severity error;
                     v.reqState := INIT;
                     v.errSta   := '1';
               end case;

               if ( v.reqState /= r.reqState or v.errSta /= r.errSta ) then
                  v.state := UPDATE_AS;
               end if;
            end if;

         when UPDATE_AS =>
            if ( v.ctlReq.valid = '0' ) then
               val             := (others => '0');
               val(4)          := r.errSta;
               val(3 downto 0) := toSlv( r.reqState );
               writeReg( v.ctlReq, rep, EC_REG_AL_STAT_C, val );
            elsif ( rep.valid = '1' ) then
               v.ctlReq.valid := '0';
               -- handle state transitions
               report "Transition from " & integer'image(ESCStateType'pos(r.curState)) & " => " & integer'image(ESCStateType'pos(r.reqState));
               v.curState := v.reqState;
               v.state    := POLL_AL;
            end if;

      end case;

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
