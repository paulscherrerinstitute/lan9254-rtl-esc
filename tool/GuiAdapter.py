import sys
from   PyQt5              import QtCore,QtGui,QtWidgets
# GUI
from   PdoElement         import PdoElement, PdoListWidget, PdoSegment, FixedPdoSegment, createValidator, DialogBase
from   FixedPdoForm       import FixedPdoForm, PdoElementGroup
# XML interface
from   lxml               import etree as ET
from   ToolCore           import VendorData, Pdo, NetConfig, ESI

class VendorDataAdapter(object):
  def __init__(self, vendorData):
    self._vendorData = vendorData
    self.__gui       = None
    # we will be editing the netConfig in place; don't copy
    self._netConfig  = vendorData.netConfig
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

  def makeFixedPdoEl(self, which, idx):
    p = self._vendorData.fixedProperties[which]
    return PdoElement( p["name"], idx, int( ( p["size"] + 7 ) / 8 ), p["nelms"] )

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
    e.append( self.makeFixedPdoEl(nidx + 0, idx0) )
    e.append( self.makeFixedPdoEl(nidx + 1, idx1) )
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
    self.__gui.addGroup( self.makeFixedPdoEl( nidx, idx0 ), checked )
    nidx      += 1
    msk      <<= 1
    while ( nidx < len(self._vendorData.fixedProperties) ):
      checked = bool( flgs & msk )
      if checked:
        idx    = pdo[eidx].index
        eidx  += 1
        flgs  &= ~msk
      else:
        idx    = 0
      self.__gui.addGroup( self.makeFixedPdoEl( nidx, idx ), checked )
      nidx    += 1
      msk    <<= 1
    return self.__gui.topLayout

  def getGuiVals(self):
    return self.__gui.getGuiVals()

  def modified(self):
    return self.vendorData.modified or self.__gui.modified

  def resetModified(self):
    self.vendorData.resetModified()
    self.__gui.resetModified()

  def makeEvrCfgGui(self):
    def mkCodGet(vd, ev):
      # ensure that the event is actually enabled
      if ( ev < 10 ):
        vd.getEvrParam(ev).pulseEnabled = True
      def g():
        if ( ev >= 10 ):
          cod = vd.getExtraEvent( ev - 10 )
        else:
          cod = vd.getEvrParam(ev).pulseEvent
        return str(cod)
      return g
    def mkCodSet(vd, ev):
      # ensure that the event is actually enabled
      if ( ev < 10 ):
        vd.getEvrParam(ev).pulseEnabled = True
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
        self._pdoGui.add( PdoElement( e.name, e.index, e.byteSz, e.nelms, e.isSigned, e.typeName, e.indexedName ) )
    except Exception as e:
      print("WARNING -- unable to add all entries found in XML:")
      print( str(e) )
    self._pdoGui.render()
    return self.__gui

  def getGuiVals(self):
    return self._pdoGui.getGuiVals()

  def modified(self):
    return self._pdoGui.modified

  def resetModified(self):
    self._pdoGui.resetModified()

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

class QuitDialog(DialogBase):
  def __init__(self, *args, **kwargs):
    super().__init__(*args, hasDelete = False, **kwargs)
    self.setMsg("There are unmodified changes - really Quit?")

  def dialogDoneCheck(self, result):
    if ( 1 == result ):
      sys.exit(0)

class MyMainWindow(QtWidgets.QMainWindow):
  def __init__(self, gui, *args, **kwargs):
    super().__init__(*args, **kwargs)
    self._gui = gui

  def closeEvent(self, event):
    self._gui.mkQuit( event.accept, event.ignore )()

class ESIAdapter(VendorDataAdapter, PdoAdapter):
  def __init__(self, esi, fnam = None):
    VendorDataAdapter.__init__(self, esi.vendorData)
    PdoAdapter.__init__(self, esi.txPdo)
    self._esi  = esi
    self._main = None
    self._fnam = fnam

  def makeGui(self, parent=None):
    window = QtWidgets.QWidget()
    title  = "EtherCAT EVR ESI-File and EEPROM Utility"
    window.setWindowTitle( title )
    layout = QtWidgets.QVBoxLayout()
    lbl    = QtWidgets.QLabel( title )
    lbl.setObjectName("H1")
    layout.addWidget( lbl )
    hlay   = QtWidgets.QHBoxLayout()
    vlay   = QtWidgets.QVBoxLayout()
    layout.addLayout( hlay )
    hlay  .addLayout( vlay )
    vlay.addLayout( VendorDataAdapter.makeNetCfgGui( self ) )
    vlay.addLayout( VendorDataAdapter.makeEvrCfgGui( self ) )
    vlay.addLayout( VendorDataAdapter.makeGui( self, self ) )
    hlay.addLayout( PdoAdapter.makeGui( self, self )        )
    window.setLayout( layout )
    main       = MyMainWindow( self )
    self._main = main
    main.setCentralWidget(window)
    menuBar    = QtWidgets.QMenuBar()
    fileMenu   = menuBar.addMenu( "File" )
    self.resetModified()

    def fileSaveDialog(slf, typ):
      op  = QtWidgets.QFileDialog.Options()
      op |= QtWidgets.QFileDialog.DontUseNativeDialog;
      parent = slf._main
      return QtWidgets.QFileDialog.getSaveFileName(parent, "File Name", "", typ, options=op)

    def mkSave(slf):
      def save():
        try:
          self.update()
          self.saveTo( self._fnam )
          self.resetModified()
        except Exception as e:
          DialogBase( hasDelete = False, parent = self._main, hasCancel = False ).setMsg( "Error: " + str(e) ).show()
      return save

    def mkSaveAs(slf):
      def saveAs():
        fn = fileSaveDialog(self, "XML Files (*.xml);;All Files (*)")
        if ( 0 == len( fn[0] ) ):
          # cancel
          return
        try:
          self.update()
          self.saveTo( fn[0] )
          self.resetModified()
        except Exception as e:
          DialogBase( hasDelete = False, parent = self._main, hasCancel = False ).setMsg( "Error: " + str(e) ).show()
      return saveAs

    def mkWriteSii(slf):
      def writeSii():
        fn = fileSaveDialog(self, "SII Files (*.sii);;All Files (*)")
        if ( 0 == len( fn[0] ) ):
          # cancel
          return
        try:
          self.update()
          self._esi.writeProm( fn[0], overwrite=True )
        except Exception as e:
          DialogBase( hasDelete = False, parent = self._main, hasCancel = False ).setMsg( "Error: " + str(e) ).show()
      return writeSii

    if ( not self._fnam is None ):
      fileMenu.addAction( "Save" ).triggered.connect( mkSave( self ) )
    fileMenu.addAction( "Save As" ).triggered.connect( mkSaveAs( self ) )
    fileMenu.addAction( "Write SII (EEPROM) File" ).triggered.connect( mkWriteSii( self ) )
    fileMenu.addAction( "Quit" ).triggered.connect( self.mkQuit() )
    main.setMenuBar( menuBar )
    return main

  def mkQuit( self, accept = lambda : sys.exit(0), ignore = lambda : None ):
    def quit():
      if ( self.modified() ):
        QuitDialog( parent = self._main ).show()
        ignore()
      else:
        accept()
    return quit

  def saveTo(self, fnam):
    ET.ElementTree(self._esi.element).write( fnam, xml_declaration = True, method = "xml", pretty_print=True )

  def update(self):
    segments, elements   = PdoAdapter.getGuiVals(self)
    flags, fixedElements = VendorDataAdapter.getGuiVals(self)
    self._vendorData.update( flags, segments )
    self._pdo.update( segments, fixedElements, elements )
    self._esi.update()

  def modified(self):
    return PdoAdapter.modified(self) or VendorDataAdapter.modified(self)

  def resetModified(self):
    PdoAdapter.resetModified(self)
    VendorDataAdapter.resetModified(self)
