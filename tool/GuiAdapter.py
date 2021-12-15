import sys
from   PyQt5        import QtCore,QtGui,QtWidgets
# GUI
from   PdoElement   import PdoElement, PdoListWidget, PdoSegment, FixedPdoSegment, createValidator
from   FixedPdoForm import FixedPdoForm, PdoElementGroup
# XML interface
from   tool         import VendorData, Pdo, NetConfig, ESI

class VendorDataAdapter(object):
  def __init__(self, vendorData):
    self._vendorData = vendorData
    self.__gui       = None
    # we will be editing the netConfig; make a copy
    self._netConfig  = vendorData.netConfig.clone()
    self._evrCfgGui  = None
    self._netCfgGui  = None

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
    lbl.setObjectName("H2")
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
    edt.setToolTip("By default (all-ones) the firmware uses a random MAC-address\nbased on the device DNA")

    edt = QtWidgets.QLineEdit()
    edt.setMaxLength( 17 )
    createValidator( edt, mkIp4Get( self._netConfig ), mkIp4Set( self._netConfig ), Ip4Validator )
    frm.addRow( QtWidgets.QLabel("IPv4 Address"), edt )
    self._netCfgEdtIp4 = edt

    vb.addLayout( frm )
    return self._netCfgGui

  def makeGui(self, pdoAdapt, parent = None):
    self.__gui = FixedPdoForm( None, parent )
    nidx       = 0
    eidx       = 0
    msk        = VendorData.F_WITH_TSTAMP;
    pdo        = pdoAdapt.pdo
    flgs       = self._vendorData.flags
    checked    = bool( flgs & msk )
    if checked:
      idx0     = pdo[eidx + 0].index
      idx1     = pdo[eidx + 1].index
      eidx    += 2
      flgs    &= ~msk
    else:
      idx0     = 0 
      idx1     = 0 
    e          = list()
    e.append( PdoElement( self._vendorData.names[nidx + 0], idx0, 4 ) )
    e.append( PdoElement( self._vendorData.names[nidx + 1], idx1, 4 ) )
    self.__gui.addGroup( PdoElementGroup( e, checked ) )
    nidx      += 2
    msk      <<= 1

    checked    = bool( flgs & msk )
    if checked:
      idx0     = pdo[eidx].index
      eidx    += 1
      flgs    &= ~msk
    else:
      idx0     = 0
    self.__gui.addGroup( PdoElement( self._vendorData.names[nidx], idx0, 4, self._vendorData.eventDWords ), checked )
    nidx      += 1
    msk      <<= 1
    while ( nidx < len(self._vendorData.names) ):
      checked = bool( flgs & msk )
      if checked:
        idx    = pdo[eidx].index
        eidx  += 1
        flgs  &= ~msk
      else:
        idx    = 0
      self.__gui.addGroup( PdoElement( self._vendorData.names[nidx], idx, 4 ), checked )
      nidx    += 1
      msk    <<= 1
    return self.__gui.topLayout

  def getGuiVals(self):
    return self.__gui.getGuiVals()

  def makeEvrCfgGui(self):
    def mkCodGet(vd, ev):
      def g():
         if ( ev >= 10 ):
           cod = vd.getExtraEvent( ev - 10 )
         else:
           cod = vd.getEvrParam(ev).pulseEvent
         return str(cod)
      return g
    def mkCodSet(vd, ev):
      def s(v):
         if ( ev >= 10 ):
           vd.setExtraEvent( ev - 10, int(v) )
         else:
           vd.getEvrParam(ev).pulseEvent = int(v)
      return s
    def mkDlyGet(vd, ev):
      def g():
         return str(vd.getEvrParam(ev).pulseDelay)
      return g
    def mkDlySet(vd, ev):
      def s(v):
         vd.getEvrParam(ev).pulseDelay = int(v)
      return s
    vb  = QtWidgets.QVBoxLayout()
    self._evrCfgGui = vb
    lbl = QtWidgets.QLabel("EVR Default Settings")
    lbl.setObjectName("H2")
    vb.addWidget( lbl )
    frm = QtWidgets.QFormLayout()

    edt = QtWidgets.QLineEdit()
    edt.setMaxLength( 4 )
    g   = mkCodGet( self._vendorData, 0 )
    s   = mkCodSet( self._vendorData, 0 )
    createValidator( edt, g, s, QtGui.QIntValidator, 0, 255 )
    frm.addRow( QtWidgets.QLabel("TxPDO Trigger Event Code"), edt )

    edt = QtWidgets.QLineEdit()
    edt.setMaxLength( 12 )
    g   = mkDlyGet( self._vendorData, 0 )
    s   = mkDlySet( self._vendorData, 0 )
    createValidator( edt, g, s, QtGui.QIntValidator, 0, 10000000 )
    edt.setToolTip("Delay is in EVR clock cycles")
    frm.addRow( QtWidgets.QLabel("TxPDO Trigger Event Delay"), edt )

    edt = QtWidgets.QLineEdit()
    edt.setMaxLength( 4 )
    g   = mkCodGet( self._vendorData, 10 )
    s   = mkCodSet( self._vendorData, 10 )
    createValidator( edt, g, s, QtGui.QIntValidator, 0, 255 )
    edt.setToolTip("When this event is detected LATCH0 is asserted;\n" +
                   "you also need to define an event to deassert LATCH0!")
    frm.addRow( QtWidgets.QLabel("Event Code setting  LATCH0"), edt )

    edt = QtWidgets.QLineEdit()
    edt.setMaxLength( 4 )
    g   = mkCodGet( self._vendorData, 11 )
    s   = mkCodSet( self._vendorData, 11 )
    createValidator( edt, g, s, QtGui.QIntValidator, 0, 255 )
    edt.setToolTip("When this event is detected LATCH0 is deasserted;\n" +
                   "you also need to define an event to assert LATCH0!")
    frm.addRow( QtWidgets.QLabel("Event Code clearing LATCH0"), edt )


    vb.addLayout( frm )
    return self._evrCfgGui


class PdoAdapter(object):
  def __init__(self, pdo):
    self.__gui = None
    self._pdo  = pdo

  @property
  def pdo(self):
    return self._pdo

  def makeGui(self, vendorAdapt, parent = None):
    vendor       = vendorAdapt.vendorData
    vb           = QtWidgets.QVBoxLayout()
    lbl          = QtWidgets.QLabel("EVR Data-Buffer PDO Mappings")
    lbl.setObjectName("H2")
    vb.addWidget( lbl )

    self.__gui   = vb
    self._pdoGui = PdoListWidget( vendor.maxNumSegments, parent )
    vb.addWidget( self._pdoGui )
    for s in vendor.segments[1:]:
      # we don't want to hand over ownership so we make a copy
      self._pdoGui.addSegment( s.clone() )
    try:
      for e in self._pdo[vendor.numEntries:]:
        print("Adding: byteSz", e.name, e.byteSz, e.isSigned)
        self._pdoGui.add( PdoElement( e.name, e.index, e.byteSz, e.nelms, e.isSigned, e.typeName, e.indexedName ) )
    except Exception as e:
      print("WARNING -- unable to add all entries found in XML:")
      print( e.args[0] )
    self._pdoGui.render()
    return self.__gui

  def getGuiVals(self):
    return self._pdoGui.getGuiVals()

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

class ESIAdapter(VendorDataAdapter, PdoAdapter):
  def __init__(self, esi):
    VendorDataAdapter.__init__(self, esi.vendorData)
    PdoAdapter.__init__(self, esi.txPdo)
    self._esi = esi

  def makeGui(self, parent=None):
    window = QtWidgets.QWidget()
    title  = "EtherCAT EVR ESI-File and EEPROM Utility"
    window.setWindowTitle( title )
    layout = QtWidgets.QVBoxLayout()
    lbl    = QtWidgets.QLabel( title )
    lbl.setObjectName("H1")
    layout.addWidget( lbl )
    layout.addLayout( VendorDataAdapter.makeNetCfgGui( self ) )
    layout.addLayout( VendorDataAdapter.makeEvrCfgGui( self ) )
    layout.addLayout( VendorDataAdapter.makeGui( self, self ) )
    layout.addLayout( PdoAdapter.makeGui( self, self )        )
    btn = QtWidgets.QPushButton("test")
    def mkTest(s):
      def a():
        s.update()
      return a
    btn.clicked.connect( mkTest(self) )
    layout.addWidget( btn )
    window.setLayout( layout ) 
    return window

  def update(self):
    segments, elements   = PdoAdapter.getGuiVals(self)
    flags, fixedElements = VendorDataAdapter.getGuiVals(self)
    print("update: {} segments, {} elements, flags {:02x}, {} fixed elements".format(len(segments), len(elements), flags, len(fixedElements)))
    self._vendorData.update( flags, segments )
    allElements = list()
    allElements.extend( fixedElements )
    allElements.extend( elements )
    self._pdo.update( segments, allElements )
    self._esi.makeProm()
    ET.ElementTree(self._esi.element).write( '-', xml_declaration = True, method = "xml", pretty_print=True )

if __name__ == "__main__":

  from   PyQt5 import QtCore,QtGui,QtWidgets
  import sys
  from   lxml  import etree as ET

  style = (
           "QLabel#H2 { font: bold italic;"
         + "            qproperty-alignment: AlignHCenter;"
         + "            padding:   20;"
         + "          }"
         + "QLabel#H1 { font: bold italic huge;"
         + "            padding:   40;"
         + "          }"
          )

  app = QtWidgets.QApplication(sys.argv)
  app.setStyleSheet(style)

  parser = ET.XMLParser(remove_blank_text=True)

  op = QtWidgets.QFileDialog.Options()
  op |= QtWidgets.QFileDialog.DontUseNativeDialog;
  parent = None
#  fn = QtWidgets.QFileDialog.getSaveFileName(parent, "File Name", "", "XML Files (*.xml)", options=op)

  et =  None if True  else ET.parse('feil.xml', parser).getroot()
  esi = ESI( et )
  guiAdapter = ESIAdapter( esi )
  window     = guiAdapter.makeGui()
  window.show()
  app.exec()
