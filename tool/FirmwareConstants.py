# These parameters must match configuration constants
# and generics in VHDL
# The EEPROM config. data for the lan9254 must also
# be in sync with the firmware (major behaviour and
# logic levels are defined by these settings).

class FirmwareConstants(object):

  @staticmethod
  def EEPROM_CONFIG_DATA_TXT():
    return "91020144000000000000004000000000" # must be correct!

  @staticmethod
  def ESC_SM_LEN( sm ):
    if   sm in [0, 1]:
      return 80
    elif sm in [2, 3]:
      return 128
    else:
      raise ValueError("Invalid SM index")

  @staticmethod
  def ESC_SM_SMA( sm ):
    if   ( 0 == sm ):
      return 0x1000
    elif ( 1 == sm ):
      return 0x1080
    elif ( 2 == sm ):
      return 0x1100
    elif ( 3 == sm ):
      return 0x1180
    else:
      raise ValueError("Invalid SM index")

  @staticmethod
  def ESC_SM_SMC( sm ):
    if   ( 0 == sm ):
      return 0x26
    elif ( 1 == sm ):
      return 0x22
    elif ( 2 == sm ):
      return 0x24
    elif ( 3 == sm ):
      return 0x20
    else:
      raise ValueError("Invalid SM index")

  @staticmethod
  def ESC_SM_MAX_LEN( sm ):
    if   ( 3 == sm ):
      return 512
    elif ( 2 == sm ):
      return 128
    else:
      return ESC_SM_LEN( sm )

  @staticmethod
  def RXMBX_SM():
    return 0

  @staticmethod
  def TXMBX_SM():
    return 1


  @staticmethod
  def RXPDO_SM():
    return 2

  @staticmethod
  def TXPDO_SM():
    return 3

  @staticmethod
  def TXPDO_MAX_NUM_SEGMENTS():
    return 16

  @staticmethod
  def DEVSPECIFIC_CATEGORY_TXT():
    return "1"

  @staticmethod
  def TXPDO_NUM_EVENT_DWORDS():
    return 4

  @staticmethod
  def EEPROM_LAYOUT_VERSION():
    return 1

  @staticmethod
  def EVR_NUM_PULSE_GENS():
    return 4

class HardwareConstants(object):
  @staticmethod
  def EEPROM_SIZE_BYTES():
    return 2048
