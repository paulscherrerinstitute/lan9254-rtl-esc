from   PyQt5      import QtCore, QtGui, QtWidgets
from   PdoElement import PdoElement, DialogBase
import sys

class PdoElementGroup(object):
  def __init__(self, pdoElementList, checked=True):
    if isinstance(pdoElementList, list):
      for e in pdoElementList:
        self.check(e)
      self._elements = pdoElementList
    else:
      self.check(pdoElementList)
      self._elements = list(pdoElementList)
    self._checked = checked

  @property
  def elements(self):
    return self._elements

  @property
  def initiallyOn(self):
    return self._checked

  def check(self, el):
    if not isinstance(el, PdoElement):
      raise ValueError("PdoElement object expected")

class LineEditChecker(QtWidgets.QCheckBox):
  def __init__(self, *args, **kwargs ):
    super().__init__(*args, **kwargs)
    self._ledt = list()
    self._pal  = QtGui.QPalette()
    self._rop  = QtGui.QPalette()
    self._rop.setColor( QtGui.QPalette.Base, QtCore.Qt.gray )
    self._rop.setColor( QtGui.QPalette.Text, QtCore.Qt.darkGray )
    self.stateChanged.connect( self )
    initiallyOn = kwargs.get("checked")
    if initiallyOn is None:
      initiallyOn = True
    self.setChecked( initiallyOn )
    print("FOO")

  def add(self, ledt):
    if not isinstance(ledt, QtWidgets.QLineEdit):
      raise RuntimeError("Internal Error -- QLineEdit object expected")
    self._ledt.append(ledt)
    # just save one of them -- assuming they are identical
    self._pal = ledt.palette()
    self.setLineEditState( ledt )

  def setLineEditState(self, ledt):
    checked = (self.checkState() != QtCore.Qt.Unchecked)
    if ( checked ):
      pal = self._pal
    else:
      pal = self._rop
    ledt.setReadOnly( checked )
    ledt.setPalette( pal )

  def __call__(self, onoff):
    for l in self._ledt:
      self.setLineEditState( l )

class FixedPdoForm(object):
  def __init__(self, pdoElementList, parent = None):
    self._top = QtWidgets.QVBoxLayout()
    vb = self._top
    lbl = QtWidgets.QLabel("Standard PDO Entries")
    lbl.setAlignment(QtCore.Qt.AlignCenter)
    vb.addWidget( lbl )
#    vb.addItem( QtWidgets.QSpacerItem(5, 50) )
    lbl = QtWidgets.QLabel("Use checkbox to include/exclude from PDO")
    lbl.setAlignment(QtCore.Qt.AlignCenter)
    vb.addWidget( lbl )
    self._frm = QtWidgets.QFormLayout()
    self._frm.addRow( QtWidgets.QLabel("Name"), QtWidgets.QLabel("Index (hex)") )
    vb.addLayout( self._frm )
    if not pdoElementList is None:
      self.addGroup( pdoElementList )

  def addGroup(self, grp):
    if   ( isinstance(grp, PdoElementGroup) ):
      els = grp.elements
      chk = self.addRow( els[0], checker=None, checked = grp.initiallyOn )
      for e in els[1:]:
        self.addRow( e, checker=chk )
    elif ( isinstance(grp, PdoElement)      ):
      self.addRow( grp, checker=None )
    elif ( isinstance(grp, list) ):
      for e in grp:
        self.addGroup( e )
    else:
      raise ValueError("Only PdoElement or PdoElementGroup objects may be added to FixedPdoForm")

  def addRow(self, pdoEl, checker = None, checked = True):
    def mkEdtDon(w, e):
      def a():
        print("EDIT DONE")
        e.index = int(w.text(), 16)
      return a
    def mkEdtRst(w, e):
      def a():
        print("RESTORE")
        w.setText( "{:04x}".format( e.index ) )
        e.index = int(w.text(), 16)
      return a
    ledt = QtWidgets.QLineEdit()
    ledt.setMaxLength( 8 )
    mkEdtRst(ledt, pdoEl)()
    ledt.editingFinished.connect( mkEdtRst( ledt, pdoEl ) )
    ledt.returnPressed.connect( mkEdtDon( ledt, pdoEl ) )
    val  = QtGui.QRegExpValidator(QtCore.QRegExp("[0-9a-fA-F]{1,4}"))
    ledt.setValidator( val )
    # Use a dummy (invisible) checkbox to get things to line up...
    lblw = QtWidgets.QWidget()
    wlay = QtWidgets.QHBoxLayout()
    wlay.setContentsMargins(0,0,0,0)
    if not isinstance(checker, LineEditChecker):
      chk = LineEditChecker( checked=checked )
      checker = chk
    else:
      chk = QtWidgets.QCheckBox()
      pol = chk.sizePolicy()
      pol.setRetainSizeWhenHidden(True)
      chk.setSizePolicy(pol)
      chk.hide()
    wlay.addWidget( chk )
    wlay.addWidget(QtWidgets.QLabel( pdoEl.name ))
    lblw.setLayout(wlay)
    checker.add( ledt )
    self._frm.addRow( lblw, ledt )
    return checker

  @property
  def topLayout(self):
    return self._top

app = QtWidgets.QApplication(sys.argv)

window = QtWidgets.QWidget()
f = FixedPdoForm(None)
e = [ PdoElement("TimestampHi", 0x1100, 4), PdoElement("TimestampLo", 0x1101, 4) ]
g = PdoElementGroup( e, False )
f.addGroup( g )
f.addGroup( PdoElement("EventSet", 0x1102, 4, 4) )

window.setLayout( f.topLayout )
window.show()
app.exec()
