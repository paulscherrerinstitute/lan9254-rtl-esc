# Load RUCKUS environment and library
source -quiet $::env(RUCKUS_DIR)/vivado_proc.tcl

exec bash -c "make -C $::DIR_PATH/hdl EEPROMContentPkg.vhd"

# Load local source Code and constraints
foreach f {
EEEmulPkg.vhd
EEPROMContentPkg.vhd
ESCEoERx.vhd
ESCEoETx.vhd
ESCMbxPkg.vhd
ESCRxMbxMux.vhd
ESCSmRx.vhd
ESCTxMbxBuf.vhd
ESCTxMbxErr.vhd
ESCTxMbxMux.vhd
ESCTxPDO.vhd
IPV4ChkSum.vhd
Lan9254ESCPkg.vhd
Lan9254ESCrun.vhd
Lan9254ESC.vhd
Lan9254ESCWrapper.vhd
Lan9254HbiImpl.vhd
Lan9254Hbi.vhd
Lan9254Pkg.vhd
MicroUDPPkg.vhd
MicroUDPRx.vhd
MicroUDPTx.vhd
SynchronizerBit.vhd  Lan9254Pkg.vhd
} {
  loadSource    -path "$::DIR_PATH/hdl/$f"
}



