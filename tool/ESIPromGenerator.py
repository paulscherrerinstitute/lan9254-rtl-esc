

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

  # find a mandatory text or attribute
  def mustGet(self, key, el=None):
    txt = self.findOpt( key, None, el )
    if (txt is None):
      raise KeyError("value for '{}' not found!".format(key))
    return txt

  # Find an element and look up its value in the string
  # dictionary; append the index of the value in the
  # string table to the prom
  def appendStrIdx(self, prom, strDict, key, el=None):
    idx = 0
    txt = self.findOpt( key, None, el )
    if ( ( not txt is None ) and ( len(txt) > 0 ) ):
      s = strDict.get( txt )
      if ( not s is None ):
        idx = int(s)
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
  def catGeneral(self, prom, strDict, devNod):
    # remember position of the group type; need a duplicate later
    grpIdxPos = len(prom)
    self.appendStrIdx( prom, strDict, "GroupType", el=devNod)
    # spec is unclear; it mentions ImageData16x14 but that would not be
    # a string and the prom entry is a 8-bit string index.
    # Skip for now as it is marked obsolete in the file specification...
    prom.append( 0x00 )
    self.appendStrIdx( prom, strDict, "Type", el=devNod)
    self.appendStrIdx( prom, strDict, "Name", el=devNod)
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

  def catPdo(self, prom, pdos, strDict):
    for pdo in pdos:
      self.appendInt( prom, "Index", dflt=None, byteSz=2, el=pdo )
      ents = pdo.findall("Entry")
      if ( len(ents) > 255 ):
        raise ValueError("Too many PDO Entries in '{}'".format(pdo.tag))
      prom.append( len(ents) & 0xff )
      self.appendInt( prom, ".@Sm", dflt = (2 if pdo.tag == "RxPdo" else 3), byteSz=1, el=pdo )
      # DC Sync (?? - not explained)
      prom.append( 0x00 )
      self.appendStrIdx( prom, strDict, "Name", el=pdo ) 
      flags = 0
      # WARNING -- not all flags are currently supported (module/slotgroup related stuff0
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
        self.appendStrIdx( prom, strDict, "Name", el=ent )
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

  # Build the string dictionary (mapping strings to their
  # index in the string category/table
  def catStrings(self, prom, strDict, devNod):
    # remember the index where number of strings is stored
    nStrPos = len(prom)
    # number of strings; we use this directly as a counter
    prom.append(0x00)

    # local helper to add a string to the prom and at the
    # same time add it to the dict. Duplicates are avoided.
    def addStr(s):
      # nothing to do if there is no string or an empty string
      if s is None or len(s) == 0:
        return
      # only do work if the string is not already in the dict/table
      if ( strDict.get( s ) is None ):
        if len(s) > 255:
          raise ValueError("Category Strings: string loo long")
        if ( prom[nStrPos] == 255 ):
          raise ValueError("Category Strings: too many strings")
        # one more string
        prom[nStrPos] += 1
        # add to dictionary: string => current number of strings (= index)
        strDict[s]     = prom[nStrPos]
        # add to prom
        prom.append( len(s) )
        prom.extend( bytearray( s.encode('ascii') ) )
    # helper to find a number of keys and add their values
    # to the string table/category
    def findAddStr(pat):
      for e in devNod.findall(pat):
        addStr(e.text)
    findAddStr("GroupType")
    findAddStr("Type")
    findAddStr("Name")
    findAddStr(".//RxPdo/Name")
    findAddStr(".//RxPdo/Entry/Name")
    findAddStr(".//TxPdo/Name")
    findAddStr(".//TxPdo/Entry/Name")
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
    nod = self.findOpt(".//Eeprom/BootStrap/Data", dflt=None, el=devNod )
    if not nod is None:
      d = bytearray.fromhex( nod.text )
    else:
      d = bytearray()
    d.extend([0 for i in range(8 - len(d))])
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

    strDict = dict()

    # - Device-specific categories
    for cat in devNod.findall(".//Eeprom/Category"):
      catNo = int( self.mustGet("CatNo", el=cat) )
      self.appendCat( prom, catNo, self.catOther, cat )

    # - Gather strings
    self.appendCat( prom, 10, self.catStrings, strDict, devNod )

    # - General Category
    self.appendCat( prom, 30, self.catGeneral, strDict, devNod )
    
    fmmus = devNod.findall("Fmmu")
    if ( len(fmmus) > 0 ):
      self.appendCat( prom, 40, self.catFmmu, fmmus )

    sms   = devNod.findall("Sm")
    if ( len(sms) > 0 ):
      self.appendCat( prom, 41, self.catSm, sms )

    txpdos = devNod.findall("TxPdo")
    self.appendCat( prom, 50, self.catPdo, txpdos, strDict )

    rxpdos = devNod.findall("RxPdo")
    self.appendCat( prom, 51, self.catPdo, rxpdos, strDict )

    # End marker
    prom.append( 0xff )
    prom.append( 0xff )

    return prom
