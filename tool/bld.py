#!/usr/bin/env python3
from lxml import etree as ET
import sys

def smCfg(sm, start, size, ctl, txt):
  if ( 0 == size or 0 == ctl ):
     size = 0
     ctl  = 0
     ena  = 0
  else:
     ena  = 1
  sm.set("ControlByte",  "#x{:02x}".format(ctl))
  sm.set("DefaultSize",  "{:d}".format(size))
  sm.set("Enable",       "{:d}".format(ena))
  sm.set("StartAddress", "#x{:04x}".format(start))
  sm.text = txt

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

  def get(self):
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

  def __init__(self):
    object.__init__(self, num32Words, byteOffset, swap = 0)
    self.num32Words = num32Words
    self.dbufOffset = byteOffset
    self.swap       = swap
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
    pd.append( (self.off >> 0) & 0xff )
    pd.append( (self.off >> 8) & 0xff )
    return pd 

class TxPdoBuilder(object):

  def __init__(self):
    object.__init__(self)
    self.withTs_ = True
    self.withEv_ = True
    self.withL0_ = True
    self.withl0_ = True
    self.withL1_ = True
    self.withl1_ = True
    self.segs_   = []

  def withTs(self, v):
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

  def addSegment(self, s):
    self.dbufSegs.extent( s )

  def clearSegments(self):
    self.dbufSegs = []

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
    dbufSegs    = []
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
    for e in entries:
      txPdo.extend( e.get() )
      byteSz += e.getByteSz()

    if ( len(dbufSegs) > 255 ):
      raise RuntimeError("Too many TxPdo Segments, sorry")

    promData = bytearray()
    promData.append( flags         )
    promData.append( len(dbufSegs) )
    for s in dbufSegs:
      promData.extend( s.promData() )

    return txPdo, byteSz, promData


netConfig    = NetConfig()
#netConfig.setIp4Addr("10.10.10.11")
vendorIdTxt  ="#x505349"
vendorNameTxt="Paul Scherrer Institut"
groupNameTxt="Lan9254"
groupTypeTxt="Lan9254"
deviceTypeTxt="Lan9254"
deviceProductCodeTxt="0001"
deviceRevisionNoTxt="0001"
deviceNameTxt="EcEVR"
sm0Len=48   #int -- must match setting in FPGA
sm1Len=48   #int -- must match setting in FPGA
sm2Len=128  #int
sm3Len=128  #int
sm3MaxLen = 138
rxPdoIndexTxt = "#x1600"
txPdoIndexTxt = "#x1A00"
eepromByteSizeTxt="2048"
eepromConfigDataTxt="910201440000000000000040"
eepromEcEvrConfigDataTxt = None
ecEvrCatNoTxt="#x01"
idxLed=0x2000

root = ET.Element("EtherCATinfo")
vendor       = ET.SubElement(root, "Vendor")
descriptions = ET.SubElement(root, "Descriptions")

vendorId      = ET.SubElement(vendor,"Id")
vendorId.text = vendorIdTxt

groups        = ET.SubElement(descriptions, "Groups")
group         = ET.SubElement(groups, "Group")
groupName     = ET.SubElement(group, "Name")
groupName.text = groupNameTxt
groupType     = ET.SubElement(group, "Type")
groupType.text = groupTypeTxt

devices       = ET.SubElement(descriptions, "Devices")
device        = ET.SubElement(devices,"Device", Physics="YY")
deviceType    = ET.SubElement(device, "Type",
                    ProductCode=deviceProductCodeTxt,
                    RevisionNo =deviceRevisionNoTxt)
deviceName    = ET.SubElement(device, "Name")
deviceName.text = deviceNameTxt
ET.SubElement(device, "GroupType").text=groupTypeTxt
ET.SubElement(device, "Fmmu").text="Inputs"
ET.SubElement(device, "Fmmu").text="Outputs"
ET.SubElement(device, "Fmmu").text="MBoxState"
sm0=ET.SubElement(device, "Sm")
sm1=ET.SubElement(device, "Sm")
sm2=ET.SubElement(device, "Sm")
sm3=ET.SubElement(device, "Sm")

txPdo, sm3Len, txPdoPromData = TxPdoBuilder().build()

if ( sm3Len > sm3MaxLen ):
  raise RuntimeError("Invalid configuration; TxPDO too large -- need to modify FPGA image")

rxPdoEntries = PdoEntry("LED", idxLed, 3, 8, False)
sm2Len = rxPdoEntries.getByteSz()

smCfg(sm0, 0x1000, sm0Len, 0x26, "MBoxOut")
smCfg(sm1, 0x1080, sm1Len, 0x22, "MBoxIn")
smCfg(sm2, 0x1100, sm2Len, 0x24, "Outputs")
smCfg(sm3, 0x1180, sm3Len, 0x20, "Inputs")

rxPdo = ET.SubElement( device, "RxPdo" )
rxPdo.set( "Fixed"       , "1" )
rxPdo.set( "Mandatory"   , "1" )
rxPdo.set( "Sm"          , "2" )
rxPdo.extend( rxPdoEntries.get() )

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

eepromEcEvrConfigDataTxt = promData.hex()

if ( not eepromEcEvrConfigDataTxt is None ):
  ET.SubElement(eepromCategory, "CatNo").text = ecEvrCatNoTxt
  ET.SubElement(eepromCategory, "Data" ).text = eepromEcEvrConfigDataTxt

device.append( txPdo )

ET.ElementTree(root).write( 'feil', xml_declaration = True, method="xml", pretty_print=True )
