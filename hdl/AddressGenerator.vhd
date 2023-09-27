------------------------------------------------------------------------------
--      Copyright (c) 2022-2023 by Paul Scherrer Institute, Switzerland
--      All rights reserved.
--  Authors: Till Straumann
--  License: PSI HDL Library License, Version 2.0 (see License.txt)
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.IPAddrConfigPkg.all;

entity AddressGenerator is
   generic (
      DEFAULT_MAC_ADDR_G : std_logic_vector(47 downto 0);
      DEFAULT_IP4_ADDR_G : std_logic_vector(31 downto 0);
      DEFAULT_UDP_PORT_G : std_logic_vector(15 downto 0);
      DEVICE_G           : string := "7Series"; -- dont use DNA if empty string
      NUM_CONFIGS_G      : natural
   );
   port (
      clk               : in  std_logic;
      rst               : in  std_logic;

      configs           : in  IPAddrConfigReqArray(NUM_CONFIGS_G - 1 downto 0);
      configAcks        : out IPAddrConfigAckArray(NUM_CONFIGS_G - 1 downto 0);

      addrOut           : out IPAddrConfigReqType
   );
end entity AddressGenerator;

architecture rtl of AddressGenerator is
   signal dna           : std_logic_vector(56 downto 0);
   signal dnaVld        : std_logic  := '0';
   signal dnaAck        : std_logic  := '0';
begin

   GEN_ACK : for ack in configAcks'range generate
      configAcks(ack) <= IP_ADDR_CONFIG_ACK_ASSERT_C;
   end generate GEN_ACK;

   GEN_DNA : if ( DEVICE_G = "7Series" ) generate
      U_DNA : entity work.DeviceDna7
         port map (
            clk      => clk,
            rst      => rst,
            dna      => dna,
            vld      => dnaVld
         );
   end generate GEN_DNA;

   P_GEN_ADDR : process ( clk ) is
   begin
      if ( rising_edge( clk ) ) then
         if ( rst = '1' ) then
            addrOut <=  makeIpAddrConfigReq( DEFAULT_MAC_ADDR_G, DEFAULT_IP4_ADDR_G, DEFAULT_UDP_PORT_G);
            dnaAck  <= '0';
         else
            if ( (not dnaAck and dnaVld) = '1' ) then
               addrOut.macAddr    <= dna(47 downto 0);
               addrOut.macAddr(0) <= '0'; -- clear multicast/mbroadcast bit
               addrOut.macAddr(1) <= '1'; -- locally managed address
               dnaAck             <= '1';
            end if;

            for cfg in configs'range loop
               if ( configs(cfg).macAddrVld = '1' ) then
                  addrOut.macAddr <= configs(cfg).macAddr;
               end if;
               if ( configs(cfg).ip4AddrVld = '1' ) then
                  addrOut.ip4Addr <= configs(cfg).ip4Addr;
               end if;
               if ( configs(cfg).udpPortVld = '1' ) then
                  addrOut.udpPort <= configs(cfg).udpPort;
               end if;
            end loop;
         end if;
      end if;
   end process P_GEN_ADDR;

end architecture rtl;
