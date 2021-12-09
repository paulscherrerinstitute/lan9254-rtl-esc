# These parameters must match configuration constants
# and generics in VHDL
# The EEPROM config. data for the lan9254 must also
# be in sync with the firmware (major behaviour and
# logic levels are defined by these settings).

class FirmwareConstants(object):

  @classmethod
  def EEPROM_CONFIG_DATA_TXT():
    return "910201440000000000000040" # must be correct!

  @classmethod
  def ESC_SM_LEN( sm ):
    if   sm in [0, 1]:
      return 48
    elif sm in [2, 3]:
      return 128
    else:
      raise ValueError("Invalid SM index")

  @classmethod
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

  @classmethod
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

  @classmethod
  def ESC_SM_MAX_LEN( sm ):
    if ( 3 == sm ):
      return 138
    else:
      return ESC_SM_LEN( sm )

  @classmethod
  def PDO_MAX_NUM_SEGMENTS( sm ):
    return 16

  @classmethod
  def DEVSPECIFIC_CATEGORY_TXT():
    return "1"

  @classmethod
  def PDO_NUM_EVENT_DWORDS():
    return 4

class HardwareConstants(object):
  @classmethod
  def EEPROM_SIZE_BYTES():
    return 2048
