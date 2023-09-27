##############################################################################
##      Copyright (c) 2022#2023 by Paul Scherrer Institute, Switzerland
##      All rights reserved.
##  Authors: Till Straumann
##  License: GNU GPLv2 or later
##############################################################################

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
      self._elements = [ pdoElementList ]
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
  def __init__(self, pdoForm, *args, **kwargs ):
    super().__init__(*args, **kwargs)
    self._ledt = list()
    self._pal  = QtGui.QPalette()
    self._rop  = QtGui.QPalette()
    self._rop.setColor( QtGui.QPalette.Base, QtCore.Qt.gray )
    self._rop.setColor( QtGui.QPalette.Text, QtCore.Qt.darkGray )
    self._pdoForm = pdoForm
    self.stateChanged.connect( self )
    initiallyOn = kwargs.get("checked")
    if initiallyOn is None:
      initiallyOn = True
    self.setChecked( initiallyOn )

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
    ledt.setReadOnly( not checked )
    ledt.setPalette( pal )

  def __call__(self, onoff):
    self._pdoForm._modified = True
    for l in self._ledt:
      self.setLineEditState( l )

class FixedPdoForm(object):
  def __init__(self, pdoElementList, parent = None):
    self._top = QtWidgets.QVBoxLayout()
    vb = self._top
    lbl = QtWidgets.QLabel("Standard PDO Entries")
    lbl.setObjectName("H2")
    vb.addWidget( lbl )
    lbl = QtWidgets.QLabel("Use checkbox to include/exclude from PDO")
    vb.addWidget( lbl )
    self._frm = QtWidgets.QFormLayout()
    self._frm.addRow( QtWidgets.QLabel("Name"), QtWidgets.QLabel("Index (hex)") )
    vb.addLayout( self._frm )
    self._groups = list()
    if not pdoElementList is None:
      self.addGroup( pdoElementList )
    self._modified = False

  @property
  def modified(self):
    return self._modified

  def resetModified(self):
    self._modified = False

  def addGroup(self, grp, checked = True):
    if   ( isinstance(grp, PdoElementGroup) ):
      els = grp.elements
      chk = self.addRow( els[0], checker=None, checked = grp.initiallyOn )
      for e in els[1:]:
        self.addRow( e, checker=chk )
      self._groups.append( (grp, chk) )
    elif ( isinstance(grp, PdoElement)      ):
      chk = self.addRow( grp, checker=None, checked=checked )
      self._groups.append( (PdoElementGroup(grp), chk) )
    elif ( isinstance(grp, list) ):
      for e in grp:
        self.addGroup( e )
    else:
      raise ValueError("Only PdoElement or PdoElementGroup objects may be added to FixedPdoForm")

  def getGuiVals(self):
    l = list()
    m = 1
    f = 0
    for g in self._groups:
      if g[1].isChecked():
        f |= m
        for e in g[0].elements:
          l.append(e)
      m <<= 1
    return f, l;

  def addRow(self, pdoEl, checker = None, checked = True):
    def mkEdtDon(s, w, e):
      def a():
        e.index     = int(w.text(), 16)
        s._modified = True
      return a
    def mkEdtRst(w, e):
      def a():
        w.setText( "{:04x}".format( e.index ) )
        e.index = int(w.text(), 16)
      return a
    ledt = QtWidgets.QLineEdit()
    ledt.setMaxLength( 8 )
    mkEdtRst(ledt, pdoEl)()
    ledt.editingFinished.connect( mkEdtRst( ledt, pdoEl ) )
    ledt.returnPressed.connect( mkEdtDon( self, ledt, pdoEl ) )
    if ( not pdoEl.help is None ):
      ledt.setToolTip( pdoEl.help )
    val  = QtGui.QRegExpValidator(QtCore.QRegExp("[0-9a-fA-F]{1,4}"))
    ledt.setValidator( val )
    # Use a dummy (invisible) checkbox to get things to line up...
    lblw = QtWidgets.QWidget()
    wlay = QtWidgets.QHBoxLayout()
    wlay.setContentsMargins(0,0,0,0)
    if not isinstance(checker, LineEditChecker):
      chk = LineEditChecker( self, checked=checked )
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

if __name__ == "__main__":

  app = QtWidgets.QApplication(sys.argv)

  window = QtWidgets.QWidget()
  f = FixedPdoForm(None)
  l = []
  e = PdoElement("TimestampHi", 0x1100, 4)
  e.help = "Timestamp received by EVR via\n" + \
           "dedicated events 0x70/0x71/0x7c/0x7c"
  print(e)
  l.append(e)
  e = PdoElement("TimestampLo", 0x1101, 4)
  e.help = "Timestamp received by EVR via\n" + \
           "dedicated events 0x70/0x71/0x7c/0x7c"
  l.append(e)
  g = PdoElementGroup( l, False )
  f.addGroup( g )
  f.addGroup( PdoElement("EventSet", 0x1102, 4, 4) )

  window.setLayout( f.topLayout )
  window.show()
  app.exec()
