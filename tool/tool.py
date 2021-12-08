#!/usr/bin/env python3
from   lxml      import etree as ET
from   functools import wraps
import sys

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

class Segment(object):

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
      raise ValueError("Segment.byteOffset must be 4-aligned int")
    self._off = val

  @property
  def swap(self):
    return self._swap

  @swap.setter
  def swap(self, val):
    if ( not isinstance(val, int) or not val in [0,1,2,4] ):
      raise ValueError("Segment.swap")
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
    if ( not isinstance(val, int) or (val < 0) ):
      raise ValueError("Segment.nDWords must be an int >= 0")
    self._n = val

  def __init__(self, nDWords, byteOffset, swap = 0):
    self._isLocked  = False
    self.nDWords    = nDWords
    self.byteOffset = byteOffset
    self.swap       = swap

class PdoEntry(object):

  def __init__(self, elmLst, name, index, nelms, bitSize, isSigned, typeName=None, indexedName=True):
    object.__init__(self)
    # initialize private vars because setters cross-check
    # and they must exist
    self._elmLst      = elmLst
    if ( elmLst is None ): 
      self._elmLst = []
      for i in range(nelms):
        self._elmLst.append( ET.Element( "Entry" ) )
    
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
      se = e.find(subEl)
      if ( se is None ):
        se = ET.SubElement( e, subEl )
      se.text = str( subVal[i] )
      i += 1

class Pdo(object):

  def __init__(self, index, name, sm):
    self._segs   = []
    self._ents   = []
    self._index  = index
    self._sm     = sm
    self._byteSz = 0
    self._used   = 0

  @property
  def index(self):
    return self._index

  @index.setter
  def index(self, index):
    self._index = index

  @property
  def sm(self):
    return self._sm

  @sm.setter
  def sm(self, val):
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
    self._name = val

  def addEntry(self, e):
    if not isinstance(e, PdoEntry):
      raise TypeError("Pdo.addEntry -- item you are trying to add is not a PdoEntry object")
    needed = e.byteSz * e.nelms
    if ( self._used + needed > self._byteSz ):
      raise ValueError("Pdo.addEntry -- does not fit in allocated segments")
    self._used += needed
    e._lock()
    self._ents.append( e )

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

  def addSegment(self, s):
    if not isinstance(s, Segment):
      raise TypeError("Pdo.addSegment -- item you are trying to add is not a Segment object")
    self._byteSz += s.nDWords * 4
    s._lock()
    self._segs.append( s )

  @staticmethod
  def fromElement(el, segments, sm):
    try:
      index = hd2int( Pdo.gTxt(el, "Index") )
      name  = Pdo.gTxt(el, "Name")
      pdo   = Pdo( index, name, sm )
      for s in segments:
        pdo.addSegment(s)

      entLst     = []
      # sub-indices must be consecutive and adjacent
      lstIdx     = -1
      lstSub     = -1
      lstLen     = -1
      lstTyp     = None
      lstNam     = None
      # gather elements with common index in a ist
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

pdo = Pdo(0x1600,"PDO",2)
s = Segment(4, 0)
print( s.byteSz )
print( e.byteSz, e.nelms )
pdo.addSegment(s)
pdo.addEntry( e )

et =ET.parse('feil.xml')
nod = et.findall("//TxPdo")[0]

pdo.fromElement(nod, [Segment(8,0)], 2)
