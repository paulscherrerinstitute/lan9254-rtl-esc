##############################################################################
##      Copyright (c) 2022#2023 by Paul Scherrer Institute, Switzerland
##      All rights reserved.
##  Authors: Till Straumann
##  License: GNU GPLv2 or later
##############################################################################

# These parameters must match configuration constants
# and generics in VHDL
# The EEPROM config. Data for the lan9254 must also
# be in sync with the firmware (major behaviour and
# logic levels are defined by these settings).
from FirmwareConstantsAuto import *

class FirmwareConstants(object):

  @staticmethod
  def EEPROM_CONFIG_DATA_TXT():
    return "91020144000000000000004000000000" # must be correct!

  @staticmethod
  def ESC_SM_LEN( sm ):
    if   ( 0 == sm ):
      return ESC_SM0_LEN_C
    elif ( 1 == sm ):
      return ESC_SM1_LEN_C
    elif ( 2 == sm ):
      return ESC_SM2_LEN_C
    elif ( 3 == sm ):
      return ESC_SM3_LEN_C
    else:
      raise ValueError("Invalid SM index")

  @staticmethod
  def ESC_SM_SMA( sm ):
    if   ( 0 == sm ):
      return ESC_SM0_SMA_C
    elif ( 1 == sm ):
      return ESC_SM1_SMA_C
    elif ( 2 == sm ):
      return ESC_SM2_SMA_C
    elif ( 3 == sm ):
      return ESC_SM3_SMA_C
    else:
      raise ValueError("Invalid SM index")

  @staticmethod
  def ESC_SM_SMC( sm ):
    if   ( 0 == sm ):
      return ESC_SM0_SMC_C
    elif ( 1 == sm ):
      return ESC_SM1_SMC_C
    elif ( 2 == sm ):
      return ESC_SM2_SMC_C
    elif ( 3 == sm ):
      return ESC_SM3_SMC_C
    else:
      raise ValueError("Invalid SM index")

  @staticmethod
  def ESC_SM_MAX_LEN( sm ):
    if   ( 3 == sm ):
      return ESC_SM3_MXL_C
    elif ( 2 == sm ):
      return ESC_SM2_MXL_C
    elif ( 0 == sm ):
      return ESC_SM0_MXL_C
    else:
      return FirmwareConstants .ESC_SM_LEN( sm )

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
    return TXPDO_MXMAP_C

  @staticmethod
  def DEVSPECIFIC_CATEGORY_TXT():
    return str(PROM_CAT_ID_C)

  @staticmethod
  def I2C_INITPRG_CATEGORY_TXT():
    return str(I2CP_CAT_ID_C)

  @staticmethod
  def TXPDO_NUM_EVENT_DWORDS():
    return 8

  @staticmethod
  def EEPROM_LAYOUT_VERSION():
    return 2

  @staticmethod
  def EVR_NUM_PULSE_GENS():
    return 4

  @staticmethod
  def EOE_ENABLED():
    return ENBL_EOE_C

  @staticmethod
  def FOE_ENABLED():
    return ENBL_FOE_C

  @staticmethod
  def VOE_ENABLED():
    return ENBL_VOE_C

  @staticmethod
  def CLK_FREQ_VND_CAT_ID():
    return 0x3000

  @staticmethod
  def EVR_DC_TARGET_VND_CAT_ID():
    return 0x3001

  @staticmethod
  def SEGNAMES_VND_CAT_ID():
    return 0x3002

  @staticmethod
  def CLK_DRIVER_MAP(key):
    if ( key == "VersaClock6" ):
      # attribute -> id mapping
      return 0x01
    elif ( key == 0x01 ):
      # id -> attribute mapping
      return "VersaClock6"
    raise KeyError("Unsupported Clock Driver")
class HardwareConstants(object):
  @staticmethod
  def EEPROM_SIZE_BYTES():
    return 2048
