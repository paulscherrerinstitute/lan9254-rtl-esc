##############################################################################
##      Copyright (c) 2022#2023 by Paul Scherrer Institute, Switzerland
##      All rights reserved.
##  Authors: Till Straumann
##  License: GNU GPLv2 or later
##############################################################################

from ClockDriver import ClockDriver

class VersaClock6Driver( ClockDriver ):
  def __init__(self, i2cAddr = 0x6a, i2cBus = 1):
    super().__init__()
    self._fbDiv   = 7*16 # default
    self._fRef    = 25.0
    # for now we leave the loop alone
    # at the power-up defaults and just
    # use the output divider
    self._vcoFreq = self._fRef * self._fbDiv
    self._i2cAddr = i2cAddr
    self._i2cBus  = i2cBus

  @property
  def freqMHzLow(self):
    return self._vcoFreq/2/2**12

  @property
  def freqMHzHigh(self):
    return 350.0

  def _computeOutDiv(self, f):
    div = int(round( self._vcoFreq/f/2.0 * 2**24 ) )
    intDiv  = int( div//(1<<24) )
    fracDiv = div % (1<<24)
    if intDiv >= (1<<12):
      raise RuntimeError("Invalid integer divisor??")
    if fracDiv >= (1<<24):
      print("Warning: fractional divider rounded down")
      fracDiv = (1<<24) - 1
    return intDiv, fracDiv

  @property
  def name(self):
    return "VersaClock6"

  def _writeReg(self, off, values):
    d = [ (self._i2cAddr << 1) | 0 ]     # i2c write
    l = 1 + len(values)                  # how many bytes are written (including offset)
    cmd = (self._i2cBus  << 4) | (l - 1) # 2nd command byte (for programmer in firmware)
    d.append( cmd    )
    d.append( off    )
    d.extend( values )
    return bytearray(d)

  def _setOutputDivider(self, freqMHz, out=3):
    intDiv, fracDiv = self._computeOutDiv( self.acceptable( freqMHz ) )
    divCtrlReg = 0x21 + (out - 1)*0x10
    fracDivReg = 0x22 + (out - 1)*0x10
    intDivReg  = 0x2D + (out - 1)*0x10
    outCtrlReg = 0x60 + (out - 1)*2

    # since divider control and fractional divider registers are
    # contiguous we can write them in one go
    d = bytearray(5)
    d[0] = 0x81 # deassert reset and enable divider
    # fractional divider
    v = (fracDiv << 2) # lowest bits disable spread-spectrum
    for i in range(4, 0, -1):
      d[i] = (v & 0xff)
      v  >>= 8
    prg = bytearray()
    prg.extend( self._writeReg( divCtrlReg, d ) )
    # integer divider
    d = bytearray(2)
    v = (intDiv << 4) # that's how the value is arranged in the registers
    for i in range(1,-1,-1):
      d[i] = (v & 0xff)
      v  <<= 8
    prg.extend( self._writeReg( intDivReg, d ) )
    #
    d = bytearray()
    v  = (3<<5) # select LVDS
    v |= (0<<3) # 1.8V drive
    v |= 3      # normal slew rate
    d.append(v)
    v  = 0x01   # enable output
    d.append(v)
    prg.extend( self._writeReg( outCtrlReg, d ) )
    return prg

  def disassemble(self, prg):
    ip      = 0
    fracDiv = 0
    intDiv  = 0
    outf    = -1
    outi    = -1
    while ip < len(prg):
      if ( prg[ip] == 0xff or prg[ip] == 0x00 ):
         break
      cmdl    = (prg[ip+1] & 0xf) + 1
      print("ip, cmdl", ip, cmdl)
      reg     = prg[ip+2]
      if   reg in [0x21, 0x31, 0x41, 0x51]:
        outf    = ((reg - 0x20) >> 4) + 1
        for i in range(4,8):
          fracDiv = (fracDiv<<8) | prg[ip + i]
        fracDiv >>= 2
        print("Fractional divisor (out {:d}): {:g}".format(outf,fracDiv/2.0**24))
      elif reg in [0x2D, 0x3D, 0x4D, 0x5D]:
        outi    = ((reg - 0x20) >> 4) + 1
        for i in range(3,5):
          intDiv = (intDiv<<8) | prg[ip + i]
        intDiv >>= 4
        print("Integer divisor (out {:d}): {:d}".format(outf,intDiv))
      ip += cmdl + 2 # i2c addr/rw + cmd 2 byte
    if ( outi != outf ):
      raise ValueError("Disassembly failed - different outputs for integer and fractional divisors")
    if ( outi < 1 or outf < 1 ):
      raise ValueError("Disassembly failed - invalid outputs")
    f = self._vcoFreq / (intDiv + fracDiv/2.0**24) / 2.0
    print("Output {:d} programmed for {:8.6f}MHz".format(outf, f))


  def mkInitProg(self, freqMHz):
    return self._setOutputDivider( freqMHz )

ClockDriver.registerDriver( VersaClock6Driver() )
