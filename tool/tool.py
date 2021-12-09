#!/usr/bin/env python3
from   lxml      import etree as ET
from   functools import wraps
import sys
import copy
from   FirmwareConstants import FirmwareConstants, HardwareConstants

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

  # lock only to be modified by holding Pdo class
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
  def nDWords(self):
    return self._n

  @property
  def byteSz(self):
    return self._n * 4

  @nDWords.setter
  @lockCheck
  def nDWords(self, val):
   if not isinstance(val, int) or val <= 0 or val > 1024:
     raise ValueError("PdoSegment.nDWords not an int or out of range")
   if ( 8 == self.swap and (val % 2) != 0 ):
     raise ValueError("PdoSegment.nDWords of a 8-byte swapped segment must be even")
   self._n = val

  def promData(self):
    pd = bytearray()
    if ( 8 == self.swap ):
      nentries = self.nDwords
      size     = 1
      off      = self.byteOffset + 4
    else:
      size     = self.nDwords
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
    self._byteSz = val/8
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

  F_MASK        = (self.F_WITH_LTCH1F << 1) - 1

  def __init__(self, flags, names = None):
    super().__init__()
    self._maxSegs = FirmwareConstants.PDO_MAX_NUM_SEGMENTS()
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
    self._eventDWords = FirmwareConstants.PDO_MAX_EVENT_DWORDS()

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
    nidx + 1
    msk = self.F_WITH_EVENTS
    while ( ( nidx < len(self._names) ) and ( eidx < len(entries) ) ):
      msk <<= 1
      if ( ( fset & msk ) != 0 ):
        self.checkEntry( entries[eidx], self._names[nidx] )
      fset &= ~msk
    if ( fst != 0 ):
      raise ValueError("Not all required entries found!")

def findOrAdd(nod, sub):
  found = nod.find(sub)
  if found is None:
    found = ET.SubElement(nod, sub)
  return found

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
    self._el.set("ControlByte",  "#x{:02x}".format(ctl))
    self._el.set("StartAddress", "#x{:04x}".format(start))
    self._el.text = txt
    self.syncElms()

  def setSize(self, size):
    self._ena  = (size != 0 and self._ctl != 0)
    self._size = size
    self.syncElms()

  def syncElms(self):
    self._el.set("DefaultSize",  "{:d}".format(self._size))
    self._el.set("Enable",       "{:d}".format(self._ena))

class VendorData(FixedPdoPart):

  def __init__(self, el, segments = [], flags = 0, netConfig = None, fixedNames = None)
    super().__init__(flags, fixedNames)
    if (el is None):
      el = ET.Element("Eeprom")
    self._segs      = segments
    self._netConfig = netConfig
    self._el        = el

  def syncElms(self):
    self._el.set("AssignToPdi", "1")

    se = findOrAdd( self._el, "ByteSize" )
    se.text = str( HardwareConstants.EEPROM_SIZE_BYTES() )

    se = findOrAdd( self._el, "ConfigData" )
    se.text = FirmwareConstants.EEPROM_CONFIG_DATA_TXT()

    cat = findOrAdd( el, "Category" )
    se  = findOrAdd( cat, "CatNo" )
    se.text = FirmwareConstants.DEVSPECIFIC_CATEGORY_TXT()

    se  = findOrAdd( cat, "Data" )
    se.text = hex( self.promData() )

    vdr = findOrAdd( el, "VendorSpecific" )
    for s in vdr.findall("Segment"):
      vdr.remove(s)
    for s in self._segs:
      sz64 = s.nDWords if s.swap == 8 else 0
      ET.SubElement(el, "Segment", Swap8Len="{}".format(sz64)).text = s.name


  def promData(self):
    actualSegs = 0
    for s in segments:
      if (8 == s.swap ):
        actualSegs += s.nDWords
      elif s.nDWords > 0:
        actualSegs += 1
    # last-ditch check; this should have been rejected earlier!
    if ( actualSegs > self.maxNumSegments ):
      raise ValueError("Too many segments")
    prom = self._netConfig.promData()
    prom.append( (self._flags & self.F_MASK) )
    prom.append( actualSegs )
    for s in segments:
      if ( s.nDWords > 0 ):
        prom.extend( s.promData )

  @staticmethod
  def fromElement(el):
    # look for segment names and 8-byte swap info
    segments = []
    vdr = el.find("VendorSpecific")
    if (not vdr is None):
      for s in vdr.findall("Segment"):
        swap8words = s.get("Swap8Len")
        if swap8words is None:
          swap8words = 0
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
    try:
      if (len(segments) > 0 and prom is None):
        raise Exception("WARNING: inconsistent vendor-specific data (Segment names found but no hex data); purging all segments!")
      if len(prom) < 14:
        raise Exception("WARNING: truncated vendor-specific prom data; ignoring")

      netCfg.setMacAddr( prom[ 0: 6] )
      netCfg.setIp4Addr( prom[ 6:10] )
      netCfg.setUdpPort( prom[10:12] )

      flags   = prom[13] & self.F_MASK
      nLLSegs = prom[14]

      if nLLSegs < len(segments):
        raise Exception("WARNING: configured low-level segments fewer than names found; purging all segments")
      if nLLSegs > ( len(prom) - 14 ) / 4:
        raise Exception("WARNING: configured low-level segments fewer than configured length; purging all segments")

      rem = nLLSegs
      idx = 14
      for s in segments:
        needed = s.nDWords if 8 == s.swap else 1
        if needed > rem:
          raise Exception("WARNING: less low-level segments in prom descriptor than in VendorSpecific section; purging all segments")
        if ( 8 == s.swap ):
          for i in range(s.nDWords):
            tmp = PdoSegment.fromPromData( prom[idx:idx+4] )
            if tmp.swap != 4 or tmp.nDWords != 1:
              raise Exception("WARNING: low-level segment inconsistent with 8-byte swap; purging all segments")
            if ( 1 == i ):
              # we find the starting offset in segment #1 !
              s.byteOffset = tmp.byteOffset
            idx += 4
        else:
          tmp  = PdoSegment.fromPromData( prom[idx:idx+4] )
          idx += 4
          s.byteOffset = tmp.byteOffset
          s.nDWords    = tmp.nDWords
          s.swap       = tmp.swap
        rem -= needed
    except Exception as e:
      segments = []
      print( e.args[0] )
    return PdoSegment( el, segments, flags, netConfig )
    
class Pdo(object):

  def __init__(self, el, index, name, sm):
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
      for it in {"Entry" : 0, "Exclude" : 1, "Name" : 1, "Index" : 1}:
        e = el.find(it[0])
        if not e is None:
          self._firstElPos = el.index(e) + it[1]
          break
    el.set("Fixed", "1")
    el.set("Mandatory", "1")
    self._el     = el
    self._segs   = []
    self._ents   = []
    self.index   = index
    self.sm      = sm
    self.name    = name
    self._byteSz = 0
    self._used   = 0

  #Remove all entries and segments
  def purge(self):
    self._segs   = []
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
    rv = 0
    for s in self._segs:
      rv += s.byteSz
    return rv

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
    self._byteSz += s.nDWords * 4
    s._lock()
    self._segs.append( s )

  def syncElms(self, segs, elms):
    # remove current content
    self.purge()
    # start adding segments
    for s in segs:
      # must copy the data -- the originals may still be
      # modified by the caller
      self.addPdoSegment( copy.copy(s) )
    for e in elms:
        self.addEntry( PdoEntry( None, e.name, e.index, e.nelms, 8*e.byteSz, e.isSigned, e.typeName, e.indexedName ) )

  @staticmethod
  def fromElement(el, segments, sm):
    try:
      index = hd2int( Pdo.gTxt(el, "Index") )
      name  = Pdo.gTxt(el, "Name")
      pdo   = Pdo( el, index, name, sm )
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
        entIdx = hd2int( Pdo.gTxt( e, "Index" ) )
        try:
          entSub = hd2int( Pdo.gTxt( e, "SubIndex" ) )
          if ( 0 == entSub ):
            raise ValueError("PDO Entries cannot have SubIndex == 0")
        except KeyError as e:
          if ( entIdx != 0 ):
            raise(e)
          entSub = 1
        entLen = int( Pdo.gTxt( e, "BitLen"         ) )
        entNam =      Pdo.gTxt( e, "Name",     True )
        entTyp =      Pdo.gTxt( e, "DataType", True )
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

class NetConfig(object):
  def __init__(self):
    object.__init__(self)
    self.macAddr = bytearray( [255 for i in range(6)] )
    self.ip4Addr = bytearray( [255 for i in range(4)] )
    self.udpPort = bytearray( [255 for i in range(2)] )

  def setMacAddr(self, a = "ff:ff:ff:ff:ff:ff"):
    if ( isinstance(a, bytearray) ):
      self.macAddr = a
    else:
      self.macAddr = self.convert(a, 6, ":", 16)

  def setIp4Addr(self, a = "255.255.255.255"):
    if ( isinstance(a, bytearray) ):
      self.ip4Addr = a
    else:
      self.ip4Addr = self.convert(a, 4, ".", 10)

  def setUdpPort(self, a = 0xffff):
    if ( isinstance(a, bytearray) ):
      self.udpPort = a
    else:
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

   
if __name__ == '__main__':

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
