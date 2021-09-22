BEGIN {
  print("library ieee;")
  print("use ieee.std_logic_1164.all;")
  print("-- AUTOMATICALLY GENERATED; DONT EDIT")
  print("package EEPROMContentPkg is")
  print("type EEPROMArray is array (natural range <>) of std_logic_vector(15 downto 0);")
  print("constant EEPROM_INIT_C : EEPROMArray := (")
}
END {
  # pad with zeroes; since emulation always reads in blocks of 8 bytes
  # it sometimes reads beyond the end...
  printf("      %d/2 => x\"0000\",\n", LSTA + 2);
  printf("      %d/2 => x\"0000\",\n", LSTA + 4);
  printf("      %d/2 => x\"0000\"\n",  LSTA + 6);
  printf(");\n")
  printf("end package EEPROMContentPkg;\n")
}
{
  printf("      %d/2 => x\"%04x\",\n", $1, $2)
  LSTA=$1
}
