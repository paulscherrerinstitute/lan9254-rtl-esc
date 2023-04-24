# EoE Client Software Support

This directory contains software for accessing firmware resources via EoE.
A simple UDP protocol is used to communicate with the firmware and access
memory-mapped registers etc.

# ECUR Library

The `ecur.h` header declares routines that implement the UDP protocol
(as implemented in `hdl/Udp2Bus.vhd`).
Note that network connectivity has to be set up first in order to be
able to communicate:

 - assign the EoE interface in the firmware an IP address. This is done at
   run-time using the ethercat software (linux ethercat master or TwinCAT ).
   The firmware may also implement a default in non-volatile memory.

 - configure the ethercat master for EoE. E.g., under linux the `eoe0s0` or
   similar interface must be set up with `ifconfig` or an equivalent method.

 - when trying to connect from a remote machine it may be necessary to
   establish appropriate IP routing.
