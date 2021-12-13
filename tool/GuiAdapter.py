import sys
from   PyQt5        import QtCore,QtGui,QtWidgets
# GUI
from   PdoElement   import PdoElement, PdoListWidget, PdoSegment, FixedPdoSegment, createValidator
from   FixedPdoForm import FixedPdoForm, PdoElementGroup
# XML interface
from   tool         import VendorData, Pdo, NetConfig

class VendorDataAdapter(object):
  def __init__(self, vendorData):
    super().__init__()
    self._vendorData = vendorData
    self._gui        = None
    # we will be editing the netConfig; make a copy
    self._netConfig  = vendorData.netConfig.clone()

  @property
  def vendorData(self):
    return self._vendorData

  def getSegmentList(self):
    return vendorData.segments

  def makeNetCfgGui(self):
    def mkMacSet(c):
      def act(s):
        c.setMacAddr( s )
      return act
    def mkMacGet(c):
      def act():
        a   = c.macAddr
        return "{:02x}:{:02x}:{:02x}:{:02x}:{:02x}:{:02x}".format(a[0], a[1], a[2], a[3], a[4], a[5])
      return act
    def mkIp4Get(c):
      def g():
        a   = c.ip4Addr
        return "{:d}.{:d}.{:d}.{:d}".format(a[0], a[1], a[2], a[3])
      return g 
    def mkIp4Set(c):
      def act(s):
        c.setIp4Addr(s)
      return act

    vb  = QtWidgets.QVBoxLayout()
    self._netCfgGui = vb
    lbl = QtWidgets.QLabel("EoE Network Settings")
    lbl.setAlignment(QtCore.Qt.AlignCenter)
    vb.addWidget( lbl )
    frm = QtWidgets.QFormLayout()

    edt = QtWidgets.QLineEdit()
    edt.setMaxLength( 17 )
    # create restorer and setter
    g = mkMacGet( self._netConfig )
    s = mkMacSet( self._netConfig )
    twohex = "[0-9a-fA-F]{2,2}"
    pattrn = "({}[:]){{5,5}}{}".format( twohex, twohex )
    createValidator( edt, g, s, QtGui.QRegExpValidator, QtCore.QRegExp( pattrn ) )
    frm.addRow( QtWidgets.QLabel("Mac Address"), edt )
    self._netCfgEdtMac = edt

    edt = QtWidgets.QLineEdit()
    edt.setMaxLength( 17 )
    createValidator( edt, mkIp4Get( self._netConfig ), mkIp4Set( self._netConfig ), Ip4Validator )
    frm.addRow( QtWidgets.QLabel("IPv4 Address"), edt )
    self._netCfgEdtIp4 = edt

    vb.addLayout( frm )
    return self._netCfgGui

  def makeGui(self, pdoAdapt, parent = None):
    self._gui = FixedPdoForm( None, parent )
    nidx      = 0
    eidx      = 0
    msk       = VendorData.F_WITH_TSTAMP;
    pdo       = pdoAdapt.pdo
    flgs      = self._vendorData.flags
    checked   = bool( flgs & msk )
    if checked:
      idx0    = pdo[eidx + 0].index
      idx1    = pdo[eidx + 1].index
      eidx   += 2
      flgs   &= ~msk
    else:
      idx0    = 0 
      idx1    = 0 
    e         = list()
    e.append( PdoElement( self._vendorData.names[nidx + 0], idx0, 4 ) )
    e.append( PdoElement( self._vendorData.names[nidx + 1], idx1, 4 ) )
    self._gui.addGroup( PdoElementGroup( e, checked ) )
    nidx     += 2
    msk     <<= 1

    checked   = bool( flgs & msk )
    if checked:
      idx0    = pdo[eidx].index
      eidx   += 1
      flgs   &= ~msk
    else:
      idx0    = 0
    self._gui.addGroup( PdoElement( self._vendorData.names[nidx], idx0, 4, self._vendorData.eventDWords ), checked )
    nidx     += 1
    msk     <<= 1
    while ( nidx < len(self._vendorData.names) ):
      checked = bool( flgs & msk )
      if checked:
        idx   = pdo[eidx].index
        eidx += 1
        flgs &= ~msk
      else:
        idx   = 0
      self._gui.addGroup( PdoElement( self._vendorData.names[nidx], idx, 4 ), checked )
      nidx += 1
      msk <<= 1
    return self._gui.topLayout

class PdoAdapter(object):
  def __init__(self, pdo):
    super().__init__()
    self._gui = None
    self._pdo = pdo

  @property
  def pdo(self):
    return self._pdo

  def makeGui(self, vendorAdapt, parent = None):
    vendor    = vendorAdapt.vendorData
    self._gui = PdoListWidget( vendor.maxNumSegments, parent )
    for s in vendor.segments[1:]:
      self._gui.addSegment( s )
    try:
      for e in self._pdo[vendor.numEntries:]:
        print("Adding: byteSz", e.name, e.byteSz, e.isSigned)
        self._gui.add( PdoElement( e.name, e.index, e.byteSz, e.nelms, e.isSigned, e.typeName, e.indexedName ) )
    except Exception as e:
      print("WARNING -- unable to add all entries found in XML:")
      print( e.args[0] )
    self._gui.render()
    return self._gui

class Ip4Validator(QtGui.QRegExpValidator):
  def __init__(self):
    decnum  = "([1-9]([0-9]){0,2})"
    ip4patt = "({}[.]){{3,3}}{}".format( decnum, decnum )
    ip4rex  =  QtCore.QRegExp( ip4patt )
    super().__init__( ip4rex )

  def validate(self, s, p):
    st = super().validate(s, p)
    if ( QtGui.QValidator.Acceptable == st ):
      for x in st.split("."):
        if int(x) > 255:
          return QtGui.QValidator.Invalid
    return st

if __name__ == "__main__":

  from   PyQt5 import QtCore,QtGui,QtWidgets
  import sys
  from   lxml  import etree as ET

  app = QtWidgets.QApplication(sys.argv)
  window = QtWidgets.QWidget()
  #window.setMinimumSize(1400,1400)
  layout = QtWidgets.QVBoxLayout()

  et = ET.parse('feil.xml')

  vendorData        = VendorData.fromElement( et.find(".//Eeprom") )
  vendorDataAdapter = VendorDataAdapter( vendorData )
  pdo               = Pdo.fromElement( et.find(".//TxPdo"), vendorData.segments ) 
  pdoAdapter        = PdoAdapter( pdo )
  vendorGui         = vendorDataAdapter.makeGui( pdoAdapter )
  netCfgGui         = vendorDataAdapter.makeNetCfgGui()
  pdoGui            = pdoAdapter.makeGui( vendorDataAdapter )
  layout.addLayout( netCfgGui )
  layout.addLayout( vendorGui )
  layout.addWidget( pdoGui    )
  
  window.setLayout( layout )
  window.show()
  app.exec()
