BEGIN {
  print("library ieee;")
  print("use ieee.std_logic_1164.all;")
  print("-- AUTOMATICALLY GENERATED; DONT EDIT")
  print("package EEPROMContentPkg is")
  print("type EEPROMArray is array (natural range <>) of std_logic_vector(15 downto 0);")
  print("constant EEPROM_INIT_C : EEPROMArray := (")
  COMMA=""
}
END {
  print(");")
  print("end package EEPROMContentPkg;")
}
{
  printf("%s%d/2 => x\"%04x\"\n", COMMA, $1, $2)
  COMMA=", "
}
