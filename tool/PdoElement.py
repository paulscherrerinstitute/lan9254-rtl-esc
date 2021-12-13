#from PyQt5.QtCore import Qt, QPoint, QItemSelection, QItemSelectionModel
#from PyQt5.QtGui import QDropEvent
#from PyQt5.QtWidgets import QTableWidget, QAbstractItemView, QTableWidgetItem, QTableWidgetSelectionRange
from PyQt5             import QtCore, QtGui, QtWidgets
from TableWidgetDnD    import TableWidgetDnD
from contextlib        import contextmanager
from tool              import PdoSegment
from FirmwareConstants import FirmwareConstants

class Sel(QtCore.QItemSelectionModel):
  def __init__(self, *args, **kwargs):
    super().__init__(*args, *kwargs)
    super().installEventFilter( self )
    print("Initializing Sel")
    
  def eventFilter(self, o, e):
    print(o, e)
    return super().eventFilter(o, e)

  def event(self, e):
    print(e)
    return super().event(e)

# Magic factory; creates a subclass of 'clazz'
# (which is expected to be a 'QValidator' subclass)
# and furnishes a 'fixup' and connects to signals
# so that 'setter' may update an associated object
# from the new QLineEdit text. 'getter' is used
# to restore the text from an associated object if
# editing fails or is abandoned.
def createValidator(lineEdit, getter, setter, clazz, *args, **kwargs):

  class TheValidator(clazz):
    def __init__(self, lineEdit, getter, setter, *args, **kwargs):
      super().__init__( *args, **kwargs )
      def mkRestoreVal(w, g):
        def act():
          w.setText( g() )
        return act
      def mkSetVal(w, g, s): 
        def act():
          try:
            s( w.text() )
          except Exception as e:
            w.setText( g() )
        return act
      self._edt = lineEdit
      self._get = getter
      self._set = setter
      if not lineEdit is None:
        self.connect( lineEdit )

    def connect(self, lineEdit):
      def mkRestoreVal(w, g):
        def act():
          w.setText( g() )
        return act
      def mkSetVal(w, g, s): 
        def act():
          try:
            s( w.text() )
          except Exception as e:
            w.setText( g() )
        return act
      self._edt = lineEdit
      self._edt.editingFinished.connect( mkRestoreVal( lineEdit, getter ) )
      self._edt.returnPressed.connect(   mkSetVal(     lineEdit, getter, setter ) )
      self._edt.setValidator( self )
      mkRestoreVal( lineEdit, getter ) ()

    def fixup(self, s):
      return self._get()

  return TheValidator( lineEdit, getter, setter, *args, **kwargs )

class PdoElement(object):

  def __init__(self, name, index, byteSize, nelms = 1, isSigned = False, typeName=None, indexedName=True):
    super().__init__()
    self.name        = name
    self.index       = index
    self.nelms       = nelms
    self.byteSz      = byteSize
    self.isSigned    = isSigned
    self.typeName    = typeName
    self.indexedName = indexedName

  @property
  def name(self):
    return self._name

  @name.setter
  def name(self, val):
    if not isinstance(val, str):
      raise ValueError("name must be a string")
    self._name = val

  @property
  def index(self):
    return self._index

  @index.setter
  def index(self, val):
    if not isinstance(val, int) or val < 0:
      raise ValueError("index must be a natural number")
    self._index = val

  @property
  def nelms(self):
    return self._nelms

  @nelms.setter
  def nelms(self, val):
    if not isinstance(val, int) or val < 0:
      raise ValueError("nelms must be a natural number")
    self._nelms = val

  @property
  def byteSz(self):
    return self._byteSz

  @byteSz.setter
  def byteSz(self, val):
    if not isinstance(val, int) or (not val in [1,2,4,8]):
      raise ValueError("byteSz must 1,2,4 or 8")
    self._byteSz = val

  @staticmethod
  def bs2str(isSigned, byteSz):
    if isSigned:
      pre = "S"
    else:
      pre = "U"
    return "{}{:d}".format(pre,8*byteSz) 

  @staticmethod
  def str2bs(s):
    isSigned = { 'S': True, 'U': False }.get( s[0].upper() )
    byteSz   = int(s[1:],0)
    if not byteSz in [8, 16, 32, 64]:
      byteSz = None
    else:
      byteSz = int(byteSz / 8)
    return byteSz, isSigned

  @property
  def isSigned(self):
    return self._isSigned

  @isSigned.setter
  def isSigned(self, val):
    if not isinstance(val, bool):
      raise ValueError("isSigned must be boolean")
    self._isSigned = val

  @property
  def indexedName(self):
    return self._indexedName

  @indexedName.setter
  def indexedName(self, val):
    if not isinstance(val, bool):
      raise ValueError("indexedName must be boolean")
    self._indexedName = val

  @property
  def typeName(self):
    return self._typeName

  @typeName.setter
  def typeName(self, val):
    if val is None:
      val = ""
    if not isinstance(val, str):
      raise ValueError("typeName must be a string")
    self._typeName = val

# Action which emits itself
class ActAction(QtWidgets.QAction):

  _signal = QtCore.pyqtSignal(QtWidgets.QAction)

  def __init__(self, name, parent=None):
    QtWidgets.QAction.__init__(self, name, parent)
    self.triggered.connect( self )

  def __call__(self):
    self._signal.emit(self)

  def connect(self, slot):
    self._signal.connect( slot )

class MenuButton(QtWidgets.QPushButton):

  def __init__(self, lbls, parent = None):
    super().__init__(parent)
    menu = QtWidgets.QMenu()
    self.setText( lbls[0] )
    # if the first label is also among the
    # following elements then it is the default/initial
    # value
    if lbls[0] in lbls[1:]:
      lbls = lbls[1:]
    for i in lbls:
      a = ActAction(i, self)
      a.connect( self.activated )
      menu.addAction( a )
    self.setMenu( menu )

  def activated(self, act):
    self.setText(act.text())


class DialogBase(QtWidgets.QDialog):

  HEX_VALIDATOR = QtGui.QRegExpValidator(QtCore.QRegExp("[0-9a-fA-F]+"))

  def __init__(self, hasDelete = False, parent = None):
    super().__init__( parent )
    self.buttonBox = QtWidgets.QDialogButtonBox( QtWidgets.QDialogButtonBox.Ok | QtWidgets.QDialogButtonBox.Cancel )
    if hasDelete:
      self.deleteButton = QtWidgets.QPushButton( "Delete" )
      self.deleteButton.clicked.connect( self.delete )
      # use 'reject' role to close the dialog without any further action in 
      # dialogDoneCheck
      self.buttonBox.addButton( self.deleteButton, QtWidgets.QDialogButtonBox.ActionRole )
    self.buttonBox.accepted.connect( self.accept )
    self.buttonBox.rejected.connect( self.reject )
    self.layout    = QtWidgets.QGridLayout()
    self.lstRow    = 0
    self.msgLbl    = QtWidgets.QLabel("")
    self.setLayout( self.layout    )
    self.finished.connect( self.dialogDoneCheck )

  def addRow(self, lbl, ini, val = None):
    self.layout.addWidget( QtWidgets.QLabel(lbl), self.lstRow, 0 )
    if ( isinstance(ini, list) ):
       wdgt = MenuButton( ini )
    else:
      wdgt = QtWidgets.QLineEdit()
      wdgt.setMaxLength( 40 )
      wdgt.setText( ini )
      wdgt.setValidator( val )
    self.layout.addWidget( wdgt, self.lstRow, 1 )
    self.lstRow += 1
    return wdgt

  def show(self):
    self.layout.addWidget( self.msgLbl,    self.layout.rowCount(), 0, 1, self.layout.columnCount() )
    self.layout.addWidget( self.buttonBox, self.layout.rowCount(), 0, 1, self.layout.columnCount() )
    self.open()

  def dialogDoneCheck(self, result):
    if 1 == result:
      msg = self.validInput()
      self.dialogError(msg)

  def dialogError(self, msg):
    if not msg is None:
      self.msgLbl.setText( msg )
      self.open()
    else:
      self.done(0)

  def validInput(self):
    return None

  def delete(self):
    return None

class SegmentEditor(DialogBase):

  def __init__(self, parent, tbl, seg = None):
    hasDelete = not seg is None
    super().__init__( hasDelete, parent )
    self.tbl = tbl
    self.seg = seg
    if ( seg is None ):
      tit      = "Create New DBUF Mapping Segment"
      tmplName = "<new>"
      tmplOffs = 0x0000
      tmplNelm = 2
      tmplSwap = 1
      tmplPos  = len(tbl._segs)
    else:
      tit = "Editing DBUF Mapping Segment'" + seg.name + "'"
      tmplName = seg.name
      tmplOffs = seg.byteOffset
      tmplNelm = seg.nDWords
      tmplSwap = seg.swap
      tmplPos  = tbl._segs.index(seg)
    self.setWindowTitle( tit )
      
    self.nameEdt   = self.addRow( "Name",          tmplName )
    self.posEdt    = self.addRow( "Position in table",  "{:d}".format( tmplPos )    )
    v              = self.HEX_VALIDATOR
    self.offstEdt  = self.addRow( "Byte-Offset (hex)",  "{:04x}".format(tmplOffs), v)
    v              = QtGui.QIntValidator(0, 32)
    self.nelmsEdt  = self.addRow( "# Elements (words)",   "{:d}".format(tmplNelm), v)

    swpChoice      = [ PdoSegment.swp2str(tmplSwap) ]
    for bs in [1, 2, 4, 8]:
        swpChoice.append( PdoSegment.swp2str( bs ) )

    self.swapEdt   = self.addRow( "Byte-swap", swpChoice )
    self.show()

  def delete(self):
    return self.dialogError( self.tbl.deleteSegment( self.seg ) )

  def validInput(self):
    if ( len(self.nelmsEdt.text()) == 0 ):
      return "ERROR -- empty input: '# Elements'"
    if ( len(self.nameEdt.text()) == 0 ):
      return "ERROR -- empty input: 'Name'"
    if ( len(self.offstEdt.text()) == 0 ):
      return "ERROR -- empty input: 'Offset'"
    if ( len(self.posEdt.text()) == 0 ):
      return "ERROR -- empty input: 'Position'"
    name     = self.nameEdt.text()
    offset   = int( self.offstEdt.text(), 16 )
    nelms    = int( self.nelmsEdt.text(),  0 )
    pos      = int( self.posEdt.text(),    0 )
    print(nelms, self.nelmsEdt.text())
    swap     = PdoSegment.str2swp( self.swapEdt.text() )
    if ( swap is None ):
      raise RuntimeError("Internal error: -- unable to convert swap from string")

    msg      = self.tbl.modifySegment(self.seg, name, pos, offset, nelms, swap)
    if not msg is None and len(msg) != 0:
      return msg
  
class ItemEditor(DialogBase):

  def __init__(self, parent, tbl, itm = None):
    hasDelete = not itm is None
    super().__init__( hasDelete, parent )
    self.tbl = tbl
    self.itm = itm
    if ( itm is None ):
      tit      = "Create New PDO Item"
      tmplName = "<new>"
      tmplIndx = 0x5000
      tmplNelm = 1
      tmplBySz = 4
      tmplSgnd = False
    else:
      tit = "Editing PDO Item '" + itm.name + "'"
      tmplName = itm.name
      tmplIndx = itm.index
      tmplNelm = itm.nelms
      tmplBySz = itm.byteSz
      tmplSgnd = itm.isSigned
    self.setWindowTitle( tit )
      
    self.nameEdt   = self.addRow( "Name",          tmplName )
    v              = self.HEX_VALIDATOR
    self.indexEdt  = self.addRow( "Index (hex)",  "{:04x}".format(tmplIndx), v)
    v              = QtGui.QIntValidator(0, 32)
    self.nelmsEdt  = self.addRow( "# Elements",   "{:d}".format(tmplNelm), v)

    bsChoice       = [ PdoElement.bs2str( tmplSgnd, tmplBySz ) ]
    for isS in [True, False]:
      for bs in [1, 2, 4, 8]:
        bsChoice.append( PdoElement.bs2str( isS, bs ) )

    self.byteSzEdt = self.addRow( "Type", bsChoice )
    self.show()

  def delete(self):
    self.tbl.deleteItem( self.itm ) 

  def validInput(self):
    if ( len(self.nelmsEdt.text()) == 0 ):
      return "ERROR -- empty input: '# Elements'"
    if ( len(self.nameEdt.text()) == 0 ):
      return "ERROR -- empty input: 'name'"
    if ( len(self.indexEdt.text()) == 0 ):
      return "ERROR -- empty input: 'index'"
    name     = self.nameEdt.text()
    index    = int( self.indexEdt.text(), 16 )
    nelms    = int( self.nelmsEdt.text(),  0 )
    byteSz , isSigned = PdoElement.str2bs( self.byteSzEdt.text() )
    print("byteSz", byteSz, isSigned)
    if ( (byteSz is None) or (isSigned is None)):
      raise RuntimeError("Internal error: -- unable to convert byte size from string")
    msg      = self.tbl.modifyItem(self.itm, name, index, byteSz, nelms, isSigned)
    if not msg is None and len(msg) != 0:
      return msg
    return None

class MyHeaderModel(QtCore.QAbstractItemModel):
  def __init__(self, parent = None):
    super().__init__(parent)
  def rowCount(self, index):
    print("rowCount -- ", index.row(), index.column())
    return 6
  def columnCount(self, index):
    return 0

class MyHeader(QtWidgets.QHeaderView):
  def __init__(self, hdr, parent = None):
    super().__init__( QtCore.Qt.Vertical, hdr )
    self._mainHdr = hdr
    self.setModel( MyHeaderModel( self ) )
    self.span = 2
    i = 0
    while i < int(hdr.count()/self.span):
      print("resizeSection ", i)
      self.resizeSection( i, self.getSectionSizes( i*self.span, (i + 1 )*self.span - 1 ) )
      i += 1
    lst = hdr.count() - 1
    if ( lst >= i*self.span ):
      self.resizeSection( i, self.getSectionSizes( i*self.span, lst ) )
    self.sectionResized.connect( self.updateSizes )
    hdr.parentWidget().horizontalScrollBar().valueChanged.connect( self.updateOffset )
    self.setGeometry(0, 0, hdr.width(), hdr.height())
    self.updateOffset()
    hdr.installEventFilter( self )

  def getSectionSizes(self, f, t):
    sz = 0
    for i in range(f, t+1):
       sz += self._mainHdr.sectionSize(i)
    print("gss {} -> {} = {}".format(f, t, sz))
    return sz

  def updateSizes(self):
    self.updateOffset()
    self._mainHdr.resizeSection(2, self._mainHdr.sectionSize(2) + (self.sectionSize(0) - self.getSectionSizes(0, 2)))
    self._mainHdr.resizeSection(4, self._mainHdr.sectionSize(4) + (self.sectionSize(1) - self.getSectionSizes(3, 4)))
    self._mainHdr.resizeSection(6, self._mainHdr.sectionSize(6) + (self.sectionSize(2) - self.getSectionSizes(5, 6)))
    self._mainHdr.resizeSection(8, self._mainHdr.sectionSize(8) + (self.sectionSize(3) - self.getSectionSizes(7, 8)))
    self._mainHdr.resizeSection(10, self._mainHdr.sectionSize(10) + (self.sectionSize(4) - self.getSectionSizes(9, 10)))
    self._mainHdr.resizeSection(11, self._mainHdr.sectionSize(11) + (self.sectionSize(5) - self.getSectionSizes(11, 11)))

  def updateOffset(self):
    self.setOffset(self._mainHdr.offset())

  def eventFilter(self, o, e):
    if o == self._mainHdr:
      if ( e.type() == QtCore.QEvent.Resize ):
         self.updateOffset()
         self.setGeometry(0, 0, self._mainHdr.width(), self._mainHdr.height())
      return False
    return super().eventFilter(o, e)  

class FixedPdoSegment(PdoSegment):

  def __init__(self, name, byteOffset, nDWords, swap=1):
    super().__init__(name, byteOffset, nDWords, swap)

  def isFixed(self):
    return True

class PdoListWidget(TableWidgetDnD):

  NCOLS = 4

  def __init__(self, maxHwSegs, parent = None):
    super().__init__(0, self.NCOLS, parent)
    self._items           = list()
    self._segs            = list()
    self._used            = 0
    self._totsz           = 0
    self._renderDisabled  = False
    self._renderNeeded    = False
    self._verifySelection = True
    self._topL            = (-1,-1)
    self._botR            = (-1,-1)
    self._maxHwSegs       = maxHwSegs
    self.selectionModel().selectionChanged.connect( self.on_selection_changed )
    self.clearSelection()
    self.setCurrentCell( 0, 0, QtCore.QItemSelectionModel.Clear )
    self.cellDoubleClicked.connect( self.editItem )
    vh = self.verticalHeader()
    vh.setToolTip("In the left header column you can define 'segments' of\n"   +
                  "the EVR data buffer that shall be mapped into the TxPDO.\n" +
                  "Double-click or hover on an item in this column to edit.\n" +
                  "The named buttons mark segment boundaries; segments use\n"  +
                  "multiples of 32-bit words. Byte-swapping can be defined\n"  +
                  "for segments if needed.")
    self.horizontalHeader().setToolTip(
                  "In the matrix you can define PDO items and assign names,\n" +
                  "IDs and their size and data type. Items can be dragged\n"   +
                  "and dropped to rearrange them. You may define 'holes' by\n" +
                  "creating padding items with ID 0x0000.\n"                   +
                  "An item may be a (contiguous!) array of sub-items (which\n" +
                  "are automatically assigned sub-indices).\n"                 +
                  "If an item spans multiple lines a '--' mark is shown.\n"    +
                  "Create or edit items by double clicking into the matrix.\n" +
                  "Note that byte-swapping is a property of the *segment*\n"   +
                  "that holds a particular item.")
    vh.sectionDoubleClicked.connect( self.editSegment )
    vh.setContextMenuPolicy( QtCore.Qt.CustomContextMenu )
    vh.customContextMenuRequested.connect( self.headerMenuEvent )
    vh.setSectionResizeMode(QtWidgets.QHeaderView.ResizeToContents)
    self.horizontalHeader().setSectionResizeMode(QtWidgets.QHeaderView.ResizeToContents)
    self.setSizeAdjustPolicy(QtWidgets.QAbstractScrollArea.AdjustToContents)
    self.setAutoScroll(True) # auto-scroll when dragging
    # Yet another annoying issue - when scrollbars are managed automatically
    # the 'AdjustToContents' policy still reserves space for them even if they
    # are not visible - leading to ugly gaps. So we might as well leave them
    # on permanently :-(
    self.setVerticalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOn)
    self.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOn)
    self.setContextMenuPolicy( QtCore.Qt.CustomContextMenu )
    self.customContextMenuRequested.connect( self.tableMenuEvent )

  def hasFixedSegment(self):
    return ( len( self._segs ) > 0 and self._segs[0].isFixed() )

  def inFixedSegment(self, row):
    return self.hasFixedSegment() and (row < self._segs[0].nDWords)

  def tableMenuEvent(self, pt):
    def mkEdAct(s, r, c):
      def a():
        s.editItem(r, c)
      return a
    def mkDlAct(s, it):
      def a():
        s.deleteItem(it)
      return a

    print(pt)
    idx = self.indexAt( pt )
    r   = idx.row()
    c   = idx.column()

    if ( self.inFixedSegment( r ) ):
      return

    ctxtMenu = QtWidgets.QMenu( self )
    if ( r >= 0 and c >= 0 and  r * self.columnCount() + c < self._used ):
      ctxtMenu.addAction( "Edit PDO Item",   mkEdAct(self, r, c) )
      idx, off = self.atRowCol( r, c )
      ctxtMenu.addAction( "Delete PDO Item", mkDlAct(self, self._items[idx] ) )
    else:
      ctxtMenu.addAction( "New PDO Item",   mkEdAct(self, r, c) )
    ctxtMenu.popup( self.viewport().mapToGlobal( pt ) )

  def headerMenuEvent(self, pt):
    def mkEdtAct(s, r):
      def a():
        s.editSegment(r)
      return a
    def mkNewAct(s):
      def a():
        s.editSegment(-1)
      return a

    idx = self.indexAt( pt )
    r = idx.row()
    c = idx.column()

    if ( self.inFixedSegment( r ) ):
      return
    
    ctxtMenu = QtWidgets.QMenu( self )
    ctxtMenu.addAction( "Edit   Segment", mkEdtAct(self,  r) )
    ctxtMenu.addAction( "Create Segment", mkEdtAct(self, -1) )
    ctxtMenu.popup( self.verticalHeader().mapToGlobal( pt ) )

  def editItem(self, r, c):
    if ( self.inFixedSegment(r) ):
      return
    if r * self.columnCount() + c >= self._used:
      it = None
    else:
      idx, off = self.atRowCol( r, c )
      it = self._items[idx]
    w = self.cellWidget(r, c)
    if ( w is None ):
      w = self
    ItemEditor( w, self, it )

  def editSegment(self, r):
    if ( r < 0 or not self.inFixedSegment( r ) ):
      SegmentEditor( self, self, self.r2seg( r ) )

  def seg2bo(self, seg):
    off = 0
    for s in self._segs:
      if s == seg:
        return off
      off += s.nDWords * self.NCOLS
    raise RuntimeError("segment not found in list")

  def r2seg(self, r):
    mx = len(self._segs) - 1
    if ( mx < 0 or r < 0 ):
      return None
    rr = 0
    for s in self._segs:
      nrr = rr + s.nDWords
      if rr <= r and r < nrr:
        break
      rr = nrr
    return s

  def modifySegment(self, seg, name, pos, byteOffset, nelms, swap):
    newSeg = (seg is None)
    maxPos = len(self._segs) - 1
    if ( newSeg ):
      maxPos += 1
    minPos = 0
    if ( self.hasFixedSegment() ):
      minPos = 1
    if ( pos < minPos or pos > maxPos ):
      return "ERROR -- position out of range ({}..{})".format(minPos, maxPos)
    if ( self._totsz + self.NCOLS * nelms > FirmwareConstants.ESC_SM_MAX_LEN( FirmwareConstants.TXPDO_SM() ) ):
      return "ERROR -- requested segment size would exceed firmware TXPDO size limit"
    try:
      # avoid partial modification; create a dummy object to verify
      # arguments; if this doesn't throw we are OK
      nseg = PdoSegment(name, byteOffset, nelms, swap)

      if (newSeg):
        seg = nseg
        self.addSegment( nseg )
      else:
        rowDiff         = nelms - seg.nDWords
        wouldHave       = self._totsz + rowDiff * self.NCOLS
        if ( wouldHave < self._used ):
          raise ValueError("reducing Segment not possible -- delete Elements first")
        self.setRowCount( self.rowCount() + rowDiff )
        seg.name        = name
        seg.byteOffset  = byteOffset
        seg.nDWords     = nelms
        seg.swap        = swap
        self._totsz     = wouldHave

      self._segs.remove( seg )
      self._segs.insert( pos, seg )
      self.renderSegments()
      return None

    except Exception as e:
      if newSeg:
        s = "create new"
      else:
        s = "modify"
      return "ERROR - unable to {} segment - \n{}".format(s, e.args[0])
    

  def modifyItem(self, it, name, index, byteSz, nelms, isSigned):
    newEl = (it is None)
    try:
      # create a new element -- avoid modifying the original one
      # in case there is an exception
      nit = PdoElement( name, index, byteSz, nelms, isSigned )

      if ( it is None ):
        it  = nit
        pos = len(self._items)
        self.insert( None, it )
        try:
          self.selectItemRange( pos )
        except Exception as e:
          print("Warning - unable to select new item")
          print( e.args[0] )
        self.render()
        return None
      else:
        if (     name     == it.name
           and nelms    == it.nelms
           and index    == it.index
           and byteSz   == it.byteSz
           and isSigned == it.isSigned ):
          return None

      currentUse = it.byteSz * it.nelms
      wouldUse   = (byteSz * nelms) - currentUse + self._used

      if (  wouldUse > self._totsz ):
        return "ERROR -- not enough space\nreduce item size/nelms"

      it.name     = name
      it.index    = index
      it.byteSz   = byteSz
      it.nelms    = nelms
      it.isSigned = isSigned
      self._used  = wouldUse
      self.selectItemRange( self._items.index( it ) )
      self.render()
      return None
    except Exception as e:
      if newEl:
        s = "create new"
      else:
        s = "edit"
      return "ERROR - unable to {} element - \n{}".format(s, e.args[0])

  def deleteItem(self, it):
    self._items.remove( it )
    self._used -= it.byteSz * it.nelms
    # make sure selection is within valid bounds
    self.selectItemRange( -1 )
    self.render()

  @contextmanager
  def lockSelection(self):
    prev = self._verifySelection
    self._verifySelection = False
    try:
      yield prev
    finally:
      self._verifySelection = prev

  def verifySelection(self):
    return self._verifySelection

  def insertColumn(self, col):
    raise RuntimeError("Number of columns cannot be changed")

  def removeColumn(self, col):
    raise RuntimeError("Number of columns cannot be changed")

  def insertRow(self, row):
    super().insertRow(row)
    self._totsz += self.columnCount()

  def needRender(self):
    self._renderNeeded = True

  def renderDisable(self, val):
    rv = self._renderDisabled
    if ( not val is None ):
      self._renderDisabled = val
      if ( rv and not val and self._renderNeeded ):
        self._renderNeeded = False
        self.render()
    return rv

  def removeRow(self, row):
    if ( self._totsz - self.columnCount() < self._used ):
      raise RuntimeError("Cannot remove row (not enough space left) - must remove items first")
    super().removeRow(row)
    self._totsz -= self.columnCount()

  def atByteOffset(self, byteOff):
    if ( len(self._items) < 0 ):
      raise RuntimeError("atByteOffset on empty list")
    if ( byteOff < 0 ):
      return 0,0
    off = 0
    l   = 0
    for i in range(len(self._items)):
      l    = self._items[i].byteSz * self._items[i].nelms
      noff = off + l
      if byteOff >= off and byteOff < noff:
        return i, off
      off = noff
    i = len(self._items) - 1
    return i, off - l

  def atRowCol(self, row, col):
    idx, off = self.atByteOffset(self.rc2bo(row, col))
    return idx, off

  def bo2rc(self, byteoff):
    r = int(byteoff / self.columnCount())
    c =     byteoff % self.columnCount()
    return r,c

  def idx2bo(self, idx):
    off = 0
    if ( idx > len(self._items) ):
      idx = len(self._items)
    for i in range(idx):
      off += self._items[i].byteSz * self._items[i].nelms
    return off

  def idx2rc(self, idx):
    return self.bo2rc( self.idx2bo( idx ) )

  def rc2bo(self, r,c):
    return r*self.columnCount() + c

  def add(self, el, disableRender = True):
    return self.insert( None, el, disableRender )

  def insert(self, pos, el, disableRender = True):
    if pos is None:
      # append
      pos = len(self._items)
    if isinstance(el, list):
      for e in el:
        self.insert(pos, e)
        pos += 1
      if not disableRender:
        self.render()
    else:
      if ( not isinstance( el, PdoElement ) ):
        raise ValueError("may only add a PdoElement object")
    need = el.byteSz * el.nelms
    if ( need + self._used > self._totsz ):
      raise RuntimeError("cannot add element - not enough space (add rows)")
    self._used += need
    self._items.insert( pos, el )
    if (disableRender):
      self.needRender()
    else:
      self.render()

  def coverage(self, rowF, colF, rowT = -1, colT = -1):
    if ( colT < 0 ):
      colT = colF
    if ( rowT < 0 ):
      rowT = rowF
    fst_idx, fst_bo = self.atRowCol(rowF, colF)
    bottom          = fst_bo
    lst_idx, lst_bo = self.atRowCol(rowT, colT)
    top      = lst_bo + self._items[lst_idx].nelms * self._items[lst_idx].byteSz - 1
    br, bc   = self.bo2rc( bottom )
    tr, tc   = self.bo2rc( top    )
    return br, bc, tr, tc

  # avoid annoying warnings
  def setSpan(self, r, c, rs, cs):
    prevr = self.rowSpan(r, c)
    prevc = self.columnSpan(r, c)
    if ((prevr != rs) or (prevc != cs) ):
      super().setSpan( r, c, rs, cs )

  MODE_FITS = 0
  MODE_BEG  = 1
  MODE_MID  = 2
  MODE_END  = 3

  def mkItemWidget(self, itm, sub, mode):
    if   mode == self.MODE_BEG:
      lbl = QtWidgets.QLabel( "{:04x}.{:02x} --".format( itm.index, sub ) )
    elif mode == self.MODE_MID:
      lbl = QtWidgets.QLabel( "-- {:04x}.{:02x} --".format( itm.index, sub ) )
    elif mode == self.MODE_END:
      lbl = QtWidgets.QLabel( "-- {:04x}.{:02x}".format( itm.index, sub ) )
    else:
      lbl = QtWidgets.QLabel( "{:04x}.{:02x}".format( itm.index, sub ) )
    lbl.setToolTip( itm.name )
    return lbl

  def render(self, trq_row = -1, trq_col = -1, brq_row = -1, brq_col = -1):
    with self.lockSelection():

      self.renderSegments()

      if ( 0 == len( self._items ) ):
        return

      if ( trq_row < 0 ):
        trq_row = 0
      if ( trq_col < 0 ):
        trq_col = 0
      if ( brq_row < 0 ):
        brq_row = self.rowCount() - 1
      if ( brq_col < 0 ):
        brq_col = self.columnCount() - 1
      if ( trq_row >= self.rowCount() or brq_row >= self.rowCount() ):
        raise RuntimeError("render: requested row out of range")
      if ( trq_col >= self.columnCount() or brq_col >= self.columnCount() ):
        raise RuntimeError("render: requested column out of range")

      # make sure we use all the cells covered by the items
      top_row, top_col, bot_row, bot_col = self.coverage( trq_row, trq_col, brq_row, brq_col )

      ii, off = self.atRowCol( top_row, top_col )
      n  = 0
      r  = top_row
      c  = top_col
      print("bot_row, bot_col ", bot_row, bot_col, self.rowCount(), self.columnCount())
      while ( (r < bot_row or (r == bot_row and c <= bot_col)) and (ii < len(self._items)) ):
        it = self._items[ii]
        l  = it.byteSz
        print("Rendering {}.{}, length {}".format(r,c,l))
        if c + l <= self.columnCount():
          for cel in range(c, c+l):
            self.setCellWidget( r, cel, None )
            self.setSpan( r, cel, 1, 2 )
            self.setSpan( r, cel, 1, 1 )
          self.setSpan( r, c, 1, l )
          lbl = self.mkItemWidget( it, n+1, self.MODE_FITS )
          self.setCellWidget( r, c, lbl )
          c += l
        else:
          for cel in range(c, self.columnCount()):
            self.setCellWidget( r, cel, None )
            self.setSpan( r, cel, 1, 1 )
          self.setSpan( r, c, 1, self.columnCount() - c )
          lbl = self.mkItemWidget( it, n+1, self.MODE_BEG )
          self.setCellWidget( r, c, lbl )
          l -= self.columnCount() - c
          r += 1
          c  = 0
          while l > self.columnCount():
            for cel in range(0, self.columnCount()):
              self.setCellWidget( r, cel, None )
              self.setSpan( r, cel, 1, 1 )
            self.setSpan( r, c, 1, self.columnCount() )
            lbl = self.mkItemWidget( it, n+1, self.MODE_MID )
            self.setCellWidget( r, c, lbl )
            r += 1
            l -= self.columnCount()
          for cel in range(c , c + l):
            self.setCellWidget( r, cel, None )
            self.setSpan( r, cel, 1, 1 )
          self.setSpan( r, c, 1, l )
          lbl = self.mkItemWidget( it, n+1, self.MODE_END )
          self.setCellWidget( r, c, lbl )
          c += l
        n += 1 
        if ( n >= it.nelms ):
          n   = 0
          ii += 1
        while c >= self.columnCount():
          c -= self.columnCount()
          r += 1
        print("new iteracion ", r, c, ii)

      # make sure the rest of the table is cleared (in case we
      # deleted elements
      while r < brq_row or (r == brq_row and c <= brq_col):
        self.setSpan      ( r, c, 1, 1)
        self.setCellWidget( r, c, None )
        c += 1
        if ( c == self.columnCount() ):
          c  = 0
          r += 1

      self._renderNeeded = False
      self.showSelection()

  def on_selection_changed(self, a, b):
    if not self.verifySelection():
      return

    # just a single item selected; reset selection span
    cr = self.currentRow()
    cc = self.currentColumn()

    if self.inFixedSegment(cr):
      print("CR FIXED")
      self._topL = (-1, -1)
      self._botR = (-1, -1)
      self.showSelection()
      return

    if ( (1 == len(self.selectedIndexes())) or ( self._topL[0] < 0 ) ):
      if self.cellWidget( cr, cc ) is None:
        # single cell outside of the configured are
        self._topL = (-1, -1)
        self._botR = (-1, -1)
        self.showSelection()
        return
      self._topL = ( cr, cc )
      self._botR = self._topL
    else:
      # extend or reduce the existing selection based on where the
      # 'current' index lies
      if   ( ( cr < self._topL[0] ) or ( (cr == self._topL[0]) and (cc <= self._topL[1]) ) ):
        # 'current' to top-left of topL
        self._topL = (cr, cc)
      elif ( ( cr > self._botR[0] ) or ( (cr == self._botR[0]) and (cc >= self._botR[1]) ) ):
        # 'current' to bot-right of botR
        self._botR = (cr, cc)
      else:
        dtl =  (cr - self._topL[0]) * self.columnCount() + (cc - self._topL[1])
        dbr = -(cr - self._botR[0]) * self.columnCount() - (cc - self._botR[1])
        # distance to topL < distance to botR
        if ( dtl < dbr ):
          self._topL = (cr, cc)
        else:
          self._botR = (cr, cc)

    # make sure we cover all elements of arrays
    tr,tc,br,bc = self.coverage( self._topL[0], self._topL[1], self._botR[0], self._botR[1] )
    self._topL = (tr, tc)
    self._botR = (br, bc)

    print("SELCH", a, b, len(a), len(b), len(self.selectedIndexes()))
    self.showSelection()

  def showSelection(self):
    with self.lockSelection():
      minr = self._topL[0]
      minc = self._topL[1]
      maxr = self._botR[0]
      maxc = self._botR[1]
      self.setCurrentCell( minr, minc, QtCore.QItemSelectionModel.Clear )
      self.setCurrentCell( minr, minc, QtCore.QItemSelectionModel.SelectCurrent )
      if ( minr < 0 or maxr < 0 ):
        return # nothing selected
      print("showSelection ", minr, minc, maxr, maxc)
      r = minr
      c = minc
      while ( r < maxr ) or ( ( r == maxr ) and ( c <= maxc ) ):
        print("Adding {}/{}".format(r,c))
        self.setRangeSelected( QtWidgets.QTableWidgetSelectionRange(r,c,r,c), True )
        c += self.columnSpan( r, c )
        if ( c >= self.columnCount() ):
          c  = 0
          r += 1

  def selectItemRange(self, elIdxFrom, elIdxTo = -1):
    if ( elIdxTo < 0 ):
      elIdxTo = elIdxFrom

    if ( elIdxTo >= len(self._items) ):
      elIdxTo = len(self._items) - 1

    if ( len(self._items) == 0 ):
      self._topL = (-1, -1)
      self._botR = (-1, -1)
      return

    if ( ( elIdxFrom < 0 ) ):
      # just verify the current range
      rf, cf         = self._topL[0], self._topL[1]
      rt, ct         = self._botR[0], self._botR[1]
    else:
      rf,cf           = self.idx2rc( elIdxFrom )
      rt,ct           = self.idx2rc( elIdxTo   )
    rf, cf, rt, ct  = self.coverage( rf, cf, rt, ct )
    self._topL      = (rf, cf)
    self._botR      = (rt, ct)

  def moveItems(self, drop_row, drop_col, from_row, from_col, to_row, to_col):
    # ignore 'from' -- we have the selected indices stored in self._topL/self._topR
    dst_idx, dst_off = self.atRowCol( drop_row, drop_col )
    frm_idx, frm_off = self.atRowCol( self._topL[0], self._topL[1] )
    end_idx, end_off = self.atRowCol( self._botR[0], self._botR[1] )
    if ( frm_idx == dst_idx or (dst_idx > frm_idx and dst_idx <= end_idx) ):
      return
    if ( self.inFixedSegment( drop_row ) ):
      return
    print("MoveItems, dst_idx", dst_idx)
    nl = []
    if ( dst_idx < 0 ):
      return
    elif ( dst_idx < frm_idx ):
      nl += self._items[0            : dst_idx    ]
      nl += self._items[frm_idx      : end_idx + 1]
      nl += self._items[dst_idx      : frm_idx    ]
      nl += self._items[end_idx + 1  :            ]
      tgt_idx = dst_idx
    else:
      nl += self._items[0            : frm_idx    ]
      nl += self._items[end_idx + 1  : dst_idx + 1]
      nl += self._items[frm_idx      : end_idx + 1]
      nl += self._items[dst_idx + 1  :            ]
      # dst_idx > end_idx has been verified!
      tgt_idx = frm_idx + dst_idx - end_idx
    self._items = nl
    tgt_off = self.idx2bo( tgt_idx )
    print("TGT_OFF / IDX ", tgt_off, tgt_idx )

    off_diff  = self.rc2bo( self._botR[0], self._botR[1] )
    off_diff -= self.rc2bo( self._topL[0], self._topL[1] )
    
    r,c  = self.bo2rc( tgt_off )
    self._topL  = (r, c)
    r,c  = self.bo2rc( tgt_off + off_diff )
    self._botR  = (r, c)
    self.render() 
    self.showSelection()

  def hwSegmentsUsed(self, seg = None ):
    # word-swapping is implemented by using
    # two 'real' mappings per longword
    rv = 0
    if seg is None:
      for s in self._segs:
        rv += self.hwSegmentsUsed( s )
    else:
      if 8 == seg.swap:
        rv += seg.nDWords
      else:
        rv += 1
    return rv

  def addSegment(self, seg):
    if not isinstance(seg, PdoSegment):
      raise ValueError("addSegment requres a 'PdoSegment' object'")
    # 8-byte swap is emulated by using two mappings per dword!
    if ( self.hwSegmentsUsed() + self.hwSegmentsUsed( seg ) > self._maxHwSegs ):
      raise ValueError("unable to add segment; not enough firmware resources\n" +
                       "(max. {}).\n".format(self._maxHwSegs) +
                       "NOTE: 8-byte swap is emulated by using TWO actual maps\n" +
                       "      per dword!")
    # make a copy since we will be editing the segment
    self._segs.append( seg.clone() )
    self._totsz += seg.nDWords * self.NCOLS
    self.setRowCount( self.rowCount() + seg.nDWords )
    self.render()

  def deleteSegment(self, seg):
    try:
      if not seg in self._segs:
        raise ValueError("segment not found")

      newTotal = self._totsz - seg.nDWords * self.NCOLS
      off      = self.seg2bo(seg)
      if off < self._used:
        raise RuntimeError("cannot delete segment in use - (delete PDO elements first)")

      self._segs.remove(seg)
      r = int(off / self.NCOLS)
      self.setRowCount( r )
      self.renderSegments()
      return None
    except Exception as e:
      return "ERROR -- unable to delete segment\n" + e.args[0]

  def renderSegments(self):
    r  = 0
    bru = QtGui.QBrush( QtGui.QColor( 255, 255, 255, 0) )
    for s in self._segs:
      hitm = QtWidgets.QTableWidgetItem()
      hitm.setText( s.name )
      self.setVerticalHeaderItem(r, hitm)
      r += 1
      for i in range(1, s.nDWords):
        eitm = QtWidgets.QTableWidgetItem()
        eitm.setBackground( bru )
        self.setVerticalHeaderItem(r, eitm)
        r += 1
