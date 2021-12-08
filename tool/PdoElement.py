#from PyQt5.QtCore import Qt, QPoint, QItemSelection, QItemSelectionModel
#from PyQt5.QtGui import QDropEvent
#from PyQt5.QtWidgets import QTableWidget, QAbstractItemView, QTableWidgetItem, QTableWidgetSelectionRange
from PyQt5           import QtCore, QtGui, QtWidgets
from TableWidgetDnD  import TableWidgetDnD
from contextlib      import contextmanager

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

class ItemEditor(QtWidgets.QDialog):

  def __init__(self, parent, tbl, itm = None):
    super().__init__( parent )
    self.tbl = tbl
    self.itm = itm
    if ( itm is None ):
      tit = "Create New Item"
    else:
      tit = "Editing " + itm.name
    self.setWindowTitle( tit )
    self.buttonBox = QtWidgets.QDialogButtonBox( QtWidgets.QDialogButtonBox.Ok | QtWidgets.QDialogButtonBox.Cancel )
    self.buttonBox.accepted.connect( self.accept )
    self.buttonBox.rejected.connect( self.reject )
    self.layout    = QtWidgets.QGridLayout()

    self.nameEdt  = self.addRow( "Name",          itm.name )
    v             = QtGui.QRegExpValidator(QtCore.QRegExp("[0-9a-fA-F]+"))
    self.indexEdt = self.addRow( "Index (hex)",  "{:04x}".format(itm.index), v)
    v             = QtGui.QIntValidator(0, 32)
    self.nelmsEdt = self.addRow( "# Elements",   "{:d}".format(itm.nelms), v)

    self.msgLbl   = QtWidgets.QLabel("")
    self.layout.addWidget( self.msgLbl,    self.layout.rowCount(), 0, 1, self.layout.columnCount() )
    self.layout.addWidget( self.buttonBox, self.layout.rowCount(), 0, 1, self.layout.columnCount() )
    self.setLayout( self.layout    )
    while self.exec():
      msg = self.validInput()
      if msg is None: 
        return
      self.msgLbl.setText( msg )
      # keep executing

  def validInput(self):
    if ( len(self.nelmsEdt.text()) == 0 ):
      return "ERROR -- empty input: '# Elements'"
    if ( len(self.nameEdt.text()) == 0 ):
      return "ERROR -- empty input: 'name'"
    if ( len(self.indexEdt.text()) == 0 ):
      return "ERROR -- empty input: 'index'"
    name   = self.nameEdt.text()
    index  = int( self.indexEdt.text(), 16 )
    nelms  = int( self.nelmsEdt.text(),  0 )
    if self.itm is None:
      raise RuntimeError("Creating new items not implemented yet")
    if not self.tbl.modifyItem(self.itm, name, index, nelms):
      return "ERROR -- not enough space\nreduce item size/nelms"
    return None

  def addRow(self, lbl, ini, val = None):
    r = self.layout.rowCount()
    self.layout.addWidget( QtWidgets.QLabel(lbl), r, 0 )
    ledt = QtWidgets.QLineEdit()
    ledt.setMaxLength( 40 )
    ledt.setText( ini )
    ledt.setValidator( val )
    self.layout.addWidget( ledt, r, 1 )
    return ledt

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

class PdoListWidget(TableWidgetDnD):

  def __init__(self, *args, **kwargs):
    super().__init__(*args, **kwargs)
    self._items           = list()
    self._used            = 0
    self._totsz           = self.columnCount() * self.rowCount()
    self._renderDisabled  = False
    self._renderNeeded    = False
    self._verifySelection = True
    self._topL            = (-1,-1)
    self._botR            = (-1,-1)
    self.selectionModel().selectionChanged.connect( self.on_selection_changed )
    self.clearSelection()
    self.setCurrentCell( 0, 0, QtCore.QItemSelectionModel.Clear )
    self.cellDoubleClicked.connect( self.editItem )
    self.verticalHeader().setVisible(True)

#    MyHeader( self.verticalHeader() )

  def editItem(self, r, c):
    print("Double-click ", r, c)
    if r * self.columnCount() + c > self._used:
      it = None
    else:
      idx, off = self.atRowCol( r, c )
      it = self._items[idx]
    ItemEditor( self.cellWidget(r, c), self, it )

  def modifyItem(self, it, name = None, index = None, nelms = None, byteSz = None, isSigned = None):
    if ( name is None ):
      name = it.name
    if ( index is None ):
      index = it.index
    if ( nelms is None ):
      nelms = it.nelms
    if ( byteSz is None ):
      byteSz = it.byteSz
    if ( isSigned is None ):
      isSigned = it.isSigned
    if (     name     == it.name
         and nelms    == it.nelms
         and index    == it.index
         and byteSz   == it.byteSz
         and isSigned == it.isSigned ):
      return True
    wouldUse = (byteSz * nelms) - (it.byteSz * it.nelms) + self._used
    if (  wouldUse > self._totsz ):
      return False
    if ( byteSz != it.byteSz or nelms != it.nelms ):
      self._topL = (-1, -1)
      self._topR = (-1, -1)
    it.name     = name
    it.index    = index
    it.byteSz   = byteSz
    it.nelms    = nelms
    it.isSigned = isSigned
    self._used  = wouldUse
    print("New Name: ", name)
    self.render()
    return True

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

  def add(self, el, disableRender = True):
    if isinstance(el, list):
      for e in el:
        self.add(e)
    else:
      if ( not isinstance( el, PdoElement ) ):
        raise ValueError("may only add a PdoElement object")
    need = el.byteSz * el.nelms
    if ( need + self._used > self._totsz ):
      raise RuntimeError("cannot add element - not enough space (add rows)")
    self._used += need
    self._items.append( el )
    if (disableRender):
      self.needRender()
    else:
      self.render()

  def idx2bo(self, idx):
    off = 0
    if ( idx > len(self._items) ):
      idx = len(self._items)
    for i in range(idx):
      off += self._items[i].byteSz * self._items[i].nelms
    return off

  def rc2bo(self, r,c):
    return r*self.columnCount() + c

  def coverage(self, row, col):
    idx, off = self.atRowCol(row, col)
    bottom   = off
    top      = bottom + self._items[idx].nelms * self._items[idx].byteSz - 1
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

  def render(self, top_row = -1, top_col = -1, bot_row = -1, bot_col = -1):
    with self.lockSelection():
      if ( top_row < 0 ):
        top_row = 0
      if ( top_col < 0 ):
        top_col = 0
      if ( bot_row < 0 ):
        bot_row = self.rowCount() - 1
      if ( bot_col < 0 ):
        bot_col = self.columnCount() - 1
      if ( top_row >= self.rowCount() or bot_row >= self.rowCount() ):
        raise RuntimeError("render: requested row out of range")
      if ( top_col >= self.columnCount() or bot_col >= self.columnCount() ):
        raise RuntimeError("render: requested column out of range")
      # make sure we use all the cells covered by the items
      top_row, top_col, r, c = self.coverage( top_row, top_col )
      r, c, bot_row, bot_col = self.coverage( bot_row, bot_col )

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
      self._renderNeeded = False
      self.setCurrentCell( 0, 0, QtCore.QItemSelectionModel.Clear )
      self.clearSelection()

  def on_selection_changed(self, a, b):
    if not self.verifySelection():
      return

    # just a single item selected; reset selection span
    cr = self.currentRow()
    cc = self.currentColumn()
    if ( (1 == len(self.selectedIndexes())) or ( self._topL[0] < 0 ) ):
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
    tr,tc,br,bc = self.coverage( self._topL[0], self._topL[1] )
    self._topL = (tr, tc)
    tr,tc,br,bc = self.coverage( self._botR[0], self._botR[1] )
    self._botR = (br, bc)

    print("SELCH", a, b, len(a), len(b), len(self.selectedIndexes()))
    self.doSelect(self._topL[0], self._topL[1], self._botR[0], self._botR[1])

  def doSelect(self, minr, minc, maxr, maxc):
    with self.lockSelection():
      self.setCurrentCell( minr, minc, QtCore.QItemSelectionModel.Clear )
      self.setCurrentCell( minr, minc, QtCore.QItemSelectionModel.SelectCurrent )
      print("doSelect ", minr, minc, maxr, maxc)
      r = minr
      c = minc
      while ( r < maxr ) or ( ( r == maxr ) and ( c <= maxc ) ):
        print("Adding {}/{}".format(r,c))
        self.setRangeSelected( QtWidgets.QTableWidgetSelectionRange(r,c,r,c), True )
        c += self.columnSpan( r, c )
        if ( c >= self.columnCount() ):
          c  = 0
          r += 1

  def moveItems(self, drop_row, drop_col, from_row, from_col, to_row, to_col):
    # ignore 'from' -- we have the selected indices stored in self._topL/self._topR
    dst_idx, dst_off = self.atRowCol( drop_row, drop_col )
    frm_idx, frm_off = self.atRowCol( self._topL[0], self._topL[1] )
    end_idx, end_off = self.atRowCol( self._botR[0], self._botR[1] )
    if ( frm_idx == dst_idx or (dst_idx > frm_idx and dst_idx <= end_idx) ):
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
    self.doSelect(self._topL[0], self._topL[1], self._botR[0], self._botR[1])
