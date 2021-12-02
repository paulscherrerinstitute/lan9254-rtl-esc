#!/usr/bin/env python3
from lxml import etree as ET
import sys

class SmCfg(object):

  def __init__(self, start, size, ctl, txt):
    object.__init__(self)
    if ( 0 == size or 0 == ctl ):
       size = 0
       ctl  = 0
       ena  = 0
    else:
       ena  = 1
    self.sm = ET.Element("Sm")
    self.sm.set("ControlByte",  "#x{:02x}".format(ctl))
    self.sm.set("DefaultSize",  "{:d}".format(size))
    self.sm.set("Enable",       "{:d}".format(ena))
    self.sm.set("StartAddress", "#x{:04x}".format(start))
    self.sm.text = txt

  def getElm(self):
    return self.sm

class PdoEntry(object):

  def __init__(self, name, idx, nelms, bitSize, signed, typeName=None, indexedName=True):
    object.__init__(self)
    self.entries = []
    self.byteSz  = 0
    if ( 0 == idx or 0 == nelms ):
      idx   = 0
      nelms = 1
    else:
      if ( typeName is None ):
        if   ( 8 == bitSize ):
          typeName = "SINT"
        elif (16 == bitSize ):
          typeName = "INT"
        elif (32 == bitSize ):
          typeName = "DINT"
        elif (64 == bitSize ):
          typeName = "LINT"
        else:
          raise RuntimeError("Unsupported bit size")
        if (not signed):
          typeName = "U"+typeName

    for i in range(0,nelms):
      e = ET.Element("Entry", Fixed="1")
      ET.SubElement( e, "Index" ).text = "#x{:04x}".format( idx )
      if ( 0 == idx ):
        subIdx = 0
      else:
        subIdx = i + 1
      if ( indexedName and nelms > 1 ):
        elName = "{}[{:d}]".format(name, i)
      else:
        elName = name
      ET.SubElement( e, "SubIndex" ).text = "{:d}".format( subIdx  )
      ET.SubElement( e, "BitLen"   ).text = "{:d}".format( bitSize )
      ET.SubElement( e, "Name"     ).text = elName
      if ( 0 != idx ):
        ET.SubElement( e, "DataType" ).text = typeName
      self.byteSz += int( (bitSize + 7)/8 )
      self.entries.append(e)

  def getByteSz(self):
    return self.byteSz

  def getElm(self):
    return self.entries

class NetConfig(object):
  def __init__(self):
    object.__init__(self)
    self.macAddr = bytearray( [255 for i in range(6)] )
    self.ip4Addr = bytearray( [255 for i in range(4)] )
    self.udpPort = bytearray( [255 for i in range(2)] )

  def setMacAddr(self, a = "ff:ff:ff:ff:ff:ff"):
    self.macAddr = self.convert(a, 6, ":", 16)

  def setIp4Addr(self, a = "255.255.255.255"):
    self.ip4Addr = self.convert(a, 4, ".", 10)

  def setUdpPort(self, a = 0xffff):
    self.udpPort = self.convert(a, 2, None, None)

  def promData(self):
    rv = bytearray()
    rv.extend( self.macAddr )
    rv.extend( self.ip4Addr )
    rv.extend( self.udpPort )
    return rv

  @staticmethod
  def convert(a, l, sep, bas):
    if   ( isinstance( a, bytearray ) ):
      if ( len(a) != l ):
        raise RuntimeError("NetConfig: bytearray must have exactly {} elements".format(l))
      ba = a
    elif ( isinstance( a, str       ) ):
      if not sep is None:
        parts = a.split(sep)
        if ( len(parts) != l ):
           raise RuntimeError("NetConfig: string (separator '{}') must have {} elements".format(sep, l))
      ba = bytearray([int(x, bas) for x in parts])
      if ( len(ba) != l ):
        raise RuntimeError("NetConfig: string does not split into {} elements".format(l))
    elif ( isinstance( a, int       ) ):
      ba = bytearray()
      for i in range(l):
        ba.append( ( a & 0xff ) )
        a >>= 8
      # address in network-byte order
      ba.reverse()
    else:
        raise RuntimeError("NetConfig: don't know how to convert " + type(a) + "into a network address")
    return ba

class DbufSegment(object):

  def __init__(self, num32Words, byteOffset, swap = 0):
    object.__init__(self)
    self.num32Words = num32Words
    # Add offset from EVR base address to data buffer
    byteOffset     += 0x80
    self.dbufOffset = byteOffset
    self.swap       = swap
    self.pdoEntries = []
    if not swap in (0,1,2,4):
      raise RuntimeError("DbufSegment: Unsupported swap size: " + swap)
    if ( num32Words > 0x3ff ):
      raise RuntimeError("DbufSegment: number of words too large")
    if ( byteOffset > 0xffff ):
      raise RuntimeError("DbufSegment: byte offset too large")

  def promData(self):
    pd = bytearray()
    pd.append( self.num32Words & 0xff )
    tmp = (self.num32Words >> 8) & 0x03
    if   ( 2 == self.swap ):
      tmp |= 0x10
    elif ( 4 == self.swap ):
      tmp |= 0x20
    pd.append( tmp )
    pd.append( (self.dbufOffset >> 0) & 0xff )
    pd.append( (self.dbufOffset >> 8) & 0xff )
    return pd 

  def getByteSz(self):
    return 4*self.num32Words

  def getPdoEntries(self):
    return self.pdoEntries

  def addPdoEntries(self, entries):
    if not entries is None:
      if isinstance(entries, list):
        self.pdoEntries.extend( entries )
      else:
        self.pdoEntries.append( entries )
    return self

  # factory method to map byte-swapped 64-bit entities
  @staticmethod
  def create(num32Words, byteOffset, swap = 0, pdoEntries = None):
    rv = []
    if ( 8 == swap ):
      if ( 0 != num32Words % 2 ):
         raise RuntimeError("DbufSegment: create - number of elements does not match swap size")
      for i in range(0,num32Words,2):
        rv.append( DbufSegment( 1, byteOffset + 4, 4 ) )
        rv.append( DbufSegment( 1, byteOffset + 0, 4 ) )
        byteOffset += 8
    else:
      rv.append( DbufSegment( num32Words, byteOffset, swap ) )

    rv[0].addPdoEntries( pdoEntries )
    return rv

class TxPdoBuilder(object):

  # maxSegs must match fpga generics
  def __init__(self, maxSegs):
    object.__init__(self)
    self.withTs_ = True
    self.withEv_ = True
    self.withL0_ = True
    self.withl0_ = True
    self.withL1_ = True
    self.withl1_ = True
    self.segs_   = []
    self.maxSegs_= maxSegs

  def withNone(self):
    self.withTimestamp(False)
    self.withEventCodes(False)
    self.withLatch0RisingTime(False)
    self.withLatch0FallingTime(False)
    self.withLatch1RisingTime(False)
    self.withLatch1FallingTime(False)
    return self

  def clear(self):
    self.withNone()
    self.clearSegments()
    return self

  def withTimestamp(self, v):
    self.withTx_ = v
    return self

  def withEventCodes(self, v):
    self.withEv_ = v
    return self
    
  def withLatch0RisingTime(self, v):
    self.withL0_ = v
    return self
    
  def withLatch0FallingTime(self, v):
    self.withl0_ = v
    return self

  def withLatch1RisingTime(self, v):
    self.withL1_ = v
    return self
    
  def withLatch1FallingTime(self, v):
    self.withl1_ = v
    return self

  def addSegments(self, s):
    if isinstance(s, list):
      self.segs_.extend( s )
    else:
      self.segs_.append( s )
    return self

  def clearSegments(self):
    self.segs_ = []
    return self

  def build(self):
    txPdo = ET.Element( "TxPdo" )
    txPdo.set( "Fixed"       , "1" )
    txPdo.set( "Mandatory"   , "1" )
    txPdo.set( "Sm"          , "3" )
    ET.SubElement( txPdo, "Index" ).text = "#x1A00"
    ET.SubElement( txPdo, "Name"  ).text = "ECAT EVR Databuffer"
    entries     = []
    byteSz      = 0
    idxTsHi     = 0x5000
    idxTsLo     = 0x5001
    idxEvts     = 0x5002
    idxL0Ri     = 0x5003
    idxL0Fa     = 0x5004
    idxL1Ri     = 0x5005
    idxL1Fa     = 0x5006
    nEvWrds     = 8
    flags       = 0
    if ( self.withTs_ ):
      entries.append( PdoEntry("TimestampHi", idxTsHi, 1, 32, False) )
      entries.append( PdoEntry("TimestampLo", idxTsLo, 1, 32, False) )
      flags |= 0x01
    if ( self.withEv_ ):
      entries.append( PdoEntry("Events"     , idxEvts, nEvWrds, 32, False) )
      flags |= 0x02
    if ( self.withL0_ ):
      entries.append( PdoEntry("TimestampLatch0Rising", idxL0Ri, 1, 64, False) )
      flags |= 0x04
    if ( self.withl0_ ):
      entries.append( PdoEntry("TimestampLatch0Falling", idxL0Fa, 1, 64, False) )
      flags |= 0x08
    if ( self.withL1_ ):
      entries.append( PdoEntry("TimestampLatch1Rising", idxL1Ri, 1, 64, False) )
      flags |= 0x10
    if ( self.withl1_ ):
      entries.append( PdoEntry("TimestampLatch1Falling", idxL1Fa, 1, 64, False) )
      flags |= 0x20

    if ( len(self.segs_) > 255 or len(self.segs_) > self.maxSegs_ ):
      raise RuntimeError("Too many TxPdo Segments, sorry")

    for e in entries:
      txPdo.extend( e.getElm() )
      byteSz += e.getByteSz()

    for s in self.segs_:
      for e in s.getPdoEntries():
        txPdo.extend( e.getElm() )
      byteSz += s.getByteSz()

    promData = bytearray()
    promData.append( flags         )
    promData.append( len(self.segs_) )
    for s in self.segs_:
      promData.extend( s.promData() )

    return txPdo, byteSz, promData


netConfig    = NetConfig()
#netConfig.setIp4Addr("10.10.10.11")
#netConfig.setMacAddr("48:01:02:03:04:05")
vendorIdTxt  ="#x505349"
vendorNameTxt="Paul Scherrer Institut"
groupNameTxt="Lan9254"
groupTypeTxt="Lan9254"
deviceTypeTxt="Lan9254"
deviceProductCodeTxt="0001"
deviceRevisionNoTxt="0001"
deviceNameTxt="EcEVR"
idxLed=0x2000
eepromEcEvrConfigDataTxt = None
rxPdoIndexTxt = "#x1600"
txPdoIndexTxt = "#x1A00"
eepromByteSizeTxt="2048" # -- must be <= value of actual hardware

eepromConfigDataTxt="910201440000000000000040" # FIXME -- must be correct
# Info that must be extracted from VHDL code
sm0Len=48   #int -- must match setting in VHDL
sm1Len=48   #int -- must match setting in VHDL
sm2Len=128  #int -- can be configured up to max set in VHDL
sm3Len=128  #int -- can be configured up to max set in VHDL
sm0Sma=0x1000
sm0Smc=0x26
sm1Sma=0x1080
sm1Smc=0x22
sm2Sma=0x1100
sm2Smc=0x24
sm3Sma=0x1180
sm3Smc=0x20
maxPdoSegs=16

sm3MaxLen = 138  # -- must be <= value defined in VHDL

ecEvrCatNoTxt="1" # -- must match setting in VHDL

root = ET.Element("EtherCATInfo")

# note that XML schema expects these elements in order !
vendor          = ET.SubElement(root, "Vendor")
vendorId          = ET.SubElement(vendor,"Id")
vendorId.text       = vendorIdTxt
vendorId          = ET.SubElement(vendor,"Name")
vendorId.text       = vendorNameTxt

descriptions    = ET.SubElement(root, "Descriptions")
groups            = ET.SubElement(descriptions, "Groups")
group               = ET.SubElement(groups, "Group")
groupType             = ET.SubElement(group, "Type")
groupType.text          = groupTypeTxt
groupName             = ET.SubElement(group, "Name")
groupName.text          = groupNameTxt

devices           = ET.SubElement(descriptions, "Devices")
device              = ET.SubElement(devices,"Device", Physics="YY")
deviceType            = ET.SubElement(device, "Type",
                          ProductCode=deviceProductCodeTxt,
                          RevisionNo =deviceRevisionNoTxt)
deviceName            = ET.SubElement(device, "Name")
deviceName.text         = deviceNameTxt

groupType             = ET.SubElement(device, "GroupType").text=groupTypeTxt
fmmu                  = ET.SubElement(device, "Fmmu")
fmmu.text               ="Inputs"
fmmu                  = ET.SubElement(device, "Fmmu")
fmmu.text               ="Outputs"
fmmu                  = ET.SubElement(device, "Fmmu")
fmmu.text               ="MBoxState"

# FIXME
txPdoBldr = TxPdoBuilder(maxPdoSegs)
txPdoBldr.clear().withTimestamp( True ).withLatch0RisingTime( True )
txPdoBldr.addSegments([
  DbufSegment(1, 0x28).addPdoEntries( PdoEntry( "TimestampSec", 0x5500, 1, 32, False ) ),
  DbufSegment(2, 0x34).addPdoEntries( PdoEntry( "PulseID"     , 0x5501, 1, 64, False ) )
  ])

txPdo, sm3Len, txPdoPromData = txPdoBldr.build()

if ( sm3Len > sm3MaxLen ):
  raise RuntimeError("Invalid configuration; TxPDO too large -- need to modify FPGA image")

rxPdoEntries = PdoEntry("LED", idxLed, 3, 8, False)

rxPdo = ET.Element( "RxPdo" )
rxPdo.set( "Fixed"       , "1" )
rxPdo.set( "Mandatory"   , "1" )
rxPdo.set( "Sm"          , "2" )
ET.SubElement( rxPdo, "Index" ).text = "#x1600"
ET.SubElement( rxPdo, "Name"  ).text = "ECAT EVR RxData"
rxPdo.extend( rxPdoEntries.getElm() )

sm2Len = rxPdoEntries.getByteSz()

device.append( SmCfg(sm0Sma, sm0Len, sm0Smc, "MBoxOut").getElm() )
device.append( SmCfg(sm1Sma, sm1Len, sm1Smc, "MBoxIn" ).getElm() )
device.append( SmCfg(sm2Sma, sm2Len, sm2Smc, "Outputs").getElm() )
device.append( SmCfg(sm3Sma, sm3Len, sm3Smc, "Inputs" ).getElm() )
device.append( rxPdo )
device.append( txPdo )

#ET.SubElement( rxPdo, "Index").text=rxPdoIndexTxt
#ET.SubElement( rxPdo, "Name").text=rxPdoIndexTxt
mailbox = ET.SubElement( device, "Mailbox" )
mailbox.set("DataLinkLayer", "1")
mailboxEoE = ET.SubElement(mailbox, "EoE")
mailboxEoE.set("IP", "1")
mailboxEoE.set("MAC", "1")

eeprom  = ET.SubElement( device, "Eeprom" )
eeprom.set("AssignToPdi", "1")
ET.SubElement(eeprom, "ByteSize" ).text=eepromByteSizeTxt
ET.SubElement(eeprom, "ConfigData").text=eepromConfigDataTxt
eepromCategory = ET.SubElement(eeprom, "Category")

promData = bytearray()
promData.extend( netConfig.promData() )
promData.extend( txPdoPromData        )

# Device-specific PROM section. Here we describe to the firmware
# what pieces of data we want them to map to the TxPdo, what
# the network addresses are and possibly other non-volatile data
# that we don't want to hardcode into the FPGA.
eepromEcEvrConfigDataTxt = promData.hex()

if ( not eepromEcEvrConfigDataTxt is None ):
  ET.SubElement(eepromCategory, "CatNo").text = ecEvrCatNoTxt
  ET.SubElement(eepromCategory, "Data" ).text = eepromEcEvrConfigDataTxt


ET.ElementTree(root).write( 'feil.xml', xml_declaration = True, method="xml", pretty_print=True )
