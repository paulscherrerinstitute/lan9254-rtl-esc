# Load RUCKUS environment and library
source -quiet $::env(RUCKUS_DIR)/vivado_proc.tcl

exec bash -c "make -C $::DIR_PATH/hdl EEPROMContentPkg.vhd"

# Load local source Code and constraints
foreach f {
  Lan9254Pkg.vhd
  Lan9254ESCPkg.vhd
  EEEmulPkg.vhd
  EEPROMContentPkg.vhd
  Lan9254ESC.vhd
  Lan9254Hbi.vhd
  Lan9254HbiImpl.vhd
  SynchronizerBit.vhd
} {
  loadSource    -path "$::DIR_PATH/hdl/$f"
}


