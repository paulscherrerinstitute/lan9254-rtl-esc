# Must match the actual hardware on the board
class HardwareConstants(object):
  @staticmethod
  def EEPROM_SIZE_BYTES():
    return 2048

# Several parameters we currently hardcode into the ESI file
class ESIDefaults(object):
  def __init__(self):
    super().__init__()

  @staticmethod
  def VENDOR_ID_TXT():
    return "#x505349"

  @staticmethod
  def VENDOR_NAME_TXT():
    return "Paul Scherrer Institut"

  @staticmethod
  def GROUP_NAME_TXT():
    return "Lan9254"

  @staticmethod
  def GROUP_TYPE_TXT():
    return "Lan9254"

  @staticmethod
  def DEVICE_TYPE_TXT():
    return "Lan9254"

  @staticmethod
  def DEVICE_PRODUCT_CODE_TXT():
    return "0001"

  @staticmethod
  def DEVICE_REVISION_NO_TXT():
    return "0001"

  @staticmethod
  def DEVICE_NAME_TXT():
    return "EcEVR"

  @staticmethod
  def RXPDO_LED_INDEX():
    return 0x2000

  @staticmethod
  def RXPDO_INDEX_TXT():
    return "#x1600"

  @staticmethod
  def TXPDO_INDEX_TXT():
    return "#x1A00"
