all: warn gatherfwparams FirmwareConstantsAuto.py

Lan9254ESCPkg.o: Lan9254Pkg.o
Lan9254Pkg.o EvrTxPDOPkg.o:  ESCBasicTypesPkg.o

GatherFwParams.o: EvrTxPDOPkg.o Lan9254ESCPkg.o


FirmwareConstantsAuto.py: gatherfwparams
	./$^ > $@

GHDL=ghdl

VPATH=../hdl

%.o: %.vhd
	$(GHDL) -a $(GHDLOPTS) $<

gatherfwparams: GatherFwParams.o
	$(GHDL) -e $(<:%.o=%)

.PHONY: warn

warn:
	@echo "WARNING: this utility is not complete yet"
