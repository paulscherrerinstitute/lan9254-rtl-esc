#!/usr/bin/env python3
if __name__ == "__main__":

  from   PyQt5        import QtCore,QtGui,QtWidgets
  import sys
  from   lxml         import etree as ET
  import getopt
  from   ToolCore     import ESI
  from   GuiAdapter   import ESIAdapter
  import io

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

  ( opts, args ) = getopt.getopt( sys.argv[1:], "h", ["help"] )

  for opt in opts:
    if opt[0] in ('-h', '--help'):
      print("Usage: {} [esi-xml-file]".format( sys.argv[0] ))
      print("  Tool to generate and/or edit XML ESI file for EtherCAT EVR")
      print("  Provide a file name to edit existing file; w/o file name a new")
      print("  XML can be generated from scratch.")
      sys.exit(0)

  et     = None
  fn     = None
  schema = None

  if ( len(args) > 0 ):
    try:
      fn       = args[0]
      try:
        schema = ET.XMLSchema( ET.parse( io.open( sys.path[0] + '/EtherCATInfo.xsd','r' ) ) )
      except Exception as e:
        print("Warning: unable to process 'EtherCATInfo.xsd' or 'EtherCATBase.xsd' schema -- skipping XML schema verification")

      parser   = ET.XMLParser( remove_blank_text = True, schema = schema)
      et       = ET.parse( fn, parser ).getroot()
    except Exception as e:
      print( "Error: " + str(e) )
      sys.exit(1)

  esi        = ESI( et )
  guiAdapter = ESIAdapter( esi, fn )
  window     = guiAdapter.makeGui()
  window.show()
  app.exec()
