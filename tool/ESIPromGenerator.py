from lxml import etree as ET
import sys
from collections import OrderedDict

class PromRd(object):
  def __init__(self, prom):
    self._pidx = 0
    self._prom = prom

  def skip(self, n=1):
    self._pidx += n

  def getInt(self, byteSz = 4):
    val = 0
    for i in range(byteSz - 1 , -1 , -1):
      val = (val << 8) | self._prom[i + self._pidx]
    self._pidx += byteSz
    return val

  def getUInt8(self):
    return self.getInt(1)

  def getUInt16(self):
    return self.getInt(2)

  def getUInt32(self):
    return self.getInt(4)

  def getBytes(self, n):
    rv = self._prom[self._pidx:self._pidx + n]
    self._pidx += n
    return rv

  @property
  def pos(self):
    return self._pidx

class Cat(PromRd):

  def __init__(self, prom, catId = 0):
    super().__init__(prom)
    self._id   = -1
    self._size = 0
    self._head = 0
    if ( 0 == catId ):
      self.next()
    else:
      while ( self.id != catId ):
        self.next()

  @property
  def id(self):
    return self._id

  @property
  def size(self):
    return self._size

  @property
  def head(self):
    return self._head

  def next(self):
    self.skip( self.size - (self.pos - self.head) )
    self._id   = self.getUInt16()
    if ( self._id == 0xffff ):
        raise KeyError("Category not found")
    self._size = self.getUInt16() * 2
    self._head = self.pos


class ESIPromGenerator(object):

  BASE_TYPE_MAP = {
    "BOOLEAN"      : 0x0001,
    "BOOL"         : 0x0001,
    "BIT"          : 0x0001,
    "BYTE"         : 0x001E,
    "WORD"         : 0x001F,
    "DWORD"        : 0x0020,
    "BIT1"         : 0x0030,
    "BIT2"         : 0x0031,
    "BIT3"         : 0x0032,
    "BIT4"         : 0x0033,
    "BIT5"         : 0x0034,
    "BIT6"         : 0x0035,
    "BIT7"         : 0x0036,
    "BIT8"         : 0x0037,
    "BITARR8"      : 0x002D,
    "BITARR16"     : 0x002E,
    "BITARR32"     : 0x002F,
    "INTEGER8"     : 0x0002,
    "SINT"         : 0x0002,
    "INTEGER16"    : 0x0003,
    "INT"          : 0x0003,
    "INTEGER24"    : 0x0010,
    "INT24"        : 0x0010,
    "INTEGER32"    : 0x0004,
    "DINT"         : 0x0004,
    "INTEGER40"    : 0x0012,
    "INT40"        : 0x0012,
    "INTEGER48"    : 0x0013,
    "INT48"        : 0x0013,
    "INTEGER56"    : 0x0014,
    "INT56"        : 0x0014,
    "INTEGER64"    : 0x0015,
    "LINT"         : 0x0015,
    "UNSIGNED8"    : 0x0005,
    "USINT"        : 0x0005,
    "UNSIGNED16"   : 0x0006,
    "UINT"         : 0x0006,
    "UNSIGNED24"   : 0x0016,
    "UINT24"       : 0x0016,
    "UNSIGNED32"   : 0x0007,
    "UDINT"        : 0x0007,
    "UNSIGNED40"   : 0x0018,
    "UINT40"       : 0x0018,
    "UNSIGNED48"   : 0x0019,
    "UINT48"       : 0x0019,
    "UNSIGNED56"   : 0x001A,
    "UINT56"       : 0x001A,
    "UNSIGNED64"   : 0x001B,
    "ULINT"        : 0x001B,
    "REAL32"       : 0x0008,
    "REAL"         : 0x0008,
    "REAL64"       : 0x0011,
    "LREAL"        : 0x0011,
    "GUID"         : 0x001D
  }

  # initialize with the root etree element
  def __init__(self, root):
    self._root = root
    self._strd = OrderedDict()

  @property
  def strDict(self):
    return self._strd

  # find an optional element or attribute substituting
  # a 'default' if it cannot be found
  # The search key is split at '@' to separate tags
  # from attributes.
  # Search may start at a specific element or the
  # document root if no element is specified.
  def findOpt(self, key, dflt, el=None):
    if el is None:
      el = self._root
    l   = key.split("@")
    tag = l[0]
    txt = None
    rv  = el.find(tag)
    if not rv is None:
      if ( len(l) > 1 ):
        txt = rv.get( l[1] )
      else:
        txt = rv.text
    return dflt if txt is None else txt

  # find a mandatory element
  def mustFind(self, key, el=None):
    if el is None:
      el = self._root
    rv = el.find( key )
    if rv is None:
      raise KeyError("Element '{}' not found".format( key ) )
    return rv

  @staticmethod
  def addOrReplace(nod, sub):
    found = nod.find(sub.tag)
    if found is None:
      nod.append(sub)
    else:
      nod.replace(found, sub)
    return sub

  @staticmethod
  def findOrAdd(nod, tag):
    hier = tag.split('/')
    for t in hier:
      found = nod.find( t )
      if found is None:
        found = ET.SubElement(nod, t)
      nod = found
    return found

  # find a mandatory text or attribute
  def mustGet(self, key, el=None):
    txt = self.findOpt( key, None, el )
    if (txt is None):
      raise KeyError("value for '{}' not found!".format(key))
    return txt

  # Find an element and look up its value in the string
  # dictionary; append the index of the value in the
  # string table to the prom
  def appendStrIdx(self, prom, key, el=None):
    idx = 0
    txt = self.findOpt( key, None, el )
    if ( ( not txt is None ) and ( len(txt) > 0 ) ):
      idx = self.findAddStr( txt )
      if ( idx < 1 or idx > 255 ):
        raise ValueError("String index out of range")
    prom.append( ( idx & 0xff ) )

  # Convert HexDec to int
  @staticmethod
  def hd2int(x):
    try:
      if x[0:2] == "#x":
        return int(x[2:],16)
      else:
        return int(x, 10)
    except Exception as e:
      print("Trying to convert '{}'".format(x))
      raise(e)

  # look up an element, convert to a int of 'byteSz'
  # and append to the prom (as little-endian)
  def appendInt(self, prom, key, dflt=0, byteSz=4, el=None):
    val = dflt
    txt = self.findOpt(key, None, el)
    if txt is None:
      if val is None:
        raise KeyError("Element '{}' not found".format( key ) )
    else:
      val = self.hd2int( txt )
    for i in range(byteSz):
      prom.append( (val & 0xff) )
      val >>= 8

  # add padding of 'l' bytes; if 'l < 0' then pad
  # to the next word boundary
  def pad(self, prom, l):
    if ( l < 0 ):
      l = (len(prom) % 2)
    prom.extend( bytearray([0 for i in range(l)]) )

  # append mailbox information
  def appendMbx(self, prom, smNode):
    self.appendInt( prom, ".@StartAddress", dflt=None, byteSz=2, el=smNode )
    self.appendInt( prom, ".@DefaultSize",  dflt=None, byteSz=2, el=smNode )

  def getCat(self, prom, catId):
    pidx = 0
    val  = -1
    sz   = -2
    while val != catId:
      pidx += 2*sz + 4
      val   = (prom[pidx + 1] << 8) | prom[pidx + 0]
      if val == 0xffff:
        raise KeyError("Category not found")
      sz    = (prom[pidx + 3] << 8) | prom[pidx + 2]
    return pidx, 2*sz

  def getCatStrings(self, prom):
    cat      = Cat( prom, 10 )
    l        = []
    sz       = cat.getUInt8()
    for i in range(sz):
      sz    = cat.getUInt8()
      l.append( cat.getBytes( sz ).decode() )
    return l

  def getCatGeneral(self, devNod, prom, strs):
    cat      = Cat( prom, 30 )
    for nm in ["GroupType", None, "Type", "Name"]:
      sidx   = cat.getUInt8()
      if ( ( sidx != 0 ) and ( not nm is None ) ):
        self.findOrAdd(devNod, nm).text = strs[sidx - 1]
    cat.skip()

    mbxNod = self.mustFind("Mailbox", devNod)

    # these flags seem redundant to the mailbox services
    val = cat.getUInt8()
    msk = 0x02
    if ( val & 0x01 ):
      coeNod     = mbxNod.find("CoE")
      haveCoeNod = (not coeNod is None)
      if ( not haveCoeNod ):
        coeNod = ET.Element("CoE")
      for k in ["SDOInfo", "PdoAssign", "PdoConfig", "PdoUpload", "CompleteAccess" ]:
        if ( val & msk ) != 0:
          coeNod.set(k, "1")
        msk <<= 1
      if not haveCoeNod:
        mbxNod.append(coeNod)
    val = cat.getUInt8()
    if ( val & 0x01 ):
      self.findOrAdd( mbxNod, "FoE" )
    val = cat.getUInt8()
    if ( val & 0x01 ):
      self.findOrAdd( mbxNod, "EoE" )
    cat.skip(3)

    val   = cat.getUInt8()
    if ( val & 0x01 ):
      self.findOrAdd( devNod, "Info/StateMachineBehavior" ).set("StartToSaveopNoSync", "1")
    if ( val & 0x02 ):
      self.findOrAdd( devNod, "Type" ).set("UseLrdLwr", "1")
    if ( val & 0x04 ):
      mbxNod.set("DataLinkLayer", "1")
    if ( val & 0x08 ):
      self.findOrAdd( devNod, "Info/IdentificationReg134" )
    if ( val & 0x10 ):
      self.findOrAdd( devNod, "Info/IdentificationAdo"    )

    val = cat.getUInt16()

    self.findOrAdd( devNod, "Info/Electrical/EBusCurrent" ).text = str( val )

    cat.skip(2)

    val = cat.getUInt16()

    svl = ""
    while ( val != 0 ):
      if   ( ( val & 0xf ) == 0x1 ):
        svl += "Y"
      elif ( ( val & 0xf ) == 0x4 ):
        svl += "H"
      else:
        svl += " "
      val >>= 4
    devNod.set("Physics", svl)

    val = cat.getUInt16()
    if ( val != 0 ):
      self.findOrAdd( devNod, "Info/IdentificationAdo"    ).text = str( val )

  def getCatFmmu(self, devNod, prom):
    cat = Cat( prom, 40 )
    sz  = cat.size
    while sz > 0:
      val = cat.getUInt8()
      if   ( 0 == val ):
        svl = None
      elif ( 1 == val ):
        svl = "Outputs"
      elif ( 2 == val ):
        svl = "Inputs"
      elif ( 3 == val ):
        svl = "MBoxState"
      else:
        raise RuntimeError("getCatFmmu: unsupported FMMU type")
      if ( not svl is None ):
        ET.SubElement(devNod, "Fmmu" ).text = svl
      sz   -= 1
 
  def getCatSm(self, devNod, prom):
    cat      = Cat(prom, 41)
    sz       = cat.size
    while sz >= 8:
      sm        = ET.Element("Sm")
      startAddr = cat.getUInt16()
      defltSize = cat.getUInt16()
      cntrlByte = cat.getUInt8()
      cat.skip(1)
      enablByte = cat.getUInt8()
      typeByte  = cat.getUInt8()
      if (startAddr != 0 or dfltSize != 0 or cntrlByte != 0 or enablByte != 0) and (typeByte != 0):
        sm.set( "ControlByte",  "#x{:02x}".format( cntrlByte ) )
        sm.set( "StartAddress", "#x{:04x}".format( startAddr ) )
        sm.set( "DefaultSize",  "{:d}".format( defltSize ) )
        sm.set( "Enable",       "{:d}".format( enablByte ) )
        if   ( typeByte == 0x01 ):
          typ = "MBoxOut"
        elif ( typeByte == 0x02 ):
          typ = "MBoxIn"
        elif ( typeByte == 0x03 ):
          typ = "Outputs"
        elif ( typeByte == 0x04 ):
          typ = "Inputs"
        else:
          raise ValueError("getCatSm: unexpected SM type")
        sm.text = typ
      devNod.append( sm )
      sz -= 8

  def getCatPdo(self, devNod, prom, strs, isRxPdo):
    if ( isRxPdo ):
      catId  = 51
      pdoNodNm = "RxPdo"
    else:
      catId  = 50
      pdoNodNm = "TxPdo"
    cat   = Cat(prom, catId)
    sz    = cat.size
    while ( sz > 0 ):
      oldpos      = cat.pos
      pdoNod      = ET.SubElement(devNod, pdoNodNm)
      idxNod      = ET.SubElement(pdoNod, "Index")
      idxNod.text = "#x{:04x}".format( cat.getUInt16() )
      nents       = cat.getUInt8()
      smIdx       = cat.getUInt8()
      pdoNod.set("Sm", "{:d}".format( smIdx ))
      cat.skip() # DC Sync (?? - not explained)
      sidx        = cat.getUInt8()
      if ( sidx != 0 ):
        try:
          ET.SubElement( pdoNod, "Name" ).text = strs[sidx - 1]
        except Exception as e:
          print(e)
      flags       = cat.getUInt16()
      # WARNING -- not all flags are currently supported (module/slotgroup related stuff)
      # Note: Sm is already dealt with above
      for k in { "Mandatory": 0x0001, "Sm": 0x10002, "Fixed": 0x10, "Virtual": 0x20 }.items():
        if ( (flags & k[1]) & 0xffff ):
          if ( k[1] & 0x10000 ):
            if ( pdoNod.get( k[0] ) is None ):
              pdoNod.set( k[0], "" )
          else:
            pdoNod.set( k[0], "1" )
        flags &= ~ k[1]
      flags &= 0xffff
      if ( flags ):
        print("Unsupported flags (0x{:04x}) found in {}; ignored".format(flags, pdoNodNm), file=sys.stderr)
      for i in range(nents):
        entNod = ET.SubElement( pdoNod, "Entry" )
        ET.SubElement(entNod, "Index").text = "#x{:04x}".format( cat.getUInt16() )
        ET.SubElement(entNod, "SubIndex").text = "#x{:02x}".format( cat.getUInt8() )
        sidx = cat.getUInt8()
        val  = cat.getUInt8()
        typ  = None
        for k in self.BASE_TYPE_MAP.items():
          if k[1] == val:
            typ = k[0]
            break
        if typ is None:
          raise ValueError("DataType is not one of the recognized Base Data Types")
        ET.SubElement(entNod, "BitLen").text = str( cat.getUInt8() )
        cat.skip(2) # reserved flags; ignored
        if 0 != sidx:
          ET.SubElement(entNod, "Name").text = strs[sidx - 1]
        ET.SubElement(entNod, "DataType").text = typ
      sz -= (cat.pos - oldpos)
  
  # append a category to the prom. This is are recursive
  # procedure:
  #  - append the category ID (catId)
  #  - call 'process(prom, *args)' to append the contents
  #  - fix up the length of the category in the header
  def appendCat(self, prom, catId, process, *args):
    prom.append( (catId >> 0) & 0xff )
    prom.append( (catId >> 8) & 0xff )
    # record position
    pos = len(prom)
    # insert dummy length
    prom.append( 0x00 )
    prom.append( 0x00 )
    # append the contents
    process(prom, *args)
    # pad to word boundary
    self.pad( prom, -1 )
    newpos = len(prom)
    catLen = newpos - (pos + 2)
    catLen = int( catLen/2 )
    # fix-up the header with the length
    prom[pos+0] = (catLen >> 0) & 0xff
    prom[pos+1] = (catLen >> 8) & 0xff

  # append 'general' category contents
  def catGeneral(self, prom, devNod):
    # remember position of the group type; need a duplicate later
    grpIdxPos = len(prom)
    self.appendStrIdx( prom, "GroupType", el=devNod)
    # spec is unclear; it mentions ImageData16x14 but that would not be
    # a string and the prom entry is a 8-bit string index.
    # Skip for now as it is marked obsolete in the file specification...
    prom.append( 0x00 )
    self.appendStrIdx( prom, "Type", el=devNod)
    self.appendStrIdx( prom, "Name", el=devNod)
    # reserved
    prom.append( 0x00 )
    mbxNod = devNod.find( "Mailbox" )
    if ( not mbxNod is None ):
      coeNod = mbxNod.find("CoE")
      val    = 0
      if ( not coeNod is None ):
        val |= 0x01
        msk  = 0x02
        for k in [".@SDOInfo", ".@PdoAssign", ".@PdoConfig", ".@PdoUpload", ".@CompleteAccess" ]:
          if ( int( self.findOpt(k, "0", coeNod) != 0 ) ):
            val |= msk
          msk <<= 1
      prom.append( (val & 0xff) )
      prom.append( 0x00 if mbxNod.find( "FoE" ) is None else 0x01 )
      prom.append( 0x00 if mbxNod.find( "EoE" ) is None else 0x01 )
    else:
      self.pad(prom, 3)
    self.pad(prom, 3)
    flg  = 0x00
    flg |= 0x00 if int(self.findOpt(".//StateMachine/Behavior@StartToSaveopNoSync", "0", el=devNod)) == 0   else 0x01
    flg |= 0x00 if int(self.findOpt("Type@UseLrdLwr",                               "0", el=devNod)) == 0   else 0x02
    flg |= 0x00 if int(self.findOpt("Mailbox@DataLinkLayer",                        "0", el=devNod)) == 0   else 0x04
    flg |= 0x00 if int(self.findOpt("Info/IdentificationReg134",                    "0", el=devNod)) == 0   else 0x08
    flg |= 0x00 if self.findOpt("Info/IdentificationAdo",                          None, el=devNod) is None else 0x10
    prom.append( (flg & 0xff) )
    self.appendInt( prom, "Info/Electrical/EBusCurrent", dflt=0, byteSz=2, el=devNod )
    prom.append( prom[grpIdxPos] ) # duplicate
    prom.append( 0x00 )            # reserved
    port    = 0
    shft    = 0
    for c in self.mustGet(".@Physics", el=devNod):
      if ( shft > 3 ):
        break
      # the file spec says 'K': LVDS but there is no mention of lvds in the prom spec;
      # instead it mentions EBUS which cannot be found in the file spec :-(
      port |= ( {"Y": 0x01, "H": 0x04, "K": 0x00}.get(c, 0x00) << (4*shft) )
      shft += 1
    prom.append( (port >> 0) & 0xff )
    prom.append( (port >> 8) & 0xff )
    
    self.appendInt( prom, "Info/IdentificationAdo", dflt=0, byteSz=2, el=devNod )
    self.pad( prom, 12 )

  # Sync-Manager Category contents
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

  def catPdo(self, prom, pdos):
    for pdo in pdos:
      self.appendInt( prom, "Index", dflt=None, byteSz=2, el=pdo )
      ents = pdo.findall("Entry")
      if ( len(ents) > 255 ):
        raise ValueError("Too many PDO Entries in '{}'".format(pdo.tag))
      prom.append( len(ents) & 0xff )
      self.appendInt( prom, ".@Sm", dflt = (2 if pdo.tag == "RxPdo" else 3), byteSz=1, el=pdo )
      # DC Sync (?? - not explained)
      prom.append( 0x00 )
      self.appendStrIdx( prom, "Name", el=pdo ) 
      flags = 0
      # WARNING -- not all flags are currently supported (module/slotgroup related stuff)
      for k in { ".@Mandatory": 0x0001, ".@Sm": 0x10002, ".@Fixed": 0x10, ".@Virtual": 0x20 }.items():
        txt = self.findOpt( k[0], dflt=None, el=pdo )
        if not txt is None:
          # for some (marked with 0x10000) presence is all
          if ( k[1] & 0x10000 ):
            flags |= (k[1] & 0xffff)
          elif int(txt) != 0:
            flags |= (k[1] & 0xffff)
      prom.append( (flags >> 0) & 0xff )
      prom.append( (flags >> 8) & 0xff )
      for ent in ents:
        self.appendInt( prom, "Index", dflt=None, byteSz=2, el=ent )
        if prom[-1] == 0 and prom[-2] == 0:
          dfltSubIdx = 1
        else:
          # if index is nonzero SubIndex is mandatory!
          dfltSubIdx = None
        self.appendInt( prom, "SubIndex", dflt=dfltSubIdx, byteSz=1, el=ent )
        self.appendStrIdx( prom, "Name", el=ent )
        idx = self.BASE_TYPE_MAP.get( self.mustGet("DataType", el=ent) )
        if ( idx is None ):
          raise ValueError("DataType is not one of the recognized Base Data Types")
        prom.append( (idx & 0xff) )
        self.appendInt( prom, "BitLen", dflt=None, byteSz=1, el=ent )
        # reserved
        self.pad( prom, 2 )

  def catFmmu(self, prom, fmmus):
    num = 0
    for fmmu in fmmus:
      if num > 3:
        break
      t = fmmu.text
      if   t == "Inputs":
        v = 0x02
      elif t == "Outputs":
        v = 0x01
      elif t == "MBoxState":
        v = 0x03
      else:
        v = 0x00
      prom.append( (v & 0xff) )
      num += 1
    self.pad(prom, -1)

  def findAddStr(self, txt):
    # only do work if the string is not already in the dict/table
    if txt is None or len(txt) == 0:
      return 0

    idx = self.strDict.get( txt )
    if idx is None:
      idx = len( self.strDict )
      if ( idx > 255 ):
        raise ValueError("Category Strings: too many strings")
      self.strDict[ txt ] = idx
    return idx + 1

  # Build the string dictionary (mapping strings to their
  # index in the string category/table
  def catStrings(self, prom, devNod):
    # remember the index where number of strings is stored
    nStrPos = len(prom)
    if (len(self.strDict) > 255 ):
      raise ValueError("Category Strings: too many strings")
    # number of strings; we use this directly as a counter
    prom.append( len(self.strDict) )

    for k in self.strDict.keys():
      if len(k) > 255:
        raise ValueError("Category Strings: string loo long")
      prom.append( len(k) )
      prom.extend( bytearray( k.encode('ascii') ) )
    self.pad(prom, -1)

  def catOther(self, prom, nod):
    # Only 'Data' is supported ATM; should add support for other types as well...
    fr = len(prom)
    prom.extend( bytearray.fromhex( self.mustGet( "Data", nod ) ) )
    to = len(prom)

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

  def parseProm(self, prom):
    devNod = self.mustFind("Descriptions/Devices/Device")
    rdr    = PromRd( prom )

    eep = ET.Element("Eeprom")
    eep.set("AssignToPdi","1")
    ET.SubElement(eep, "ByteSize").text   = str(len(prom))
    ET.SubElement(eep, "ConfigData").text = rdr.getBytes(16).hex()

    self.findOrAdd( self._root.find("Vendor"), "Id" ).text = "#x{:x}".format( rdr.getUInt32() )

    nod = self.findOrAdd( devNod, "Type" )
    nod.set("ProductCode", "{:04d}".format( rdr.getUInt32() ))
    nod.set("RevisionNo",  "{:04d}".format( rdr.getUInt32() ))
    nod.set("SerialNo"  ,  "{:04d}".format( rdr.getUInt32() ))

    rdr.skip(8)

    allZero = True
    dat     = rdr.getBytes(8)
    for i in dat:
      if ( i != 0 ):
        allZero = False
        break
    if not allZero:
      ET.SubElement(eep, "BootStrap").text = dat.hex()

    # skip mailbox; get redundant info from SM category
    rdr.skip(8)

    #Mailbox Services
    mbx = ET.Element("Mailbox")
    val = rdr.getUInt16()

    for prot in {"AoE" : 0x01, "EoE" : 0x02, "CoE" : 0x04, "FoE" : 0x08,
                 "SoE" : 0x10, "VoE" : 0x20 }.items():
      if ( (val & prot[1]) != 0 ):
        el = ET.SubElement( mbx, prot[0] )
        if ( prot[0] == "EoE" ):
          el.set("IP", "1")
          el.set("MAC", "1")

    rdr.skip(66)

    val = rdr.getUInt16()

    eep.find("ByteSize").text = str( int( (val + 1)*1024/8 ) )

    val = rdr.getUInt16()

    if( val != 1 ):
      raise RuntimeError("Unexpected SII version {:d}".format( val ))

    promUpper = prom[rdr.pos:]


    strs = self.getCatStrings( promUpper )

    self.getCatFmmu   ( devNod, promUpper         )
    self.getCatSm     ( devNod, promUpper         )
    # RxPDO
    self.getCatPdo    ( devNod, promUpper,   strs, True )
    # TxPDO
    self.getCatPdo    ( devNod, promUpper,   strs, False)
    self.addOrReplace ( devNod, mbx               )
    self.addOrReplace ( devNod, eep               )
    self.getCatGeneral( devNod, promUpper,   strs ) 

    typ = self.findOpt( "Type", dflt = None, el = devNod )
    if ( not typ is None ):
      typNod = self.mustFind("Descriptions/Groups/Group/Type")
      if ( typNod.text is None ):
        typNod.text = typ
      namNod = self.mustFind("Descriptions/Groups/Group/Name")
      if ( namNod.text is None ):
        namNod.text = typ

    # - Device- and Vendor-specific categories
    cat = Cat( promUpper )
    try:
      while ( True ):
        # vendor-specific categories are fixed-up by the EsiTool
        if (cat.id >= 1 and cat.id < 9) or (cat.id >= 0x0800 and cat.id <= 0xfffe):
          catNod = ET.SubElement( eep, "Category" )
          ET.SubElement( catNod, "CatNo" ).text = str( cat.id )
          ET.SubElement( catNod, "Data" ).text  = cat.getBytes( cat.size ).hex()
        cat.next()
    except KeyError:
      pass # end reached

    return self._root, strs

  def makeProm(self, devNod = None):
    prom    = bytearray()

    # Use first/default device node if none given
    if devNod is None:
      devNod = self.mustFind(".//Devices/Device")

    cfgData = bytearray.fromhex( self.mustGet(".//Eeprom/ConfigData", el=devNod) )
    # pad to 14 bytes if necessary
    cfgData.extend([0 for i in range(14 - len(cfgData))])

    crc = 0xff
    for b in cfgData[0:14]:
       crc = self.crc8byte(crc, b)

    prom.extend( cfgData[0:14] )
    prom.append( (crc & 0xff ) )
    prom.append( 0x00 )

    self.appendInt( prom, "Vendor/Id",        dflt=None         )
    self.appendInt( prom, "Type@ProductCode", dflt=0, el=devNod )
    self.appendInt( prom, "Type@RevisionNo",  dflt=0, el=devNod )
    self.appendInt( prom, "Type@SerialNo",    dflt=0, el=devNod )
    self.pad(       prom, 8 )

    #Bootstrap Mailbox
    nod = self.findOpt(".//Eeprom/BootStrap", dflt=None, el=devNod )
    if not nod is None:
      d = bytearray.fromhex( nod )
    else:
      d = bytearray(8)
    if ( len(d) != 8 ):
      raise ValueError("BootStrap data must be 8 octets long")
    prom.extend(d)

    #Standard Mailbox
    sms = devNod.findall("Sm")
    for wanted in [ "MBoxOut", "MBoxIn" ]:
      fnd = None
      for sm in sms:
        if ( sm.text == wanted ):
          fnd = sm
          break
      if fnd is None:
        self.pad(prom, 4)
      else:
        self.appendMbx(prom, fnd)

    #Mailbox Services
    val = 0
    nod = devNod.find("Mailbox")
    if ( not nod is None ):
      for prot in {"AoE" : 0x01, "EoE" : 0x02, "CoE" : 0x04, "FoE" : 0x08,
                   "SoE" : 0x10, "VoE" : 0x20 }.items():
        if not nod.find(prot[0]) is None:
          val |= prot[1]
    prom.append( (val >> 0) & 0xff )
    prom.append( (val >> 8) & 0xff )

    self.pad( prom, 66 )

    #Prom Size
    nod = self.mustFind(".//Eeprom/ByteSize", el=devNod)
    val = int( int(nod.text) * 8/1024 ) - 1
    if ( val < 0 or val > 65535 ):
      raise ValueError("Invalid EEPROM Size")
    prom.append( (val >> 0) & 0xff )
    prom.append( (val >> 8) & 0xff )

    #Version 1 as per spec
    val = 0x0001
    prom.append( (val >> 0) & 0xff )
    prom.append( (val >> 8) & 0xff )

    #Categories
    cats = bytearray()

    # - Device-specific categories
    for cat in devNod.findall(".//Eeprom/Category"):
      catNo = int( self.mustGet("CatNo", el=cat) )
      self.appendCat( cats, catNo, self.catOther, cat )

    # - General Category
    self.appendCat( cats, 30, self.catGeneral, devNod )
    
    fmmus = devNod.findall("Fmmu")
    if ( len(fmmus) > 0 ):
      self.appendCat( cats, 40, self.catFmmu, fmmus )

    sms   = devNod.findall("Sm")
    if ( len(sms) > 0 ):
      self.appendCat( cats, 41, self.catSm, sms )

    txpdos = devNod.findall("TxPdo")
    self.appendCat( cats, 50, self.catPdo, txpdos )

    rxpdos = devNod.findall("RxPdo")
    self.appendCat( cats, 51, self.catPdo, rxpdos )

    # Mop up strings; TwinCAT seems to need this first;
    # otherwise it does not recognize the categories
    self.appendCat( prom, 10, self.catStrings, devNod )

    prom.extend( cats )

    # End marker
    prom.append( 0xff )
    prom.append( 0xff )

    return prom
