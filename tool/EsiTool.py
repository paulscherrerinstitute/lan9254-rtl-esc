#!/usr/bin/env python3
if __name__ == "__main__":

  import sys
  from   lxml         import etree as ET
  import getopt
  import io
  import re

  ( opts, args ) = getopt.getopt( sys.argv[1:], "hPVf", ["help", "prom", "vhdl"] )

  isGui     = True
  overwrite = False
  mkProm    = False
  mkVhd     = False

  for opt in opts:
    if opt[0] in ('-h', '--help'):
      print("Usage: {} [-h] [-P] [esi-xml-file]".format( sys.argv[0] ))
      print("  Tool to generate and/or edit XML ESI file for EtherCAT EVR")
      print("  Provide a file name to edit existing file; w/o file name a new")
      print("  XML can be generated from scratch.")
      print("   -h   : print this message")
      print("   -P   : non-GUI mode; just generate PROM (binary) from from XML")
      print("   -V   : non-GUI mode; just generate VHDL package from from XML")
      print("   -f   : overwrite existing PROM and/or VHDL file(s)")
      sys.exit(0)
    elif opt[0] in ('-P', '--prom'):
      isGui  = False
      mkProm = True
      if ( len(args) < 1 ):
        raise RuntimeError("In -P/prom mode you must specify an XML file")
    elif opt[0] in ('-f'):
      overwrite = True
    elif opt[0] in ('-V', '--vhdl'):
      isGui = False
      mkVhd = True

  et     = None
  fnam   = None
  schema = None

  if ( len(args) > 0 ):
    try:
      fnam     = args[0]
      try:
        schema = ET.XMLSchema( ET.parse( io.open( sys.path[0] + '/EtherCATInfo.xsd','r' ) ) )
      except Exception as e:
        print("Warning: unable to process 'EtherCATInfo.xsd' or 'EtherCATBase.xsd' schema -- skipping XML schema verification")

      parser   = ET.XMLParser( remove_blank_text = True, schema = schema)
      et       = ET.parse( fnam, parser ).getroot()
    except Exception as e:
      print( "Error: " + str(e) )
      sys.exit(1)

  if ( isGui ):
    from   PyQt5        import QtCore,QtGui,QtWidgets
    from   ToolCore     import ESI
    from   GuiAdapter   import ESIAdapter

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


    esi        = ESI( et )
    guiAdapter = ESIAdapter( esi, fnam )
    window     = guiAdapter.makeGui()
    window.show()
    app.exec()
  else:
    from ESIPromGenerator import ESIPromGenerator
    prom = ESIPromGenerator( et ).makeProm()
    mode = "wb" if overwrite else "xb"
    m    = re.match("^(.*)([.][^.]*)$", fnam)
    if ( mkProm ):
      pnam = '-'
      if (not m is None):
        pnam = m.group(1) + ".sii"
      if ( '-' == pnam ):
        pnam    = sys.stdout.fileno()
        closefd = False
      else:
        closefd = True
      with io.open( pnam, mode=mode, closefd=closefd ) as f:
        f.write( prom )
    if ( mkVhd ):
      vnam = "EEPROMContentPkg.vhd"
      with io.open( vnam, mode=mode[0:1], closefd=True ) as f:
        print("library ieee;", file=f)
        print("use ieee.std_logic_1164.all;", file=f)
        print("-- AUTOMATICALLY GENERATED; DONT EDIT", file=f)
        print("package EEPROMContentPkg is", file=f)
        print("type EEPROMArray is array (natural range <>) of std_logic_vector(15 downto 0);", file=f)
        print("constant EEPROM_INIT_C : EEPROMArray := (", file=f)
        l = len(prom)
        # pad with ones; since emulation always reads in blocks of 8 bytes
        # it sometimes reads beyond the end...
        while ( ( l & 7 ) != 0 ):
          l+=1
          prom.append(255)

        for i in range(0,l-2,2):
          print("      {:d}/2 => x\"{:04x}\",".format(i, 256*prom[i+1]+prom[i]), file=f)
        i = l-2
        print("      {:d}/2 => x\"{:04x}\"".format(i, 256*prom[i+1]+prom[i]), file=f)
        print(");", file=f)
        print("end package EEPROMContentPkg;", file=f)
