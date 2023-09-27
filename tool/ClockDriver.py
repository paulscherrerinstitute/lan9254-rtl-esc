##############################################################################
##      Copyright (c) 2022#2023 by Paul Scherrer Institute, Switzerland
##      All rights reserved.
##  Authors: Till Straumann
##  License: GNU GPLv2 or later
##############################################################################

class ClockDriver(object):

  REGISTRY = dict()

  def __init__(self):
    super().__init__()

  @property
  def freqMHzLow(self):
    return 10.0

  @property
  def freqMHzHigh(self):
    return 500.0

  def acceptable(self, freqMHz):
    l = self.freqMHzLow
    h = self.freqMHzHigh
    if ( freqMHz < l or freqMHz > h ):
      raise RuntimeError("Requested frequency out of range ({:g}..{:g})".format(l,h))
    return freqMHz

  def mkInitProg(self, freqMHz):
    return bytearray()

  @property
  def name(self):
    return "Soft"

  @staticmethod
  def registerDriver( d ):
    if not isinstance(d, ClockDriver):
      raise RuntimeError("ClockDriver: can only register ClockDriver objects")
    ClockDriver.REGISTRY[ d.name ] = d

  @staticmethod
  def findDriver(name):
    return ClockDriver.REGISTRY[ name ]
