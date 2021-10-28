library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

use     work.Lan9254Pkg.all;
use     work.Udp2BusPkg.all;

-- utility to convert Lan9254 bus transactions
-- to 'Udp2Bus' ones. This is mainly because
-- the logic levels used by Lan9254 are configurable
-- but Udp2Bus uses fixed levels (easier on humans)

package Lan9254UdpBusPkt is

   function to_Lan9254ReqType (constant x : in Udp2BusReqType)
   return Lan9254ReqType;

   function to_Udp2BusRepType (constant x : in Lan9254RepType)
   return Udp2BusRepType;

end package Lan9254UdpBusPkt;

package body Lan9254UdpBusPkt is

   function to_Lan9254ReqType (constant x : in Udp2BusReqType)
   return Lan9254ReqType is
      variable v : Lan9254ReqType;
   begin
      v         := LAN9254REQ_INIT_C;
      v.addr    := resize( unsigned(x.dwaddr) & "00", v.addr'length );
      v.data    := x.data;
      v.rdnwr   := x.rdnwr;
      v.be      := (others => not HBI_BE_ACT_C);
      for i in x.be'range loop
         if ( x.be(i) = '1' ) then
            v.be(i) := HBI_BE_ACT_C;
         end if;
      end loop;

      return v;

   end function to_Lan9254ReqType;

   function to_Udp2BusRepType (constant x : in Lan9254RepType)
   return Udp2BusRepType is
      variable v : Udp2BusRepType;
   begin
      v := UDP2BUSREP_INIT_C;
      v.valid := x.valid;
      v.rdata := x.rdata;
      v.berr  := '0';
      for i in x.berr'range loop
         v.berr := v.berr or x.berr(i);
      end loop;
      
      return v;
   end function to_Udp2BusRepType;

end package body Lan9254UdpBusPkt;
