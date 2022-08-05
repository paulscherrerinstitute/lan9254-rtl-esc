# create I2c programming sequence

class I2cProg:
  def __init__(self):
    self.reset()

  def reset(self):
    self._p = bytearray()

  I2C_WRITE = 0

  I2C_BUSNO_MIN = 0
  I2C_BUSNO_MAX = 1

  def append(self, i2cAddr, regOff, data, i2cBusNo = 1):
    if ( not isinstance(i2cAddr, int) or i2cAddr > 0x7e ):
      raise RuntimeError("Invalid i2c address")
    # regOff is a convenience; offsets > 255 (multi-bytes) must
    # be encoded by the user and supplied as part of the data
    ba = bytearray()
    if ( not regOff is None ):
      if ( not isinstance(regOff, int) or regOff > 255 or regOff < 0 ):
        raise RuntimeError("Invalid register offset (must be 0 <= off <= 255")
      ba.extend([regOff]) # raises if regOff > 255
    if ( i2cBusNo < self.I2C_BUSNO_MIN or i2cBusNo > self.I2C_BUSNO_MAX ): 
      raise RuntimeError("I2c bus number out of range")
    if ( isinstance(data,int) ):
      ba.extend([data])   # raises if data > 255
    elif ( isinstance(data, list) or isinstance(data, bytearray) ):
      ba.extend(data) # should raise if there is anyting 
    else:
      raise RuntimeError("data must be a single number, a bytearray or a list")
    if ( len(ba) > 16 ):
      raise RuntimeError("max. length of program (including regOff) is 16")
    if ( len(ba) < 1 ):
      raise RuntimeError("min. length of program (including regOff) is 1")
    # append
    self._p.extend( [(i2cAddr<<1) | self.I2C_WRITE] )
    # encode upper byte
    self._p.extend( [ (i2cBusNo << 4) | (len(ba) - 1) ] ) 
    # append data
    self._p.extend( ba )

  def getProg(self):
    rv = self._p.copy()
    # END marker
    rv.extend([0xff])
    # PAD to even length
    if ( (len(rv) & 1) != 0 ):
      rv.extend([0xff])
    return rv
