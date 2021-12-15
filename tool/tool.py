#!/usr/bin/env python3
from   lxml      import etree as ET
from   functools import wraps
import sys
import copy
from   FirmwareConstants import FirmwareConstants
from   AppConstants      import ESIDefaults, HardwareConstants

# Define a decorator that checks if
# the current state allows the object
# to be modified.
def lockCheck(prop):
  @wraps(prop)
  def _check(self, *a, **ka):
    if self.isLocked:
      raise RuntimeError("Cannot modify locked object")
    rv = prop(self, *a, **ka)
    return rv
  return _check

# Convert HexDec to int
def hd2int(x):
  try:
    if x[0:2] == "#x":
      return int(x[2:],16)
    else:
      return int(x, 10)
  except Exception as e:
    print("Trying to convert '{}'".format(x))
    raise(e)

def int2hd(x, wid=0, asHex=True):
  if asHex:
    pr = "#x"
    fm = "x"
  else:
    pr = ""
    fm = "d"
  return "{}{{:0{:d}{}}}".format(pr,wid,fm).format(x)


# object that describes an element in
# the XML tree

# Instantiate with 
#
# Item( <key>, <type>, <default_value> )
#
# - key must be a string (XML tag; used as dict key)
# - type is one of
#     Item.T_INT : integer
#     Item.T_STR : string
#     Item.T_HDT : raw hex data (bytearray)
#     Item.T_BLN : boolean

class Item(object):
  # Types
  T_NUL = 0 # no data
  T_INT = 1
  T_STR = 2
  T_HDT = 3 # hex data
  T_BLN = 4 # boolean
  _T_MAX = 4

  @property
  def key(self):
    return self._key

  @key.setter
  def key(self, val):
    if not isinstance(val, str):
      raise ValueError("Item.key must be a string")
    self._key = val

  @property
  def typ(self):
    return self._typ

  @property
  def val(self):
    if self.T_NUL == self.typ:
      raise ValueError("Item.val[setter]: NUL item cannot hold a value")
    else:
      return self._val

  @val.setter
  def val(self, val):
    if self.T_NUL == self.typ:
      raise ValueError("Item.val[setter]: NUL item cannot hold a value")
    elif self.T_INT == self.typ:
      if isinstance(val, int):
        self._val = val
      elif isinstance(val, str):
        if val[0:2] == "#x" or val[0:2] == "#X":
          self._val = int(val[2:], 16)
        else:
          self._val = int(val, 0)
      else:
        self._val = int(val)
    elif self.T_STR == self.typ:
      self._val = str(val)
    elif self.T_HDT == self.typ:
      if isinstance(val, bytearray):
        self._val = val
      elif isinstance(val, str):
        l = len(val)
        if ( l % 2 != 0 ):
          raise ValueError("Item.val[setter]: string length must be even")
        l = int(l/2)
        self._val = bytearray( l )
        for i in range( l ):
           self._val[i] = int(val[2*i:2*i+2],16)
      else:
        raise ValueError("Item.val[setter]: unable to convert to bytearray")
    elif self.T_BLN == self.typ:
      if isinstance(val, bool):
        self._val = val
      elif isinstance(val, int):
        self._val = (val != 0)
      elif isinstance(val, str):
        if   ( str.upper(val[0]) in [ '1', 'T' ] ):
          self._val = True
        elif ( str.upper(val[0]) in [ '0', 'F' ] ):
          self._val = False
        else:
          raise ValueError("Item.val[setter]: unable to convert to boolean")
    else:
      raise RuntimeError("Item.val[setter]: should not get here")
  
  def __init__(self, key, typ, defval = None):
    object.__init__(self)
    if not isinstance(typ, int) or typ < 0 or typ > self._T_MAX:
      raise ValueError("Item type invalid")
    self._typ      = typ
    if ( Item.T_NUL != typ ):
      self.val       = defval
    self._children = []

  def add(self, children):
    if not isinstance(children, list):
      children = [children]
    for c in children:
      if not isinstance(c, Item):
        raise ValueError("Item.add: must only add Item objects")
    self._children.extend( children )

  # convert to a string conforming with ESI file XML spec
  def toStr(self, base=10, width=0):
    if self.T_NUL == self.typ:
      return ""
    elif self.T_INT == self.typ:
      if ( 10 == base ):
        return str(self.val)
      elif ( 16 == base ):
        return "#x{{:0{}x}}".format(width).format(val)
      else:
        raise ValueError("Item.toStr - invalid base (10 or 16 supported)")
    elif self.T_STR == self.typ:
      return self.val
    elif self.T_HDT == self.typ:
      return self.val.hex()
    elif self.T_BLN == self.typ:
      if self.val:
        return "1"
      else:
        return "0"
    else:
      raise RuntimeError("Item.val[setter]: should not get here")

class PdoSegment(object):

  @staticmethod
  def swp2str(swap):
    return "{:d}-bytes".format(swap)

  @staticmethod
  def str2swp(s):
    return int(s[0])

  def __init__(self, name, byteOffset, nDWords, swap = 0):
    self._isLocked   = False
    self._name       = None
    self._nDWords    = 2
    self._swap       = 0
    self._byteOffset = 0
    self.name        = name
    self.nDWords     = nDWords
    self.byteOffset  = byteOffset
    self.swap        = swap

  def clone(self):
    rv           = copy.copy(self)
    rv._isLocked = False
    return rv

  def isFixed(self):
    return False

  @property
  def name(self):
    return self._name

  @name.setter
  def name(self, val):
    self._name = val

  @property
  def isLocked(self):
    return self._isLocked

  # lock only to be modified by holding class
  def _lock(self):
    self._isLocked = True

  def _unlock(self):
    self._isLocked = False

  @property
  def byteOffset(self):
    return self._off

  @byteOffset.setter
  def byteOffset(self, val):
    if ( not isinstance(val, int) or (val % 4 != 0) ):
      raise ValueError("PdoSegment.byteOffset must be 4-aligned int")
    if ( (val < 0) or (val > 4*1024) ):
      raise ValueError("PdoSegment.byteOffset out of range")
    self._off = val

  @property
  def swap(self):
    return self._swap

  @swap.setter
  def swap(self, val):
    if not isinstance(val, int) or not val in [0,1,2,4,8]:
      raise ValueError("PdoSegment.swap not an int or out of range")
    if ( 8 == val and (self.nDWords % 2) != 0 ):
      raise ValueError("nDWords of a 8-byte swapped segment must be even")
    if 0 == val:
      val = 1
    self._swap = val

  @property
  def byteSz(self):
    return self._n * 4

  @property
  def nDWords(self):
    return self._n

  @nDWords.setter
  @lockCheck
  def nDWords(self, val):
   if not isinstance(val, int) or val <  0 or val > 1024:
     raise ValueError("PdoSegment.nDWords not an int or out of range")
   if ( 8 == self.swap and (val % 2) != 0 ):
     raise ValueError("PdoSegment.nDWords of a 8-byte swapped segment must be even")
   self._n = val

  def promData(self):
    pd = bytearray()
    if ( 8 == self.swap ):
      nentries = self.nDWords
      size     = 1
      off      = self.byteOffset + 4
    else:
      size     = self.nDWords
      nentries = 1
      off      = self.byteOffset

    for i in range(nentries):
      pd.append( nentries & 0xff )
      tmp = (nentries >> 8) & 0x03
      if   ( 2 == self.swap ):
        tmp |= 0x10
      elif ( 4 == self.swap or 8 == self.swap ):
        tmp |= 0x20
      pd.append( tmp )
      pd.append( (off >> 0) & 0xff )
      pd.append( (off >> 8) & 0xff )
      off += -4 if (i % 2 == 0) else +8
    return pd

  @staticmethod
  def fromPromData(prom):
    if not isinstance(prom, bytearray):
      raise ValueError("bytearray expected")
    nDWords = ((prom[1] & 3) << 8) | prom[0]
    tmp     = prom[1] & ~3
    if   0x20 == tmp:
      swap = 4
    elif 0x10 == tmp:
      swap = 2
    else:
      swap = 1
    byteOff = ((prom[3]<<8) | prom[2])
    return PdoSegment(None, byteOff, nDWords, swap)

class PdoEntry(object):

  def __init__(self, elmLst, name, index, nelms, bitSize, isSigned, typeName=None, indexedName=True):
    object.__init__(self)
    # initialize private vars because setters cross-check
    # and they must exist
    self._elmLst      = elmLst
    if ( elmLst is None ): 
      self._elmLst = []
      for i in range(nelms):
        self._elmLst.append( ET.Element( "Entry", Fixed="1" ) )
    
    self._isLocked    = False
    self._index       = 0
    self._indexedName = indexedName
    self._typeName    = typeName
    # the following assignments define the order of sub-elements
    # in the associated XML when this is created from scratch.
    # The order has to adhere to the XML schema!
    self.index        = index
    self.syncElms( "SubIndex", [ int2hd( i+1, wid=2 ) for i in range( self.nelms ) ] )
    self.bitSize      = bitSize
    self.name         = name
    self.isSigned     = isSigned
    if typeName is None:
      typeName = ""
    self.typeName     = typeName
    self.indexedName  = indexedName


  @property
  def typeName(self):
    if ( self._typeName is None or 0 == len(self._typeName) ):
        if   ( 8 == self.bitSize ):
          tn = "SINT"
        elif (16 == self.bitSize ):
          tn = "INT"
        elif (32 == self.bitSize ):
          tn = "DINT"
        elif (64 == self.bitSize ):
          tn = "LINT"
        else:
          raise RuntimeError("Unexpected bit size")
        if (not self.isSigned):
          tn = "U"+tn
    else:
      tn = self._typeName 
    return tn

  @typeName.setter
  def typeName(self, val):
    self._typeName = val
    self.syncElms( "DataType", self.typeName )

  @property
  def bitSize(self):
    return 8*self.byteSz

  @property
  def byteSz(self):
    return self._byteSz

  @bitSize.setter
  @lockCheck
  def bitSize(self, val):
    if ( val % 8 != 0 ):
      raise ValueError("PdoEntry.bitSize - only multiples of 8 supported")
    self._byteSz = int( val/8 )
    self.syncElms( "BitLen", str(val) )

  @byteSz.setter
  @lockCheck
  def byteSz(self, val):
    self._byteSz = val
    self.syncElms( "BitLen", str(8*val) )

  @property
  def name(self):
    return self._name

  @name.setter
  def name(self, val):
    self._name = val
    if ( self.indexedName and self.nelms > 1 ):
       val = [ "{}[{:d}]".format(val, i) for i in range(1, self.nelms + 1) ]
    self.syncElms( "Name", val )

  @property
  def nelms(self):
    return len( self._elmLst )

  @property
  def index(self):
    return self._index

  @index.setter
  def index(self, val):
    if ( val < 0 ):
      raise ValueError("PdoEntry.index - must be >= 0")
    self._index = val
    if ( 0 == val ):
      self._nelms = 0
    elif ( 0 == self.nelms ):
      self._nelms = 1
    self.syncElms( "Index", "#x{:04x}".format( self.index ) )

  @staticmethod
  def toBool(val):
    if isinstance(val, bool):
      return val
    elif isinstance(val, int):
      return (val != 0)
    elif isinstance(val, str) and len(val) > 0:
      if val.upper() in ['1', 'T']:
        return True
      elif val.upper() in ['0', 'F']:
        return False
    raise ValueError("PdoEntry.toBool - unable to convert '{}' to bool".format(val))

  @property
  def isSigned(self):
    return self._isSigned

  @isSigned.setter
  def isSigned(self, val):
    self._isSigned = self.toBool(val)
    # sync type name
    self.typeName  = self.typeName

  @property
  def indexedName(self):
    return self._indexedName

  @indexedName.setter
  def indexedName(self, val):
    self._indexedName = self.toBool(val)
    # update names in associated elements
    self.name         = self.name

  @property
  def isLocked(self):
    return self._isLocked

  # lock only to be modified by holding Pdo object
  def _lock(self):
    self._isLocked = True

  def _unlock(self):
    self._isLocked = False

  @property
  def elements(self):
    return self._elmLst

  def syncElms(self, subEl, subVal):
    if not isinstance(subVal, list):
      subVal = [ subVal for i in range( len(subEl) ) ]
    i = 0
    for e in self._elmLst:
      se = findOrAdd(e, subEl)
      se.text = str( subVal[i] )
      i += 1

class FixedPdoPart(object):
  F_WITH_TSTAMP = 1
  F_WITH_EVENTS = 2
  F_WITH_LTCH0R = 4
  F_WITH_LTCH0F = 8
  F_WITH_LTCH1R = 16
  F_WITH_LTCH1F = 32

  F_MASK        = (F_WITH_LTCH1F << 1) - 1

  def __init__(self, flags, names = None):
    super().__init__()
    self._maxSegs = FirmwareConstants.TXPDO_MAX_NUM_SEGMENTS()
    self._flags   = flags
    if names is None:
      names = [ "TimestampLo",
                "TimestampHi",
                "EventSet",
                "TimestampLatch0Rising",
                "TimestampLatch0Falling",
                "TimestampLatch1Rising",
                "TimestampLatch2Falling" ]
    self._names       = names
    self._eventDWords = FirmwareConstants.TXPDO_NUM_EVENT_DWORDS()

  @property
  def flags(self):
    return self._flags

  # should only be used by subclass 
  def _setFlags(self, val):
    self._flags = val

  @property
  def eventDWords(self):
    return self._eventDWords

  @property
  def numEntries(self):
    rv = 0
    if ( (self.flags & self.F_WITH_TSTAMP) ):
      rv += 2
    if ( (self.flags & self.F_WITH_EVENTS) ):
      rv += self._eventDWords
    if ( (self.flags & self.F_WITH_LTCH0R) ):
      rv += 2
    if ( (self.flags & self.F_WITH_LTCH0F) ):
      rv += 2
    if ( (self.flags & self.F_WITH_LTCH1R) ):
      rv += 2
    if ( (self.flags & self.F_WITH_LTCH1F) ):
      rv += 2
    return rv

  @property
  def byteSz(self):
    return 4*self.numEntries

  @property
  def names(self):
    return self._names

  @property
  def maxNumSegments(self):
    return self._maxSegs

  def checkEntry(self, e, nm):
    enm = e.find("Name")
    if ( enm is None or enm.text != nm ):
      raise ValueError("Entry named '{}' not found".format(nm))

  def validateTxPdo(self, pdoEl):
    if ( pdoEl is None ):
      return
    entries = pdoEl.findall("Entry")
    eidx    = 0
    nidx    = 0
    # timestamp flag covers both 
    fset    = self._flags
    if ( (fset & self.F_WITH_TSTAMP) != 0 ):
      self.checkEntry( entries[eidx    ], self._names[nidx    ] )
      self.checkEntry( entries[eidx + 1], self._names[nidx + 1] )
      eidx += 2
      fset &= ~ self.F_WITH_TSTAMP
    nidx += 2
    if ( (self.flags & self.F_WITH_EVENTS) != 0 ):
      for i in range(self._eventDWords):
        self.checkEntry( entries[eidx], self._names[nidx] )
        eidx += 1
      fset &= ~ self.F_WITH_EVENTS
    nidx += 1
    msk = self.F_WITH_EVENTS
    while ( ( nidx < len(self._names) ) and ( eidx < len(entries) ) ):
      msk <<= 1
      if ( ( fset & msk ) != 0 ):
        self.checkEntry( entries[eidx], self._names[nidx] )
      fset &= ~msk
      nidx += 1
    if ( fset != 0 ):
      raise ValueError("Not all required entries found!")

def findOrAdd(nod, sub):
  found = nod.find(sub)
  if found is None:
    found = ET.SubElement(nod, sub)
  return found

def addOrReplace(nod, sub):
  found = nod.find(sub.tag)
  if found is None:
    nod.append(sub)
  else:
    nod.replace(found, sub)

class Sm(object):
  def __init__(self, el, start, size, ctl, txt):
    object.__init__(self)
    if ( 0 == size or 0 == ctl ):
       self._ena  = 0
    else:
       self._ena  = 1
    self._ctl  = ctl
    self._size = size
    self._el = ET.Element("Sm") if el is None else el
    # immutable
    self._el.set("ControlByte",  int2hd(ctl,   wid = 2))
    self._el.set("StartAddress", int2hd(start, wid = 4))
    self._el.text = txt
    self.syncElms()

  def setSize(self, size):
    self._ena  = (size != 0 and self._ctl != 0)
    self._size = size
    self.syncElms()

  def syncElms(self):
    self._el.set("DefaultSize",  "{:d}".format(self._size))
    self._el.set("Enable",       "{:d}".format(self._ena))

class NetConfig(object):
  def __init__(self):
    object.__init__(self)
    self._macAddr = bytearray( [255 for i in range(6)] )
    self._ip4Addr = bytearray( [255 for i in range(4)] )
    self._udpPort = bytearray( [255 for i in range(2)] )

  def clone(self):
    return copy.copy(self)

  @property
  def macAddr(self):
    return copy.copy(self._macAddr)

  @property
  def ip4Addr(self):
    return copy.copy(self._ip4Addr)

  @property
  def udpPort(self):
    return copy.copy(self._udpPort)

  def setMacAddr(self, a = "ff:ff:ff:ff:ff:ff"):
    if ( isinstance(a, bytearray) ):
      self._macAddr = a
    else:
      self._macAddr = self.convert(a, 6, ":", 16)

  def setIp4Addr(self, a = "255.255.255.255"):
    if ( isinstance(a, bytearray) ):
      self._ip4Addr = a
    else:
      self._ip4Addr = self.convert(a, 4, ".", 10)

  def setUdpPort(self, a = 0xffff):
    if ( isinstance(a, bytearray) ):
      self._udpPort = a
    else:
      self._udpPort = self.convert(a, 2, None, None)

  def promData(self):
    rv = bytearray()
    rv.extend( self._macAddr )
    rv.extend( self._ip4Addr )
    rv.extend( self._udpPort )
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

class Evr320PulseParam(object):
  def __init__(self):
    self._enabled = False
    self._width   = 4
    self._delay   = 0
    self._event   = 0

  @property
  def pulseEnabled(self):
    return self._enabled

  @pulseEnabled.setter
  def pulseEnabled(self, v):
    self._enabled = v and (self.pulseWidth != 0)

  @property
  def pulseWidth(self):
    return self._width

  @pulseWidth.setter
  def pulseWidth(self, v):
    self._width  = v
    # re-check enabled flag
    self.pulseEnabled = self.pulseEnabled

  @property
  def pulseDelay(self):
    return self._delay

  @pulseDelay.setter
  def pulseDelay(self, v):
    self._delay  = v

  @property
  def pulseEvent(self):
    return self._event

  @pulseEvent.setter
  def pulseEvent(self, v):
    if ( v < 0 or v > 255 ):
      raise ValueError("Evr320PulseParams -- invalid event code")
    self._event  = v

  def promData(self):
    rv = bytearray()
    x  = self.pulseWidth & ~(1<<31)
    if self.pulseEnabled:
      x |= (1<<31)
    for v in [x, self.pulseDelay]:
      for i in range(4):
        rv.append( (v & 255) )
        v >>= 8
    rv.append( (self.pulseEvent & 255) )
    return rv

class ExtraEvents(object):
  def __init__(self):
    self._eventCodes = [0,0,0,0]

  def __getitem__(self,i):
    return self._eventCodes[i]

  def __setitem__(self, i, val):
    if ( val < 0 or val > 255 ):
      raise ValueError("ExtraEvents -- invalid event code")
    self._eventCodes[i] = val

  def __len__(self):
    return len(self._eventCodes)

  def promData(self):
    return bytearray(self._eventCodes)

class VendorData(FixedPdoPart):

  def __init__(self, el, segments = [], flags = 0, netConfig = NetConfig(), evrParams = None, eventCodes = ExtraEvents(), fixedNames = None):
    super().__init__(flags, fixedNames)
    if (el is None):
      el = ET.Element("Eeprom")
    else:
      self.validateTxPdo( el.find("../TxPdo") )
    self._netConfig = netConfig
    self._el        = el
    if ( evrParams is None ):
      self._evrParams = [ Evr320PulseParam() for i in range(FirmwareConstants.EVR_NUM_PULSE_GENS()) ]
      i = 1
      for p in self._evrParams:
        p.pulseDelay = 16*i
        p.pulseWidth = 256*i + 4
        p.pulseEvent = i
        i += 1
    else:
      self._evrParams = evrParams
    self._xtraEvents = eventCodes
    for i in range(len(self._xtraEvents)):
      self._xtraEvents[i] = 0x11*(i+1)

    self.update( self.flags, segments )

  def getEvrParam(self, idx):
    return self._evrParams[idx]

  def getExtraEvent(self, idx):
    return self._xtraEvents[idx]

  def setExtraEvent(self, idx, val):
    self._xtraEvents[idx] = val

  @property
  def netConfig(self):
    return self._netConfig

  def update(self, flags, segments):
    self._setFlags( flags )
    self._segs      = []
    # make a copy
    for s in segments:
      self._segs.append( s.clone() )
    # add dummy segment for fixed / non-editable entries
    self._segs.insert(0, PdoSegment( "Fixed", 0, self.numEntries ))
    for s in self._segs:
      s._lock()
    self.syncElms()

  # brute-force; this is not often used
  @staticmethod
  def crc8byte(crc, dat):
    rem = dat ^ crc
    for i in range(8):
      if 0 != (rem & 0x80):
        rem = (rem<<1) ^ 0x07 # XOR with polynomial
      else:
        rem = (rem<<1)
      rem &= 0xff
    return rem
      

  def syncElms(self):
    self._el.set("AssignToPdi", "1")

    se = findOrAdd( self._el, "ByteSize" )
    se.text = str( HardwareConstants.EEPROM_SIZE_BYTES() )

    se = findOrAdd( self._el, "ConfigData" )
    data = bytearray.fromhex( FirmwareConstants.EEPROM_CONFIG_DATA_TXT() )
    data.extend( [0 for i in range(14 - len(data))] )
    crc  = 0xff
    for d in data[0:14]:
       crc = self.crc8byte(crc, d)
    data[14] = crc
    data[15] = 0
    se.text  = data.hex()

    cat = findOrAdd( self._el, "Category" )
    se  = findOrAdd( cat, "CatNo" )
    se.text = FirmwareConstants.DEVSPECIFIC_CATEGORY_TXT()

    se  = findOrAdd( cat, "Data" )
    se.text = self.promData().hex()

    if len( self._segs ) < 2:
      vdr = self._el.find( "VendorSpecific" )
      if not vdr is None:
        self._el.remove( vdr )
    else:
      vdr = findOrAdd( self._el, "VendorSpecific" )
      for s in vdr.findall("Segment"):
        vdr.remove(s)
      for s in self._segs[1:]:
        sz64 = s.nDWords if s.swap == 8 else 0
        ET.SubElement(vdr, "Segment", Swap8="{}".format(sz64)).text = s.name

  @property
  def segments(self):
    return self._segs

  def promData(self):
    actualSegs = 0
    for s in self.segments:
      if (8 == s.swap ):
        actualSegs += s.nDWords
      elif s.nDWords > 0:
        actualSegs += 1
    # last-ditch check; this should have been rejected earlier!
    if ( actualSegs > self.maxNumSegments ):
      raise ValueError("Too many segments")
    prom = bytearray()
    prom.append( FirmwareConstants.EEPROM_LAYOUT_VERSION() )
    prom.extend( self._netConfig.promData() )
    prom.append( len( self._evrParams )     )
    for p in self._evrParams:
      prom.extend( p.promData() )
    prom.extend( self._xtraEvents.promData() )
    prom.append( (self._flags & self.F_MASK) )
    prom.append( actualSegs )
    for s in self.segments:
      if ( s.nDWords > 0 ):
        prom.extend( s.promData() )
    return prom

  @property
  def element(self):
    return self._el

  @classmethod
  def fromElement(clazz, el, *args, **kwargs):
    # look for segment names and 8-byte swap info
    segments = []
    vdr = el.find("VendorSpecific")
    if (not vdr is None):
      for s in vdr.findall("Segment"):
        swap8words = s.get("Swap8")
        if swap8words is None:
          swap8words = 0
        else:
          swap8words = int(swap8words)
        swap = 8 if swap8words > 0 else 0
        segments.append( PdoSegment( s.text, 0, swap8words, swap ) )
    # look for prom data
    prom = None
    cat = el.find("Category")
    if not cat is None:
      for s in cat.findall("CatNo"):
        if ( s.text == FirmwareConstants.DEVSPECIFIC_CATEGORY_TXT() ):
          data = s.getnext()
          if (data.tag == "Data"):
            prom = bytearray.fromhex( data.text )
            break
    netCfg  = NetConfig()
    flags   = 0
    nLLSegs = 0
    rem     = 0
    evrCfg  = None
    xtraEvt = ExtraEvents()
    try:
      if (len(segments) > 0 and prom is None):
        raise Exception("WARNING: inconsistent vendor-specific data (Segment names found but no hex data); purging all segments!")
      if len(prom) < 1 + 12 + 1 + FirmwareConstants.EVR_NUM_PULSE_GENS() * 9 + 2:
        raise Exception("WARNING: truncated vendor-specific prom data; ignoring")

      if ( prom[0] != FirmwareConstants.EEPROM_LAYOUT_VERSION() ):
        raise Exception("WARNING: vendor-specific prom data version mismatch; ignoring")

      promIdx  = 1

      netCfg.setMacAddr( prom[promIdx +  0: promIdx +  6] )
      netCfg.setIp4Addr( prom[promIdx +  6: promIdx + 10] )
      netCfg.setUdpPort( prom[promIdx + 10: promIdx + 12] )
      promIdx += 12
      
      numPulseGens = prom[promIdx]
      promIdx += 1
      if ( numPulseGens > 16 ):
        raise Exception("WARNING: vendor-specific prom data has an unreasonable number of pulse generators; ignoring")
      evrCfg = []
      for i in range(numPulseGens):
        c = Evr320PulseParam()
        vals = [0,0]
        for v in range(len(vals)):
          for j in range(3, -1, -1):
            vals[v] = (vals[v] << 8) | prom[promIdx + j]
          promIdx += 4
        c.pulseDelay  = vals[1]
        c.pulseWidth  = vals[0] & ~(1<<31)
        c.pulseEnable = ( (vals[0] & (1<<31)) != 0 )
        c.pulseEvent  = prom[promIdx]
        promIdx      += 1
        evrCfg.append( c )

      for i in range(4):
        xtraEvt[i] = prom[promIdx]
        promIdx   += 1

      flags    = prom[promIdx] & FixedPdoPart.F_MASK
      promIdx += 1
      nLLSegs  = prom[promIdx]
      promIdx += 1

      if nLLSegs < len(segments):
        raise Exception("WARNING: configured low-level segments fewer than names found; purging all segments")
      if nLLSegs > ( len(prom) - 14 ) / 4:
        raise Exception("WARNING: configured low-level segments fewer than configured length; purging all segments")

      rem = nLLSegs
      for s in segments:
        needed = s.nDWords if 8 == s.swap else 1
        if needed > rem:
          raise Exception("WARNING: less low-level segments in prom descriptor than in VendorSpecific section; purging all segments")
        if ( 8 == s.swap ):
          for i in range(s.nDWords):
            tmp = PdoSegment.fromPromData( prom[promIdx:promIdx+4] )
            if tmp.swap != 4 or tmp.nDWords != 1:
              raise Exception("WARNING: low-level segment inconsistent with 8-byte swap; purging all segments")
            if ( 1 == i ):
              # we find the starting offset in segment #1 !
              s.byteOffset = tmp.byteOffset
            promIdx += 4
        else:
          tmp  = PdoSegment.fromPromData( prom[promIdx:promIdx+4] )
          promIdx += 4
          s.byteOffset = tmp.byteOffset
          s.nDWords    = tmp.nDWords
          s.swap       = tmp.swap
        rem -= needed
    except Exception as e:
      segments = []
      evrCfg   = None
      print(e.args[0])
    return clazz( el, segments, flags, netCfg, evrCfg, xtraEvt, *args, **kwargs )
    
class Pdo(object):

  def __init__(self, el, index, name, sm):
    self._firstElPos = -1
    if el is None:
      el = ET.Element("TxPdo")
      n  = ET.Element("Index")
      el.append( n )
      n  = ET.Element("Name")
      el.append( n )
      self._firstElPos = 2
    else:
      if el.find("Name") is None:
        # Index is mandatory
        el.insert( 1, ET.Element("Name") )
      for it in {"Entry" : 0, "Exclude" : 1, "Name" : 1, "Index" : 1}.items():
        e = el.find(it[0])
        print("Looking for ", it[0])
        if not e is None:
          self._firstElPos = el.index(e) + it[1]
          break
    if ( self._firstElPos < 1 ):
      raise ValueError("Pdo -- unable to determine position of first 'Entry' element")
      
    el.set("Fixed", "1")
    el.set("Mandatory", "1")
    self._el     = el
    self._ents   = []
    self.index   = index
    self.sm      = sm
    self.name    = name
    self._byteSz = 0
    self._used   = 0

  @property
  def element(self):
    return self._el

  def __getitem__(self, i):
    return self._ents[i]

  #Remove all entries and segments
  def purge(self):
    self._byteSz = 0
    self._used   = 0
    for e in self._el.findall("Entry"):
      self._el.remove( e )
    self._ents   = []

  @property
  def index(self):
    return self._index

  @index.setter
  def index(self, index):
    self._el.find("Index").text = int2hd( index, wid = 4 )
    self._index = index

  @property
  def sm(self):
    return self._sm

  @sm.setter
  def sm(self, val):
    self._el.set("Sm", str(val))
    self._sm = val

  @property
  def byteSz(self):
    return self._byteSz

  @property
  def name(self):
    return self._name

  @name.setter
  def name(self, val):
    self._el.find("Name").text = val
    self._name = val

  def addEntry(self, e):
    if not isinstance(e, PdoEntry):
      raise TypeError("Pdo.addEntry -- item you are trying to add is not a PdoEntry object")

    parent = None

    for elm in e.elements:

      for anc in elm.iterancestors():
        if not parent is None and parent != anc:
          raise ValueError("Internal error: PDOEntry with sub-elements that have different parents?")
        parent = anc
        break

      if not parent is None and parent != self._el:
        raise ValueError("This PDO is not the parent of the element you are trying to add")

    needed = e.byteSz * e.nelms
    if ( self._used + needed > self._byteSz ):
      raise ValueError("Pdo.addEntry -- does not fit in allocated segments")
    self._used += needed
    e._lock()
    self._ents.append( e )
    if parent is None:
      allent = self._el.findall("Entry")
      if 0 == len(allent):
        pos = self._firstElPos
      else:
        pos = self._el.index(allent[-1]) + 1
      self._el[pos:pos] = e.elements

  def gNod(el, tag, noneOk=False):
    rv = el.find(tag)
    if rv is None and not noneOk:
      raise KeyError("No '{}' Element in {}".format(tag, el.tag))
    return rv

  def gTxt(el, tag, noneOk=False ):
    rv = Pdo.gNod(el, tag, noneOk)
    if rv is None:
      return ""
    return rv.text

  def addPdoSegment(self, s):
    if not isinstance(s, PdoSegment):
      raise TypeError("Pdo.addPdoSegment -- item you are trying to add is not a PdoSegment object")
    if ( self._byteSz + s.nDWords * 4 > FirmwareConstants.ESC_SM_MAX_LEN( FirmwareConstants.TXPDO_SM() ) ):
      raise ValueError("Pdo.addPdoSegment -- adding this segment would exceed firmware TXPDO size limit")

    self._byteSz += s.nDWords * 4

  def update(self, segs, elms):
    # remove current content
    self.purge()
    # start adding segments
    for s in segs:
      self.addPdoSegment( s )
    for e in elms:
        self.addEntry( PdoEntry( None, e.name, e.index, e.nelms, 8*e.byteSz, e.isSigned, e.typeName, e.indexedName ) )

  @classmethod
  def fromElement(clazz, el, segments, sm = FirmwareConstants.TXPDO_SM(), *args, **kwargs):
    try:
      index = hd2int( clazz.gTxt(el, "Index") )
      name  = clazz.gTxt(el, "Name")
      pdo   = clazz( el, index, name, sm, *args, **kwargs )
      for s in segments:
        pdo.addPdoSegment(s)

      entLst     = []
      # sub-indices must be consecutive and adjacent
      lstIdx     = -1
      lstSub     = -1
      lstLen     = -1
      lstTyp     = None
      lstNam     = None
      # gather elements with common index in a list
      idxLst     = []
      for e in el.findall("Entry"):
        entIdx = hd2int( clazz.gTxt( e, "Index" ) )
        try:
          entSub = hd2int( clazz.gTxt( e, "SubIndex" ) )
          if ( 0 == entSub ):
            raise ValueError("PDO Entries cannot have SubIndex == 0")
        except KeyError as e:
          if ( entIdx != 0 ):
            raise(e)
          entSub = 1
        entLen = int( clazz.gTxt( e, "BitLen"         ) )
        entNam =      clazz.gTxt( e, "Name",     True )
        entTyp =      clazz.gTxt( e, "DataType", True )
        if ( 1 == entSub ):
          # start of new array
          if ( lstIdx >= 0 ):
            isSigned = not lstTyp is None and len(lstTyp) > 0 and lstTyp[0].upper() != "U"
            entLst.append( PdoEntry( idxLst, lstNam, lstIdx, lstSub, lstLen, isSigned, lstTyp ) )
          idxLst = [ e ]
          lstSub = 1
          lstIdx = entIdx
          lstLen = entLen
          lstTyp = entTyp
          lstNam = entNam
        elif ( lstIdx == entIdx and entSub == lstSub + 1 ):
          lstSub = entSub
          idxLst.append( e )
        else:
          raise ValueError("PDO Entries with SubIndex != 1 must be adjacent and contiguous")
      # deal with the last one
      if ( lstIdx >= 0 ):
        isSigned = not lstTyp is None and len(lstTyp) > 0 and lstTyp[0].upper() != "U"
        entLst.append( PdoEntry( idxLst, lstNam, lstIdx, lstSub, lstLen, isSigned, lstTyp ) )

      for pdoe in entLst:
        pdo.addEntry( pdoe )

    except Exception as e:
     print("Errors were found when processing " + el.tag)
     raise(e)

    return pdo

class ESI(object):

  def __init__(self, root = None):
    super().__init__()
    if root is None:
      root = ET.Element("EtherCATInfo")

      # note that XML schema expects these elements in order !
      vendor          = ET.SubElement(root, "Vendor")
      vendorId          = ET.SubElement(vendor,"Id")
      vendorId.text       = ESIDefaults.VENDOR_ID_TXT()
      vendorId          = ET.SubElement(vendor,"Name")
      vendorId.text       = ESIDefaults.VENDOR_NAME_TXT()

      descriptions    = ET.SubElement(root, "Descriptions")
      groups            = ET.SubElement(descriptions, "Groups")
      group               = ET.SubElement(groups, "Group")
      groupType             = ET.SubElement(group, "Type")
      groupType.text          = ESIDefaults.GROUP_TYPE_TXT()
      groupName             = ET.SubElement(group, "Name")
      groupName.text          = ESIDefaults.GROUP_NAME_TXT()

      devices           = ET.SubElement(descriptions, "Devices")
      device              = ET.SubElement(devices,"Device", Physics="YY")
      deviceType            = ET.SubElement(device, "Type",
                                ProductCode=ESIDefaults.DEVICE_PRODUCT_CODE_TXT(),
                                RevisionNo =ESIDefaults.DEVICE_REVISION_NO_TXT())
      deviceType.text         = ESIDefaults.DEVICE_TYPE_TXT()
      deviceName            = ET.SubElement(device, "Name")
      deviceName.text         = ESIDefaults.DEVICE_NAME_TXT()

      groupType             = ET.SubElement(device, "GroupType").text=ESIDefaults.GROUP_TYPE_TXT()
      fmmu                  = ET.SubElement(device, "Fmmu")
      fmmu.text               ="Inputs"
      fmmu                  = ET.SubElement(device, "Fmmu")
      fmmu.text               ="Outputs"
      fmmu                  = ET.SubElement(device, "Fmmu")
      fmmu.text               ="MBoxState"
      for i in range(4):
        ET.SubElement(device, "Sm")
    else:
      device = root.find("Descriptions/Devices/Device")
      if device is None:
        raise RuntimeError("'Device' node not found in XML -- fix XML or create from scratch")

    # While this is configurable nothing will actually happen unless firmware is using
    # the rxpdo. We assume some LEDs are hooked up.
    rxPdoEntries = PdoEntry(None, "LED", ESIDefaults.RXPDO_LED_INDEX(), 3, 8, False)
    rxPdo = ET.Element( "RxPdo" )
    rxPdo.set( "Fixed",     "1" )
    rxPdo.set( "Mandatory", "1" )
    rxPdo.set( "Sm",        str(FirmwareConstants.RXPDO_SM()) )
    ET.SubElement( rxPdo, "Index" ).text = ESIDefaults.RXPDO_INDEX_TXT()
    ET.SubElement( rxPdo, "Name"  ).text = "ECAT EVR RxData"
    rxPdo.extend( rxPdoEntries.elements )
    rxPdoLen = rxPdoEntries.byteSz * rxPdoEntries.nelms
    if ( rxPdoLen > FirmwareConstants.ESC_SM_MAX_LEN( FirmwareConstants.RXPDO_SM() ) ):
      raise ValueError("RxPDO size exceeds firmware limit")

    # SM configuration must match firmware
    sms = device.findall("Sm")
    if len(sms) < 4 and len(sms) > 0:
      raise RuntimeError("Unexpected number of 'Sm' nodes found (0 or >= 4 expected) -- fix XML or create from scratch")
    txt = [ "MBoxOut", "MBoxIn", "Outputs", "Inputs" ]
    if ( 0 == len(sms) ):
      sms = [ None for i in range(4) ]
    self._sms = []
    for i in range(4):
      self._sms.append( Sm( sms[i],
                        FirmwareConstants.ESC_SM_SMA(i),
                        FirmwareConstants.ESC_SM_LEN(i), 
                        FirmwareConstants.ESC_SM_SMC(i),
                        txt[i] ) )
    self._sms[ FirmwareConstants.RXPDO_SM() ].setSize( rxPdoLen )

    addOrReplace( device, rxPdo )
    # we'll deal with the TxPDO later (once we have our vendor data)

    mailbox = ET.SubElement( device, "Mailbox" )
    mailbox.set("DataLinkLayer", "1")
    mailboxEoE = ET.SubElement(mailbox, "EoE")
    mailboxEoE.set("IP", "1")
    mailboxEoE.set("MAC", "1")

    addOrReplace( device, mailbox )

    # parse or construct eeprom + vendor data
    found = device.find("Eeprom")
    if ( found is None ):
      self._vendorData = VendorData( None )
      # add to tree
      device.append( self._vendorData.element )
    else:
      self._vendorData = VendorData.fromElement( found )

    found = device.find("TxPdo")

    if ( found is None ):
      txPdo = Pdo( None, hd2int( ESIDefaults.TXPDO_INDEX_TXT() ), "ECAT EVR TxData", FirmwareConstants.TXPDO_SM() )
      device.insert( device.index( rxPdo ) + 1, txPdo.element )
    else:
      txPdo = Pdo.fromElement( found, self._vendorData.segments )
    self._txPdo = txPdo
    self._root  = root
    self.syncElms()

  def mustFind(self, tag, el=None):
    if el is None:
      el = self._root
    rv = el.find(tag)
    if rv is None:
      raise KeyError("Element '{}' not found".format( tag ) )
    return rv

  def findOpt(self, tag, dflt, el=None):
    if el is None:
      el = self._root
    rv = el.find(tag)
    return dflt if rv is None else rv.text

  def appendInt(self, prom, key, dflt=0, byteSz=4, el=None):
    if el is None:
      el = self._root
    l   = key.split("@")
    tag = l[0]
    val = dflt
    txt = None
    rv  = el.find(tag)
    if not rv is None:
      if ( len(l) > 1 ):
        txt = rv.get( l[1] )
      else:
        txt = rv.text
    if txt is None:
      if val is None:
        raise KeyError("Element '{}' not found".format( key ) )
    else:
      val = hd2int( txt )
    for i in range(byteSz):
      prom.append( (val & 0xff) )
      val >>= 8

  def pad(self, prom, l):
    prom.extend( bytearray([0 for i in range(l)]) )

  def appendMbx(self, prom, smNode):
    self.appendInt( prom, ".@StartAddress", dflt=None, byteSz=2, el=smNode )
    self.appendInt( prom, ".@DefaultSize",  dflt=None, byteSz=2, el=smNode )
   

  def appendCat(self, prom, catId, process, *args):
    prom.append( (catId >> 0) & 0xff )
    prom.append( (catId >> 8) & 0xff )
    pos = len(prom) # record position
    prom.append( 0x00 )
    prom.append( 0x00 )
    process(prom, *args)
    newpos = len(prom)
    catLen = newpos - pos + 2
    if ( (catLen % 2) != 0 ):
      prom.append( 0x00 )
      catLen += 1
    catLen = int( catLen/2 )
    prom[pos+0] = (catLen >> 0) & 0xff
    prom[pos+1] = (catLen >> 8) & 0xff

  def catGeneral(self, prom):
    print("CAT General")

  def catSm(self, prom, sms):
    for sm in sms: 
      self.appendInt( prom, ".@StartAddress", dflt=None, byteSz=2, el=sm )
      self.appendInt( prom, ".@DefaultSize",  dflt=None, byteSz=2, el=sm )
      self.appendInt( prom, ".@ControlByte",  dflt=None, byteSz=1, el=sm )
      prom.append(0x00)
      self.appendInt( prom, ".@Enable",       dflt=None, byteSz=1, el=sm )
 
      t = sm.text
      if   t == "Inputs":
        v = 0x04
      elif t == "Outputs":
        v = 0x03
      elif t == "MBoxIn":
        v = 0x02
      elif t == "MBoxOut":
        v = 0x01
      else:
        v = 0x00
      prom.append( (v & 0xff) )

  def catPdo(self, prom, pdos, strDict):
    print("CAT Pdo")
    pass

  def catFmmu(self, prom, fmmus):
    print("CAT Fmmu")
    l = 0
    for fmmu in fmmus:
      t = fmmu.text
      if   t == "Inputs":
        v = 0x02
      elif t == "Outputs":
        v = 0x01
      elif t == "MBoxState":
        v = 0x03
      else:
        v = 0xff
      prom.append( (v & 0xff) )
      l += 1
    if ( l % 2 != 0 ):
      prom.append( 0x00 )

  def catStrings(self, prom, strDict):
    nStrPos = len(prom)
    prom.append(0x00) # place holder for num Strings
    def addStr(s):
      if s is None or len(s) == 0:
        return
      if ( strDict.get( s ) is None ):
        if len(s) > 255:
          raise ValueError("Category Strings: string loo long")
        if ( prom[nStrPos] == 255 ):
          raise ValueError("Category Strings: too many strings")
        prom[nStrPos] += 1
        # add to dictionary
        strDict[s]     = prom[nStrPos]

        # add to prom
        prom.append( len(s) )
        prom.extend( bytearray( s.encode('ascii') ) )
    def findAddStr(pat):
      for e in self._root.findall(pat):
        addStr(e.text)
    findAddStr(".//TxPdo/Name")
    findAddStr(".//RxPdo/Name")
    findAddStr(".//RxPdo/Entry/Name")
    findAddStr(".//TxPdo/Entry/Name")
    findAddStr(".//Devices/Device/GroupType")
    findAddStr(".//Devices/Device/Type")
    findAddStr(".//Devices/Device/Name")

    if ( (len(prom) - nStrPos ) % 2 != 0 ):
      prom.append( 0x00 )
    for i in strDict:
      print(i)

  def catOther(self, prom, nod):
    # Only 'Data' is supported ATM
    print("CAT Other ", nod.find("CatNo").text )
    prom.extend( bytearray.fromhex( self.mustFind( "Data", nod ).text ) )

  def makeProm(self):
    prom = bytearray()
    prom.extend( bytearray.fromhex(self.mustFind(".//Eeprom/ConfigData").text) )
    self.appendInt( prom, ".//Vendor/Id",                       dflt=None )
    self.appendInt( prom, ".//Devices/Device/Type@ProductCode", dflt=0 )
    self.appendInt( prom, ".//Devices/Device/Type@RevisionNo",  dflt=0 )
    self.appendInt( prom, ".//Devices/Device/Type@SerialNo",    dflt=0 )
    self.pad(       prom, 8 )
    nod = self._root.find(".//Eeprom/BootStrap/Data")
    if not nod is None:
      d = bytearray.fromhex( nod.text )
    else:
      d = bytearray()
    d.extend([0 for i in range(8 - len(d))])
    prom.extend(d)
    sms = self._root.findall(".//Devices/Device/Sm")
    for idx in [ FirmwareConstants.RXMBX_SM(), FirmwareConstants.TXMBX_SM() ]:
      if ( len(sms) > idx ):
        self.appendMbx(prom, sms[idx])
      else:
        self.pad(prom, 4)
    val = 0
    nod = self._root.find(".//Devices/Device/Mailbox")
    if ( not nod is None ):
      for prot in {"AoE" : 0x01, "EoE" : 0x02, "CoE" : 0x04, "FoE" : 0x08,
                   "SoE" : 0x10, "VoE" : 0x20 }.items():
        if not nod.find(prot[0]) is None:
          val |= prot[1]
    prom.append( (val & 0xff) )
    prom.append( 0x00          )

    nod = self.mustFind(".//Eeprom/ByteSize")
    val = int( int(nod.text) * 8/1024 ) - 1
    prom.append( (val & 0xff) )
    prom.append( 0x01 ) # version 1 as per spec
    self.appendCat( prom, 30, self.catGeneral )
    
    fmmus = self._root.findall(".//Devices/Device/Fmmu")
    if ( len(fmmus) > 0 ):
      self.appendCat( prom, 40, self.catFmmu, fmmus )

    sms   = self._root.findall(".//Devices/Device/Sm")
    if ( len(sms) > 0 ):
      self.appendCat( prom, 43, self.catSm, sms )

    strDict = dict()

    self.appendCat( prom, 10, self.catStrings, strDict )

    txpdos = self._root.findall(".//Devices/Device/TxPdo")
    self.appendCat( prom, 50, self.catPdo, txpdos, strDict )

    rxpdos = self._root.findall(".//Devices/Device/RxPdo")
    self.appendCat( prom, 51, self.catPdo, rxpdos, strDict )

    for cat in self._root.findall(".//Eeprom/Category"):
      catNo = int( self.mustFind("CatNo", cat).text )
      self.appendCat( prom, catNo, self.catOther, cat )
    prom.append( 0xff )
    prom.append( 0xff )

  @property
  def element(self):
    return self._root

  @property
  def txPdo(self):
    return self._txPdo

  @property
  def vendorData(self):
    return self._vendorData

  def syncElms(self):
    self._sms[ FirmwareConstants.TXPDO_SM() ].setSize( self._txPdo.byteSz )
   
if __name__ == '__main__':

  parser = ET.XMLParser(remove_blank_text=True)

  nod = None if True  else ET.parse('keil.xml', parser).getroot()

  esi = ESI( nod )
  ET.ElementTree(esi.element).write( '-', pretty_print=True )

  if False:
    e = PdoEntry(None, "foo", 0x1100, 4, 16, False)
    print(e.typeName)
    print(e.name)
    print(e.index)
    print(e.nelms)
    print(e.bitSize)
    print(e.byteSz)
    print(e.isSigned)
    print(e.indexedName)
    e.typeName="FOOTYPE"
    e.name="barname"
    e.index=1
    e.bitSize = 32
    e.isSigned=1
    e.indexedName=False
    print(e.typeName)
    print(e.name)
    print(e.index)
    print(e.nelms)
    print(e.bitSize)
    print(e.byteSz)
    print(e.isSigned)
    print(e.indexedName)
    
    pdo = Pdo(None, 0x1600,"PDO",2)
    s = PdoSegment("S1", 0, 4)
    print( s.byteSz )
    print( e.byteSz, e.nelms )
    pdo.addPdoSegment(s)
    pdo.addEntry( e )
    
    ET.ElementTree(pdo._el).write( '-', pretty_print=True )
    sys.exit()
    et =ET.parse('feil.xml')
    nod = et.findall("//TxPdo")[0]
    
    pdo.fromElement(nod, [PdoSegment(8,0)], 2)
