#!/usr/bin/env python3

##############################################################################
##      Copyright (c) 2022#2023 by Paul Scherrer Institute, Switzerland
##      All rights reserved.
##  Authors: Till Straumann
##  License: GNU GPLv2 or later
##############################################################################

from   lxml      import etree as ET
from   functools import wraps
import sys
import io
import re
import copy
from   FirmwareConstants import FirmwareConstants
from   AppConstants      import ESIDefaults, HardwareConstants
from   ESIPromGenerator  import ESIPromGenerator
from   ClockDriver       import ClockDriver
import VersaClock6Driver # importing a driver registers it
import struct

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
      pd.append( size & 0xff )
      tmp = (size >> 8) & 0x03
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
    if typeName is None:
      typeName = ""
    self._typeName    = typeName
    # the following assignments define the order of sub-elements
    # in the associated XML when this is created from scratch.
    # The order has to adhere to the XML schema!
    self.index        = index
    self.syncElms( "SubIndex", [ int2hd( i+1, wid=2 ) for i in range( self.nelms ) ] )
    self.bitSize      = bitSize
    self.name         = name
    self.isSigned     = isSigned

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
       # remove old index
       val = re.sub('\[[^]]*[]]','', val)
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
      subVal = [ subVal for i in range( len(self._elmLst) ) ]
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

  def __init__(self, flags, names = None, helps = None):
    super().__init__()
    self._maxSegs     = FirmwareConstants.TXPDO_MAX_NUM_SEGMENTS()
    self._flags       = flags
    self._eventDWords = FirmwareConstants.TXPDO_NUM_EVENT_DWORDS()
    n                 = self._eventDWords
    if names is None:
      names = [ "TimestampHi",
                "TimestampLo",
                "EventSet",
                "TimestampLatch0Rising",
                "TimestampLatch0Falling",
                "TimestampLatch1Rising",
                "TimestampLatch1Falling" ]
      helps = [ "Timestamp (s) received by EVR via\n" + \
                "dedicated events 0x70/0x71/0x7d",
                "Timestamp (ns) received by EVR via\n" + \
                "dedicated events 0x7c (or event clock) / 0x7d",
                ("A bit-set of all events observed since\n" + \
                "the TxPDO was last sent. This adds {:d} DWORDS\n" + \
                "to the TxPDO.").format(n),
                "The DC time of LATCH0 raising",
                "The DC time of LATCH0 falling",
                "The DC time of LATCH1 raising",
                "The DC time of LATCH1 falling"]

    else:
      if ( len(names) != 7 ):
        raise ValueError("names of predefined items must be a list of 7 strings")
    self._fixed       = [
      { "name" : names[0], "size" : 32, "nelms": 1, "help" : helps[0] },
      { "name" : names[1], "size" : 32, "nelms": 1, "help" : helps[1] },
      { "name" : names[2], "size" : 32, "nelms": n, "help" : helps[2] },
      { "name" : names[3], "size" : 64, "nelms": 1, "help" : helps[3] },
      { "name" : names[4], "size" : 64, "nelms": 1, "help" : helps[4] },
      { "name" : names[5], "size" : 64, "nelms": 1, "help" : helps[5] },
      { "name" : names[6], "size" : 64, "nelms": 1, "help" : helps[6] },
    ]

  @property
  def flags(self):
    return self._flags

  # should only be used by subclass 
  def _setFlags(self, val):
    self._flags = val

  @property
  def eventDWords(self):
    return self._eventDWords

  # number of PDO 'Entry' elements (not byte sizes)
  @property
  def numEntries(self):
    rv = 0
    if ( (self.flags & self.F_WITH_TSTAMP) ):
      rv += 2
    if ( (self.flags & self.F_WITH_EVENTS) ):
      rv += 1
    if ( (self.flags & self.F_WITH_LTCH0R) ):
      rv += 1
    if ( (self.flags & self.F_WITH_LTCH0F) ):
      rv += 1
    if ( (self.flags & self.F_WITH_LTCH1R) ):
      rv += 1
    if ( (self.flags & self.F_WITH_LTCH1F) ):
      rv += 1
    return rv

  # size of PDO 'Entry' elements (in dwords)
  @property
  def numDWords(self):
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
  def fixedProperties(self):
    return self._fixed

  @property
  def maxNumSegments(self):
    return self._maxSegs

  def checkEntry( self, e, p, idx=None ):
    nm = p["name"]
    sz = p["size"]
    en = mustFind(e, "Name").text
    if ( not idx is None ):
      nm = "{}[{:d}]".format(nm, idx)
    if ( en != nm ):
      raise ValueError("Entry named '{}' not found".format(nm))
    if ( int( mustFind(e, "BitLen").text ) != sz ):
      raise ValueError("Bit length of {}('{}') unexpected (expected {:d})".format( e.tag, nm, sz ))

  def validateTxPdo(self, pdoEl):
    if ( pdoEl is None ):
      return
    entries = pdoEl.findall("Entry")
    eidx    = 0
    nidx    = 0
    # timestamp flag covers both 
    fset    = self._flags
    if ( (fset & self.F_WITH_TSTAMP) != 0 ):
      self.checkEntry( entries[eidx    ], self._fixed[nidx    ] )
      self.checkEntry( entries[eidx + 1], self._fixed[nidx + 1] )
      eidx += 2
      fset &= ~ self.F_WITH_TSTAMP
    nidx += 2
    if ( (self.flags & self.F_WITH_EVENTS) != 0 ):
      for i in range(self._eventDWords):
        self.checkEntry( entries[eidx], self._fixed[nidx], i + 1 )
        eidx += 1
      fset &= ~ self.F_WITH_EVENTS
    nidx += 1
    msk = self.F_WITH_EVENTS
    while ( ( nidx < len(self._fixed) ) and ( eidx < len(entries) ) ):
      msk <<= 1
      if ( ( fset & msk ) != 0 ):
        self.checkEntry( entries[eidx], self._fixed[nidx] )
        eidx += 1
      fset &= ~msk
      nidx += 1
    if ( fset != 0 ):
      raise ValueError("Not all required entries found!")

def mustFind(nod, sub):
  found = nod.find(sub)
  if found is None:
    raise KeyError("Mandatory element '{}' not found in '{}'".format(sub, nod.tag))
  return found

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

def findCat(nod, catId):
  for n in nod.findall( "Category" ):
    if ( int(catId) == int(n.find( "CatNo" ).text) ):
      return n
  raise KeyError("Category {:d} not found".format( catId ) )

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

  @classmethod
  def fromElement(clazz, el, *args, **kwargs):
    start = hd2int( el.get("StartAddress") )
    size  = hd2int( el.get("DefaultSize") )
    ctl   = hd2int( el.get("ControlByte") )
    txt   = el.text
    return clazz( el, start, size, ctl, txt)

class Configurable(object):
  def __init__(self):
    super().__init__()
    self._modified = False

  @property
  def modified(self):
    return self._modified

  def resetModified(self):
    self._modified = False

  def clone(self):
    return copy.copy(self)

class NoClockDriver(RuntimeError):
  def __init__(self, msg):
    super().__init__(msg)

class ClockConfig(Configurable):

  def __init__(self, freqMHz = 100.333, driverName = "VersaClock6"):
    super().__init__()
    try:
      self._drv = ClockDriver.findDriver( driverName )
    except KeyError:
      raise NoClockDriver("No driver for requested clock ({}) found".format( driverName ))
    self.setFreqMHz( freqMHz )
    self._modified = False

  @property
  def freqMHz(self):
    return self._freqMHz

  def setFreqMHz(self, f):
    f = float( f )
    self._freqMHz  = self.acceptable( f )
    self._modified = True

  # check if the requested frequency can be synthesized
  # returns actual frequency or raises a RuntimeError if
  # no close frequency can be produced
  def acceptable(self, f):
    if ( f < self.freqMHzLow ):
      raise RuntimeError("Event Frequency too low")
    if ( f > self.freqMHzHigh ):
      raise RuntimeError("Event Frequency too high")
    rdiv = self.getRateDiv( f )
    return self._drv.acceptable( f*rdiv )/rdiv

  # increase GTP rate divisor by a factor of two while using
  # double the event-frequency as a reference (necessary to
  # operate the GTP/PLL within specified range)
  def getRateDiv(self, f):
    if ( f < 80.0 ):
      return 2
    return 1

  def mkInitProg(self):
    rateDiv = self.getRateDiv( self.freqMHz )
    p = self._drv.mkInitProg( self.freqMHz*rateDiv )
    if ( 2 == rateDiv ):
      # switch the rate divisor
      addr = 0x180010
      val  = (1<<6)
      # reserve bytearray for 2 command bytes and two words
      p1   = bytearray(2 + 2*4)
      p1[0] = 0xfe     # bus access (not i2c)
      p1[1] = 2*4 - 1  # write (bit 7 == 0); nBytes - 1
      sreg  = (val << 32) | addr
      for i in range(2,len(p1)):
        p1[i] = (sreg & 0xff)
        sreg >>= 8
      p.extend( p1 )
    return p

  def driverName(self):
    return self._drv.name

  @property
  def freqMHzLow(self):
    # GTP PLL min freq 1.6GHz; at output div 4 (half rate) -> 40MHz
    return 40.0

  @property
  def freqMHzHigh(self):
    # design built for max. freq; this passes timing
    return 143.0

class EvrDCConfig(Configurable):
  def __init__(self, dcTarget = 0, freqMHz = 0):
    super().__init__()
    if ( 0 == freqMHz ):
      # assume they give us nano-seconds already
      self._DCTargetNS = dcTarget
    else:
      self._DCTargetNS = float(dcTarget) / 65536.0 * 1000.0 / freqMHz

  def setDCTargetNS(self, ns):
    self._DCTargetNS = ns
    self._modified      = True

  def getDCTargetNS(self):
    return self._DCTargetNS

  def promData(self, freqMHz):
    rv = bytearray(4)
    v  = int( round( freqMHz * self.getDCTargetNS() / 1000.0 * 65536.0 ) )
    if ( 0 > v ):
      v = 0
    elif ( v > 0xffffffff ):
      v = 0xffffffff
    for i in range(4):
      rv[i] = v & 255
      v   >>= 8
    return rv

  @staticmethod
  def fromPromDataClicks(prom):
    dcTgtClicks = 0
    for i in range(4):
       dcTgtClicks = (dcTgtClicks << 8) | prom[3 - i]
    return dcTgtClicks, 4

class NetConfig(Configurable):
  def __init__(self):
    super().__init__()
    self._macAddr  = bytearray( [255 for i in range(6)] )
    self._ip4Addr  = bytearray( [255 for i in range(4)] )
    self._udpPort  = bytearray( [255 for i in range(2)] )

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
    self._modified = True

  def setIp4Addr(self, a = "255.255.255.255"):
    if ( isinstance(a, bytearray) ):
      self._ip4Addr = a
    else:
      self._ip4Addr = self.convert(a, 4, ".", 10)
    self._modified = True

  def setUdpPort(self, a = 0xffff):
    if ( isinstance(a, bytearray) ):
      self._udpPort = a
    else:
      self._udpPort = self.convert(a, 2, None, None)
    self._modified = True

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

class Evr320PulseParam(Configurable):
  def __init__(self):
    super().__init__()
    self._enabled  = False
    self._width    = 4
    self._delay    = 0
    self._event    = 0
    self._invrt    = False

  @property
  def pulseEnabled(self):
    return self._enabled

  @pulseEnabled.setter
  def pulseEnabled(self, v):
    self._enabled  = v
    self._modified = True

  @property
  def pulseWidth(self):
    return self._width

  @pulseWidth.setter
  def pulseWidth(self, v):
    self._width    = v
    self._modified = True

  @property
  def pulseDelay(self):
    return self._delay

  @pulseDelay.setter
  def pulseDelay(self, v):
    self._delay    = v
    self._modified = True


  @property
  def pulseEvent(self):
    return self._event

  @pulseEvent.setter
  def pulseEvent(self, v):
    if ( v < 0 or v > 255 ):
      raise ValueError("Evr320PulseParams -- invalid event code")
    self._event    = v
    self._modified = True

  @property
  def pulseInvert(self):
    return self._invrt

  @pulseInvert.setter
  def pulseInvert(self, v):
    self._invrt    = not not v
    self._modified = True

  def promData(self):
    rv = bytearray()
    x  = self.pulseWidth & ~(3<<30)
    if self.pulseEnabled:
      x |= (1<<31)
    if self.pulseInvert:
      x |= (1<<30)
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

  def __init__(self, el, segments = [], flags = 0, netConfig = NetConfig(), evrParams = None, eventCodes = ExtraEvents(), clockConfig = ClockConfig(), evrDCConfig = EvrDCConfig(), fixedNames = None ):
    super().__init__(flags, fixedNames)
    if (el is None):
      el = ET.Element("Eeprom")
    else:
      self.validateTxPdo( el.find("../TxPdo") )
    self._netConfig = netConfig
    self._el        = el
    self._modified  = False
    if ( evrParams is None ):
      self._evrPulseParams = [ Evr320PulseParam() for i in range(FirmwareConstants.EVR_NUM_PULSE_GENS()) ]
    else:
      self._evrPulseParams = evrParams
    self._xtraEvents = eventCodes
    for i in range(len(self._xtraEvents)):
      self._xtraEvents[i] = 0x11*(i+1)

    self._clockConfig   = clockConfig
    self._evrDCConfig   = evrDCConfig

    self.update( self.flags, segments )
    self.resetModified()

  @property
  def modified(self):
    rv = self._modified or self._netConfig.modified or self._clockConfig.modified or self._evrDCConfig.modified
    for p in self._evrPulseParams:
      rv = rv or p.modified
    return rv

  def getEvrDCTargetNS(self):
    return self._evrDCConfig.getDCTargetNS()

  def setEvrDCTargetNS(self, v):
    self._evrDCConfig.setDCTargetNS( v )

  def resetModified(self):
    self._modified = False
    self._netConfig.resetModified()
    self._clockConfig.resetModified()
    self._evrDCConfig.resetModified()
    for p in self._evrPulseParams:
      p.resetModified()

  def getEvrPulseParam(self, idx):
    return self._evrPulseParams[idx]

  def getExtraEvent(self, idx):
    return self._xtraEvents[idx]

  def setExtraEvent(self, idx, val):
    self._xtraEvents[idx] = val
    self._modified        = True

  @property
  def netConfig(self):
    return self._netConfig

  @property
  def clockConfig(self):
    return self._clockConfig

  def update(self, flags, segments):
    self._setFlags( flags )
    self._segs      = []
    # make a copy
    for s in segments:
      self._segs.append( s.clone() )
    # add dummy segment for fixed / non-editable entries
    self._segs.insert(0, PdoSegment( "Fixed", 0, self.numDWords ))
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

    if (   ( FirmwareConstants.ESC_SM_MAX_LEN( 0 ) > FirmwareConstants.ESC_SM_LEN( 0 ) )
        or ( FirmwareConstants.ESC_SM_MAX_LEN( 1 ) > FirmwareConstants.ESC_SM_LEN( 1 ) ) ):
      data=bytearray()
      for i in range(2):
        ba = bytearray.fromhex("{:04x}".format(FirmwareConstants.ESC_SM_SMA(i)))
        ba.reverse()
        data.extend( ba )
        ba = bytearray.fromhex("{:04x}".format(FirmwareConstants.ESC_SM_MAX_LEN(i)))
        ba.reverse()
        data.extend( ba )
      se = findOrAdd( self._el, "BootStrap" )
      se.text = data.hex()

    for c in self._el.findall( "Category" ):
      self._el.remove(c)

    vdr = findOrAdd( self._el, "VendorSpecific" )
    for s in vdr.findall("Segment"):
      vdr.remove(s)
    for s in self._segs[1:]:
      sz64 = s.nDWords if s.swap == 8 else 0
      ET.SubElement(vdr, "Segment", Swap8="{}".format(sz64)).text = s.name
    for s in vdr.findall("ClockFreqMHz"):
      vdr.remove(s)
    ET.SubElement(
      vdr,
      "ClockFreqMHz",
      DriverName=self._clockConfig.driverName()
    ).text = "{:.8g}".format( self._clockConfig.freqMHz )

    for s in vdr.findall("EvrDCTargetNS"):
      vdr.remove(s)
    ET.SubElement(
      vdr,
      "EvrDCTargetNS",
    ).text = "{:.8g}".format( self.getEvrDCTargetNS() )

    cat = ET.SubElement( self._el, "Category" )
    se  = findOrAdd( cat, "CatNo" )
    se.text = FirmwareConstants.DEVSPECIFIC_CATEGORY_TXT()

    se  = findOrAdd( cat, "Data" )
    se.text = self.promData().hex()

    # categories must precede VendorSpecific
    self._el.insert( self._el.index( vdr ), cat )

    cat = ET.SubElement( self._el, "Category" )
    se  = findOrAdd( cat, "CatNo" )
    se.text = FirmwareConstants.I2C_INITPRG_CATEGORY_TXT()

    se  = findOrAdd( cat, "Data" )
    se.text = self.i2cInitProg().hex()

    # categories must precede VendorSpecific
    self._el.insert( self._el.index( vdr ), cat )


  @property
  def segments(self):
    return self._segs

  # Return the correct size to configure the SM -- this includes the
  # fixed segment!
  @property
  def byteSz(self):
    sz = 0
    for s in self.segments:
      sz += s.byteSz
    return sz

  def promData(self):
    actualSegs = 0
    for s in self.segments[1:]:
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
    prom.append( len( self._evrPulseParams )     )
    prom.extend( self._evrDCConfig.promData( self._clockConfig.freqMHz ) )
    for p in self._evrPulseParams:
      prom.extend( p.promData() )
    prom.extend( self._xtraEvents.promData() )
    prom.append( (self._flags & self.F_MASK) )
    prom.append( actualSegs )
    for s in self.segments[1:]:
      if ( s.nDWords > 0 ):
        prom.extend( s.promData() )
    return prom

  def i2cInitProg(self):
    p = bytearray()
    p.extend( self._clockConfig.mkInitProg() )
    # End marker
    p.append( 0xff )
    p.append( 0xff )
    return p

  @property
  def element(self):
    return self._el

  @classmethod
  def fromElement(clazz, el, *args, **kwargs):
    # look for segment names and 8-byte swap info
    segments = []
    vdr = el.find("VendorSpecific")
    clkFrqMHz = None
    clkDrvNam = None
    dcTgtNS   = 0.0
    if (not vdr is None):
      for s in vdr.findall("Segment"):
        swap8words = s.get("Swap8")
        if swap8words is None:
          swap8words = 0
        else:
          swap8words = int(swap8words)
        swap = 8 if swap8words > 0 else 0
        segments.append( PdoSegment( s.text, 0, swap8words, swap ) )
      s = vdr.find("ClockFreqMHz")
      if not s is None:
        clkDrvNam = s.get("DriverName")
        clkFrqMHz = float( s.text )
      s = vdr.find("EvrDCTargetNS")
      if not s is None:
        dcTgtNS = float( s.text )
    evrDCCfg = EvrDCConfig( dcTgtNS )
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
      if (prom is None):
        if (len(segments) > 0):
          raise Exception("WARNING: inconsistent vendor-specific data (Segment names found but no hex data); purging all segments!")
        else:
          raise Exception("WARNING: no prom data in XML")

      if len(prom) < 1 + 12 + 1 + FirmwareConstants.EVR_NUM_PULSE_GENS() * 9 + 2:
        raise Exception("WARNING: truncated vendor-specific prom data; ignoring")

      if ( prom[0] > FirmwareConstants.EEPROM_LAYOUT_VERSION() or prom[0] < 1 ):
        raise Exception("WARNING: vendor-specific prom data version mismatch; ignoring")

      promIdx  = 1

      netCfg.setMacAddr( prom[promIdx +  0: promIdx +  6] )
      netCfg.setIp4Addr( prom[promIdx +  6: promIdx + 10] )
      netCfg.setUdpPort( prom[promIdx + 10: promIdx + 12] )
      promIdx += 12

     
      numPulseGens = prom[promIdx]
      promIdx += 1

      if ( 1 == prom[0] ):
        print("WARNING: Old prom layout version; (no DC target) -- will upgrade when saving!", file=sys.stderr)
      else:
         dcTgt, l = EvrDCConfig.fromPromDataClicks(prom[promIdx:])
         promIdx += l
         # ignore the dcTgt (clicks) and use the float value from the XML instead
         # to avoid roundoff issues.
 
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
        c.pulseDelay   = vals[1]
        c.pulseWidth   = vals[0] & ~(1<<31)
        c.pulseEnabled = ( (vals[0] & (1<<31)) != 0 )
        c.pulseEvent   = prom[promIdx]
        promIdx       += 1
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
      if ( (nLLSegs > 0) and (0 == len(segments)) ):
        print("WARNING: found segments in PROM but have no VendorSpecific XML section; you are probably decoding", file=sys.stderr)
        print("         an old PROM. I'll create fake segments but any 8-byte swapping info is lost, beware!"    , file=sys.stderr)
        segments = [ PdoSegment( "DUMMY{:d}".format(i), 0, 0, 0) for i in range(nLLSegs) ]
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
      clkCfg = ClockConfig( clkFrqMHz, clkDrvNam )
    except NoClockDriver as e:
      print("No Clock Driver ({}) - using defaults".format( str( e ) ), file=sys.stderr )
      clkCfg   = ClockConfig()
    except Exception as e:
      segments = []
      evrCfg   = None
      clkCfg   = ClockConfig()
      print("Exception when trying to construct from XML ({}) - using defaults".format( str( e ) ), file=sys.stderr )
    return clazz( el, segments, flags, netCfg, evrCfg, xtraEvt, clkCfg, evrDCCfg, *args, **kwargs )
    
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
        if not e is None:
          self._firstElPos = el.index(e) + it[1]
          break
    if ( self._firstElPos < 1 ):
      raise ValueError("Pdo -- unable to determine position of first 'Entry' element")
      
    el.set("Fixed", "1")
    el.set("Mandatory", "1")
    self._el      = el
    self._ents    = []
    self.index    = index
    self.sm       = sm
    self.name     = name
    self._segsSz  = 0
    self._used    = 0
    self._pdoSize = 0

  def pdoSize(self):
    return self._pdoSize

  @property
  def element(self):
    return self._el

  def __getitem__(self, i):
    return self._ents[i]

  #Remove all entries and segments
  def purge(self):
    self._segsSz  = 0
    self._used    = 0
    for e in self._el.findall("Entry"):
      self._el.remove( e )
    self._ents    = []
    self._pdoSize = 0

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
  def name(self):
    return self._name

  @name.setter
  def name(self, val):
    self._el.find("Name").text = val
    self._name = val

  def addEntry(self, e, toTreeOnly=False):
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

    if ( not toTreeOnly ):
      needed = e.byteSz * e.nelms
      if ( self._used + needed > self._segsSz ):
        print("used {}, needed {}, current size {}".format(self._used, needed, self._segsSz))
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
    # pdoSize measures managed *and* unmanaged elements
    self._pdoSize += e.byteSz * e.nelms

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
    if ( self._segsSz + s.nDWords * 4 > FirmwareConstants.ESC_SM_MAX_LEN( FirmwareConstants.TXPDO_SM() ) ):
      raise ValueError("Pdo.addPdoSegment -- adding this segment would exceed firmware TXPDO size limit")

    self._segsSz += s.nDWords * 4

  def update(self, segs, externalElements, managedElements):
    # remove current content
    self.purge()
    # start adding segments
    for s in segs:
      self.addPdoSegment( s )
    for e in externalElements:
        self.addEntry(
          PdoEntry( None, e.name, e.index, e.nelms, 8*e.byteSz, e.isSigned, e.typeName, e.indexedName ),
          toTreeOnly = True
        )
    for e in managedElements:
        self.addEntry(
          PdoEntry( None, e.name, e.index, e.nelms, 8*e.byteSz, e.isSigned, e.typeName, e.indexedName ),
          toTreeOnly = False
        )

  @classmethod
  def fromElement(clazz, el, segments, sm = FirmwareConstants.TXPDO_SM(), *args, **kwargs):
    try:
      index = hd2int( clazz.gTxt(el, "Index") )
      name  = clazz.gTxt(el, "Name")
      pdo   = clazz( el, index, name, sm, *args, **kwargs )

      if ( not segments is None ):
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

      if ( not segments is None ):
        for pdoe in entLst:
          pdo.addEntry( pdoe )

    except Exception as e:
     print("Errors were found when processing " + el.tag)
     raise(e)

    return pdo

class XMLBase(object):

  @staticmethod
  def mkBasicTree(useDefaults = True):
    root = ET.Element("EtherCATInfo")

    # note that XML schema expects these elements in order !
    vendor          = ET.SubElement(root, "Vendor")
    vendorId          = ET.SubElement(vendor,"Id")
    if ( useDefaults ):
      vendorId.text       = ESIDefaults.VENDOR_ID_TXT()
    vendorId          = ET.SubElement(vendor,"Name")
    if ( useDefaults ):
      vendorId.text       = ESIDefaults.VENDOR_NAME_TXT()

    descriptions    = ET.SubElement(root, "Descriptions")
    groups            = ET.SubElement(descriptions, "Groups")
    group               = ET.SubElement(groups, "Group")
    groupType             = ET.SubElement(group, "Type")
    if ( useDefaults ):
      groupType.text          = ESIDefaults.GROUP_TYPE_TXT()

    groupName             = ET.SubElement(group, "Name")
    if ( useDefaults ):
      groupName.text          = ESIDefaults.GROUP_NAME_TXT()

    devices           = ET.SubElement(descriptions, "Devices")
    device              = ET.SubElement(devices,"Device")
    if ( useDefaults ):
      device.set("Physics", "YY")
    deviceType            = ET.SubElement(device, "Type")
    if ( useDefaults ):
      deviceType.set( "ProductCode", ESIDefaults.DEVICE_PRODUCT_CODE_TXT() )
      deviceType.set( "RevisionNo" , ESIDefaults.DEVICE_REVISION_NO_TXT()  )
      deviceType.text = ESIDefaults.DEVICE_TYPE_TXT()

    deviceName            = ET.SubElement(device, "Name")
    if ( useDefaults ):
      deviceName.text         = ESIDefaults.DEVICE_NAME_TXT()

    ET.SubElement(device, "Info")

    groupType             = ET.SubElement(device, "GroupType")
    if ( useDefaults ):
      groupType.text        = ESIDefaults.GROUP_TYPE_TXT()
      fmmu                  = ET.SubElement(device, "Fmmu")
      fmmu.text               ="Outputs"
      fmmu                  = ET.SubElement(device, "Fmmu")
      fmmu.text               ="Inputs"
      fmmu                  = ET.SubElement(device, "Fmmu")
      fmmu.text               ="MBoxState"
      for i in range(4):
        ET.SubElement(device, "Sm")
    return root

  def __init__(self, root = None):
    if root is None:
      root = self.mkBasicTree()
    self._root = root

  def writeXML(self, fnam, pre=''):
    if ( isinstance(fnam, io.TextIOWrapper) ):
      txt = self.toString().split('\n')
      if ( len(txt[-1]) == 0 ):
        del( txt[-1] )
      for lin in txt: 
        print('{}{}'.format(pre, lin), file=fnam)
    else:
      closeFd = True
      if fnam == '-':
        fnam    = sys.stdout.fileno()
        closeFd = False
      with io.open(fnam, 'w', closefd = closeFd) as f:
        self.writeXML( f, pre )

  def toString(self):
    et = ET.ElementTree(self._root)
    st = ET.tostring( et, xml_declaration = True, method = "xml", pretty_print=True, encoding='utf-8')
    return st.decode()

class ESI(XMLBase):

  def __init__(self, root = None):
    super().__init__( root )
    root = self._root
    device = root.find("Descriptions/Devices/Device")
    if device is None:
      raise RuntimeError("'Device' node not found in XML -- fix XML or create from scratch")

    # SM configuration must match firmware
    sms = device.findall("Sm")
    if len(sms) < 4 and len(sms) > 0:
      raise RuntimeError("Unexpected number of 'Sm' nodes found (0 or >= 4 expected) -- fix XML or create from scratch")
    smType = [ "MBoxOut", "MBoxIn", "Outputs", "Inputs" ]
    self._sms = []

    found = device.find( "RxPdo" )
    if ( found is None ):
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

      if ( 0 == len(sms) ):
        sms = [ None for i in range(4) ]

      for i in range(4):
        self._sms.append( Sm( sms[i],
                          FirmwareConstants.ESC_SM_SMA(i),
                          FirmwareConstants.ESC_SM_LEN(i),
                          FirmwareConstants.ESC_SM_SMC(i),
                          smType[i] ) )
      self._sms[ FirmwareConstants.RXPDO_SM() ].setSize( rxPdoLen )

      addOrReplace( device, rxPdo )
    else:
      rxPdo = Pdo.fromElement( found, None, int( found.get("Sm") ) )
      for sm in sms:
        self._sms.append( Sm.fromElement( sm ) )

    # we'll deal with the TxPDO later (once we have our vendor data)

    found = device.find( "Mailbox" )

    if ( found is None ):
      mailbox = ET.SubElement( device, "Mailbox" )
      mailbox.set("DataLinkLayer", "1")
     
      if ( FirmwareConstants.EOE_ENABLED() ):
         mailboxEoE = ET.SubElement(mailbox, "EoE")
         mailboxEoE.set("IP", "1")
         mailboxEoE.set("MAC", "1")
      if ( FirmwareConstants.FOE_ENABLED() ):
         mailboxFoE = ET.SubElement(mailbox, "FoE")
      if ( FirmwareConstants.VOE_ENABLED() ):
         mailboxFoE = ET.SubElement(mailbox, "VoE")

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
      txPdo = Pdo.fromElement( found, self._vendorData.segments, int( found.get("Sm") ) )
    self._txPdo = txPdo
    self.syncElms()

  @property
  def element(self):
    return self._root

  @property
  def txPdo(self):
    return self._txPdo

  @property
  def vendorData(self):
    return self._vendorData

  def update(self):
    self.syncElms()

  def syncElms(self):
    self._sms[ FirmwareConstants.TXPDO_SM() ].setSize( self.txPdo.pdoSize() )

  @staticmethod
  def addVndCat(eepNod, catId, dat):
    vndNod = eepNod.find("VendorSpecific")
    catNod = ET.Element("Category")
    ET.SubElement(catNod, "CatNo").text = str( catId )
    ET.SubElement(catNod, "Data").text  = dat.hex()
    try:
      eepNod.remove( findCat( eepNod, catId ) )
    except KeyError:
      pass
    eepNod.insert( eepNod.index( vndNod ), catNod )
    
  def _getAndMaybeBumpRev(self, bump=False):
    nod = mustFind( self._root, ".//Device/Type" )
    rev = hd2int( nod.get("RevisionNo") )
    if ( bump ):
      nod.set("RevisionNo", int2hd( rev + 1 ))
    return rev

  def getRevision(self):
    return self._getAndMaybeBumpRev()

  def bumpRevision(self):
    return self._getAndMaybeBumpRev( True )
   
  def makeProm(self):
    # fixup vendor-specific data
    pgen   = ESIPromGenerator( self._root )
    eepNod = mustFind( self._root, ".//Device/Eeprom" )
    vndNod = eepNod.find("VendorSpecific")
    if not vndNod is None:
      nod    = vndNod.find("ClockFreqMHz")
      if not nod is None:
        drvId   = FirmwareConstants.CLK_DRIVER_MAP( nod.get("DriverName") )
        freqMHz = float( nod.text )
        catId   = FirmwareConstants.CLK_FREQ_VND_CAT_ID()
        dat     = bytearray()
        dat.append( drvId )
        dat.extend( struct.pack( '<d', freqMHz ) )
        self.addVndCat( eepNod, catId, dat )
      nod = vndNod.find("EvrDCTargetNS")
      if not nod is None:
        catId   = FirmwareConstants.EVR_DC_TARGET_VND_CAT_ID()
        dat     = struct.pack( '<d', float( nod.text ) )
        self.addVndCat( eepNod, catId, dat )
        dat     = bytearray()
        for nod in vndNod.findall("Segment"):
          dat.append( pgen.findAddStr( nod.text ) )
          dat.append( int( nod.get( "Swap8" ) )   )
        self.addVndCat( eepNod, FirmwareConstants.SEGNAMES_VND_CAT_ID(), dat )
    return pgen.makeProm()

  @staticmethod
  def fromProm(fnam):
    with io.open(fnam, 'rb') as f:
      prom = f.read()
    rootNod, strs = ESIPromGenerator( ESI.mkBasicTree( False ) ).parseProm( prom )
    eepNod  = mustFind( rootNod, ".//Device/Eeprom" )
    vndNod  = findOrAdd( eepNod, "VendorSpecific" )
    try:
      catNod  = findCat(eepNod, FirmwareConstants.CLK_FREQ_VND_CAT_ID())
    except KeyError:
      catNod  = None
      print("Vendor Category (ClockFreqMHz support) not found -- ignoring", file=sys.stderr)
    if not catNod is None:
      dat      = bytearray.fromhex( catNod.find("Data").text )
      drvNam   = FirmwareConstants.CLK_DRIVER_MAP( dat[0] )
      freqMHz  = struct.unpack( '<d', dat[1:9] )[0]
      eepNod.remove( catNod )
      nod      = ET.Element( "ClockFreqMHz", DriverName=drvNam )
      nod.text = str( freqMHz )
      addOrReplace( vndNod, nod )
    try:
      catNod  = findCat(eepNod, FirmwareConstants.EVR_DC_TARGET_VND_CAT_ID())
    except KeyError:
      catNod  = None
      print("Vendor Category (EvrDCTargetsNS support) not found -- ignoring", file=sys.stderr)
    if not catNod is None:
      dat      = bytearray.fromhex( catNod.find("Data").text )
      dcTgtNS  = struct.unpack( '<d', dat[0:8] )[0]
      nod      = ET.Element( "EvrDCTargetNS" )
      nod.text = str( dcTgtNS )
      addOrReplace( vndNod, nod )
    try:
      catNod  = findCat(eepNod, FirmwareConstants.SEGNAMES_VND_CAT_ID())
    except KeyError:
      catNod  = None
      print("Vendor Category (Segment name support) not found -- ignoring", file=sys.stderr)
    if not catNod is None:
      dat      = bytearray.fromhex( catNod.find("Data").text )
      eepNod.remove( catNod )
      for i in range(0,len(dat),2):
         segNod      = ET.SubElement(vndNod, "Segment")
         sidx        = dat[i]
         if sidx > 0:
           segNod.text = strs[ sidx - 1 ]
         segNod.set( "Swap8", str(dat[i+1]) )
    if 0 == len(vndNod):
      eepNod.remove( vndNod )
        
    return rootNod

  def writeProm(self, fnam, overwrite=False, prom = None):
    mode = "wb" if overwrite else "xb"
    if ( '-' == fnam ):
      fnam    = sys.stdout.fileno()
      closefd = False
    else:
      closefd = True

    if prom is None:
      prom = self.makeProm()

    with io.open( fnam, mode=mode, closefd=closefd ) as f:
      f.write( prom )

  def _resolveOpen(self, fnam, flg):
    if ( isinstance(fnam, io.TextIOWrapper) ):
      return fnam
    elif isinstance(fnam, int):
      pass
    if ( fnam == '-' ):
      fnam = sys.stdout.fileno()
    return io.open(fnam, flg)

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
