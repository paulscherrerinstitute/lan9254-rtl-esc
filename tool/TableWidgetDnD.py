
from PyQt5.QtCore import Qt, QPoint, QItemSelection, QItemSelectionModel
from PyQt5.QtGui import QDropEvent
from PyQt5.QtWidgets import QTableWidget, QAbstractItemView, QTableWidgetItem, QTableWidgetSelectionRange

class TableWidgetDnD(QTableWidget):

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

        self.setDragEnabled(True)
        self.setAcceptDrops(True)
        self.viewport().setAcceptDrops(True)
        self.setDragDropOverwriteMode(False)
        self.setDropIndicatorShown(True)

        self.setSelectionMode(QAbstractItemView.ContiguousSelection)
        self.setSelectionBehavior(QAbstractItemView.SelectItems)
        self.setDragDropMode(QAbstractItemView.InternalMove)
#        self.selectionModel().selectionChanged.connect( self.on_selection_changed )
        self._verifySelection = True

    def moveItems(self, drop_row, drop_col, top_row, top_col, bot_row, bot_col):
      print("moveItems (base class) -- should be overridden")
      pass # to be implemented by subclass

    def dropEvent(self, event: QDropEvent):
        if not event.isAccepted() and event.source() == self:
            drop_row, drop_col = self.drop_on(event)
            print("Drop row/col {}/{}".format(drop_row, drop_col))

            move = []
            rngs = self.selectedRanges()
            for r in rngs:
              rw = r.topRow()
              cl = r.leftColumn()
              if r.bottomRow() != rw or r.rightColumn() != cl:
                raise RuntimeError("selected ranges should be individual elements")
              move.append( (rw, cl) )
            if ( 0 == len(move) ):
              return self.bail( event )
            move.sort( key = lambda tup: tup[0] )

            self.moveItems( drop_row, drop_col, move[0][0], move[0][1], move[-1][0], move[-1][1] )

            if False:
              nrows = move[-1][0] - move[0][0] + 1
              print("{} rows selected @{}.{}".format(nrows, move[0][0], move[0][1]))
              itpl = int(self.columnCount()/span)
              if (drop_row < move[0][0]) or (drop_row == move[0][0] and drop_col <= move[0][1]):
                for i in range(drop_row, move[-1][0] + 1):
                  if (span != self.columnSpan( i, 0 )):
                    print("Alignment mismatch (row {})".format(i))
                    return self.bail(event)
                i   = drop_row
                j   = drop_col
                pos = [] 
                print(i,j,move[0][0], move[0][1])
                while ( i != move[0][0] or j != move[0][1] ):
                  if ( self.cellWidget(i,j) is None ):
                    print("No widget @ {}.{}".format(i,j))
                  pos.append( ( i, j, self.cellWidget(i,j).clone() ) )
                  j += 1
                  if 0 == j % itpl:
                    i += 1
                    j  = 0
                  print(i,j,move[0][0], move[0][1])
                rep  = move + pos
                dsti = drop_row
                dstj = drop_col
              else:
                for i in range(move[0][0], drop_row + move[-1][0] - move[0][0] + 1):
                  if (span != self.columnSpan( i, 0 )):
                    print("Alignment mismatch (row {})".format(i))
                    return self.bail(event)
                idx = move[-1][0] * itpl + move[-1][1] + 1
                pre = []
                for k in range(idx, drop_row * itpl + drop_col + len(move)):
                  i = int(k / itpl)
                  j = k % itpl
                  print("adding pre ", i,j)
                  pre.append( (i, j, self.cellWidget(i,j).clone()) )
                rep  = pre + move
                dsti = move[0][0]
                dstj = move[0][1]
              print("Replacing ", len(rep))
              for it in rep:
                print("Setting ",dsti,dstj,it[2].text())
                self.setCellWidget( dsti, dstj, it[2] )
                dstj += 1
                if dstj == itpl:
                  dsti += 1
                  dstj = 0
              lst = drop_row * itpl + drop_col + len(move) - 1
              self.doSelect( drop_row, drop_col, int(lst / itpl), lst % itpl )

            if ( False ):
              for row_index in reversed(rows):
                  print("actually removing row")
                  self.removeRow(row_index)
                  if row_index < drop_row:
                      drop_row -= 1
  
              for row_index, data in enumerate(rows_to_move):
                  row_index += drop_row
                  self.insertRow(row_index)
                  for column_index, column_data in enumerate(data):
                      self.setCellWidget(row_index, column_index, column_data)
              event.accept()
              for row_index in range(len(rows_to_move)):
                  self.item(drop_row + row_index, 0).setSelected(True)
                  self.item(drop_row + row_index, 1).setSelected(True)
        super().dropEvent(event)

    def bail(self, event):
      super().dropEvent(event)

    def drop_on(self, event):
        index = self.indexAt(event.pos())
        if not index.isValid():
            ro = self.rowCount()
            cl = self.columnCount()
        else:
            ro = index.row()    + 1 if self.is_below(event.pos(), index) else index.row()
            cl = index.column() + 1 if self.is_right(event.pos(), index) else index.column()
        return ro,cl

    def is_below(self, pos, index):
        rect = self.visualRect(index)
        margin = 2
        if pos.y() - rect.top() < margin:
            return False
        elif rect.bottom() - pos.y() < margin:
            return True
        # noinspection PyTypeChecker
        return rect.contains(pos, True) and not (int(self.model().flags(index)) & Qt.ItemIsDropEnabled) and pos.y() >= rect.center().y()
    def is_right(self, pos, index):
        rect = self.visualRect(index)
        margin = 2
        if pos.x() - rect.left() < margin:
            return False
        elif rect.right() - pos.x() < margin:
            return True
        # noinspection PyTypeChecker
        return rect.contains(pos, True) and not (int(self.model().flags(index)) & Qt.ItemIsDropEnabled) and pos.x() >= rect.center().x()

    def verifySelection(self, val = None):
      rv = self._verifySelection
      if not val is None:
        self._verifySelection = val
      return rv

    def on_selection_changed(self, a, b):
      if not self.verifySelection():
        return
      maxr = -1
      minr = 1000000000000000
      maxc = -1
      minc = 1000000000000000
      
      print("SELCH", type(self))
      for it in self.selectedIndexes():
         r = it.row()
         c = it.column()
         print("checking {}/{}".format(r,c))
         if ( r < minr ):
           minr = r
           minc = c
         elif ( r == minr and c < minc ):
           minc = c
         if ( r > maxr ):
           maxr = r
           maxc = c
         elif ( r == maxr and c > maxc ):
           maxc = c
      print("TL {}/{}".format(minr,minc))
      print("BR {}/{}".format(maxr,maxc))
      if ( maxc >= 0 ):
        self.doSelect(minr, minc, maxr, maxc)

    def doSelect(self, minr, minc, maxr, maxc):
      wasEnabled = self.verifySelection( False )
      self.setCurrentCell( minr, minc, QItemSelectionModel.Clear )
      self.setCurrentCell( minr, minc, QItemSelectionModel.SelectCurrent )
      print("doSelect ", minr, minc, maxr, maxc)
      if True:
        for r in range(minr, maxr + 1):
          if r == minr:
            f = minc
          else:
            f = 0
          if r == maxr:
            t = maxc + 1
          else:
            t = self.columnCount()
          while f < t:
             print("Adding {}/{}".format(r,f))
             self.setRangeSelected( QTableWidgetSelectionRange(r,f,r,f), True )
             f += self.columnSpan(r, f)
             if f >= self.columnCount():
               f  = 0
               r += 1
      self.verifySelection( wasEnabled )
