#!/usr/bin/env python3
import re
import sys
import getopt

ilanam=None
probsz=64
outfil=None
infil=None
prefix=None

opts, rem = getopt.getopt(sys.argv[1:],"i:s:ho:p:")
for o in opts:
  if ( o[0] == "-h" ):
    print("Usage: {} [-h] [-o <outfile>] [-s <size>] -p prefix -i <ila_name> <infile>".format(sys.argv[0]))
    print()
    print("Script to generate a Vivado ILA 'probes' file from VHDL")
    print("Requires the VHDL to assing signals to ILA probes in the")
    print("following form:")
    print()
    print("  probeX(3 downto 4) <= signalName(1 downto 0);")
    print("  probeX(6 downto 5) <= signalName;")
    print("  probeY(4)          <= signalName;")
    print("  probeZ             <= signalName;")
    print("  probeZ             <= signalName(63 downto0);")
    print()
    print("where 'X' ranges from 0-9; more complicated signal names")
    print("are copied verbatim into a commented line for the user to")
    print("fix by hand")
    print()
    print("Options:")
    print(" -h          : This message")
    print(" -i <name>   : Ila name (must match hw ila name in design)")
    print(" -s <size>   : Default probe size (probeZ example); defaults to 64")
    print(" -o <name>   : Output file name (stdout by default)")
    print(" -p <pref>   : Prefix for the probe name; probes must be unique across")
    print("               all ILAs; choose an appropriate name!")
    exit(0)
  elif ( o[0] == "-i" ):
    ilanam = o[1]
  elif ( o[0] == "-o" ):
    if ( o[1] != "-" ):
      outfil = o[1]
  elif ( o[0] == "-s" ):
    probsz = int(o[1])
  elif ( o[0] == "-p" ):
    prefix = o[1]
  else:
    raise RuntimeError("Unknown Option {}".format(o[0]))

if ilanam is None:
  raise RuntimeError("Missing ILA name (must use '-i <ilaname>' option)")

if prefix is None:
  raise RuntimeError("Missing probe prefix (must use '-p <prefix>' option")

if len(rem) == 0:
  raise RuntimeError("Missing input file name (provide as cmdline arg)")
elif rem[0] == "-":
  pass
else:
  infil = rem[0]

num="([0-9]+)"
spco="[ \t]*"
spc1="[ \t]+"
rng=spco+"[(]("+spco+num+spc1+"downto )?"+spco+num+spco+"[)]"
nam="([a-zA-Z0-9_.]+)"

hdr="^"+spco+"(p(robe)?[0-9])"+"("+rng+")?"+spco+"<="+spco

okline=hdr+nam+"("+rng+")?"+spco+"[;].*"
manline=hdr+"(.*)"

okpat=re.compile(okline)
manpat=re.compile(manline)

def pr(x):
  print(x, end='')

def mkrng(l,r):
  if l is None:
    if r is None:
      return "{:d}:0".format( probsz - 1 )
    else:
      return r
  return l + ":" + r

def rnglen(l,r):
  if l is None:
    return 1
  else:
    return int(l) - int(r) + 1

def process(inf, outf):
  fnd  = 0
  mans = 0
  dups = dict()
  print("proc add_{}_probes {{ {{ ilanam {} }} }} {{".format(prefix, ilanam), file=outf)
  print(file=outf)
  for l in inf:
    mm = manpat.match(l)
    if mm is None:
      continue
    m = okpat.match(l)
    outp = [ "" ]
    expl = None
    comm = "#"
    if m is None:
      expl    = "# Unable to automatically map:"
      mans   += 1
      outp[0] = comm 
      g       = mm.groups() 
    else:
      g       = m.groups()
    probnam = g[0]
    fromnam = g[4]
    dwntonam = g[5]
    # replace '.' by '_'
    signam  = prefix + "." + g[6]
    
    outp.append( "create_hw_probe -map {{{:s}[{:s}]}}".format(probnam, mkrng(fromnam, dwntonam)) )
    if m is None:
      outp.append( signam )
    else:
      if not dups.get( signam ) is None:
        signam = g[6] + "_".join( mkrng(g[8],g[9]).split(':') )
        if not dups.get( signam ) is None:
          expl    = "# Duplicate Name - must remap manually"
          outp[0] = comm
          mans   += 1
      dups[ signam ] = signam
      l = rnglen(fromnam, dwntonam)
      if ( l > 1 ):
        outp.append("{:s}[{:d}:0]".format(signam, l-1))
      else:
        outp.append("{:s}".format(signam))
    outp.append(" [get_hw_ilas ${ila_name}]")
    if not expl is None:
      print(expl, file=outf)
    print(" ".join(outp), file=outf)
  print("}", file=outf)
  
  if ( mans > 0 ):
    print("Warning: unable to map all signals automatically; please inspect generated TCL", file=sys.stderr)

if infil is None:
  if outfil is None:
    process(sys.stdin, sys.stdout)
  else:
    with open(outfil,"w+") as f:
      process(sys.stdin, f)
else:
  with open(infil, "r") as i:
    if outfil is None:
      process(i, sys.stdout)
    else:
      with open(outfil,"w+") as g:
        process(f,g)
