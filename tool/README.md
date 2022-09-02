# Tool for Creating or Modifying ESI File for the EtherCAT-EVR

  Till Straumann, PSI, 2021-2022

This tool helps the user with editing ESI files. While some
information (such as the vendor ID and low-level PDI configuration
data) is hard-coded several settings can be dynamically changed
in the GUI:

 - EoE Networking parameters
 - Default settings for (some) EVR triggers
 - TxPDO layout

The ESI file is saved as XML but the tool can also generate
(binary) EEPROM images (sii files).

Note that this is not a generic ESI tool but somewhat taylored
for the EtherCAT-EVR device.

## Prerequisites
The tool requires `python-3`, `PyQt5` and `lxml`.

## Startup
The tool may be started with a XML file-name argument or without any
arguments (in which case a new XML file will be generated from scratch).

If an existing file is opened and the `EtherCATInfo.xsd` (and dependent)
schema file(s) are present then the file is validated against the schema.

## Using the Tool
The following subsections describe the editable features.

### EoE Networking Settings
The MAC- and IP4 addresses can be defined here. While it is in most cases
fine to leave the MAC-address undefined (all-ones or all-zeroes) because
the firmware uses a semi-randomized MAC-address by default it is convenient
to define the IP4 address in the ESI-file/EEPROM.

The IP4 address may also be set/changed at run-time via the EoE protocol
but this requires an EtherCAT master which supports setting IP parameters
and it must be performed after every restart of the EtherCAT-EVR.

Note that the addresses defined in the tool and uploaded into the EEPROM
are just defaults. They may always be changed via EoE at run-time.

### EVR Default Settings
Default values for pulse-generators that are affecting the operation of
the EtherCAT EVR may be defined here. Note that these settings may be
modified at run-time via EoE but it may be convenient to have suitable
default values after startup because some applications may then not need
any EoE at all.

#### TxPDO Trigger
Sending of the TxPDO is triggered by an EVR pulse-generator and the
(default) event-code and delay of this trigger pulse are defined here.
The delay is measured in EVR-clock ticks.

The special event code `0` does not use a pulse-generator but detects
the arrival of the EVR's distributed data buffer.

#### LATCH0 Events
The EtherCAT-EVR hardware/firmware latches the EtherCAT DC timestamp
when the LATCH0 signal (in firmware) is asserted and deasserted, respectively.
The firmware asserts and deasserts this signal when specific EVR-events 
occur. The default event codes are defined in the GUI. Note that two
appropriate event codes should be used to make sure LATCH0 is asserted
and deasserted periodically in a meaningful sequence.

For generating the LATCH events the special event code `0` may also
be used (see TxPDO Trigger).

### TxPDO Layout
Many details of the TxPDO image can be defined by the tool. Note that
the TxPDO layout consists of two main parts:

 - *standard* part
 - user-definable part

#### Standart TxPDO Part
The standard part consists of a number of predefined items:

 - EVR-Timestamp
 - Set of Events
 - DC-timestamps of LATCH0 and LATCH1 assertion/deassertion, respectively

While these items are predefined the user may still decide (for each of
these items) whether to include them with the TxPDO or omit them. The
user may also assign arbitrary EtherCAT/CoE index numbers to these items.

The EVR timestamp consists of two 32-bit words which depend on the reception
of the 'special' `0x70`, `0x71`, `0x7c` and `0x7d` event codes (see EVR documentation).
The high-resolution part of this timestamp is by default clocked by the EVR clock
and reset by the `0x7d` event. Note that the EVR timestamp is *not* a timestamp
extracted from the EVR distributed-data buffer.

The Set of Events is an array of eight 32-bit words with each bit in this
array representing an event-code. A bit is asserted if the associated event-code
has been received since the last TxPDO was sent.
The individual words in the array are assigned EtherCAT/CoE consecutive subindices
starting with 1 while using the same (user-defined) index number.

#### EVR Data-Buffer PDO Mappings
In the user-defined TxPDO part the user may map arbitrary segments of the EVR
distributed-data buffer into the TxPDO.

The (user-defined part of the) TxPDO is represented by a table with four columns.
Each cell in this column represents one byte (i.e.,  PDO items must be aligned with
byte-boundaries and have a length of multiple bytes). The table has four columns
because segments of the EVR buffer are mapped in multiples of 32-bit words.

##### Segments and PDO Items
A *segment* is a (consecutive) region in the EVR data-buffer. Multiple segments may
be mapped into the TxPDO and they may cover entirely different but also overlapping
regions in the EVR buffer. Segments always cover multiples of 4-byte words. Byte-swapping
is supported for segments and is always performed at the segment level. If there
are some items that require byte-swapping and others that dont then different segments
should be defined for these items.

Segments are packed along the vertical axis in the table. Note that you need
to have available space in a segment before you may define PDO items (create
segments from the table-left-edge context menu; if the table is empty then
this menu can be brought up anywhere in the table).

The ordering of segments along the vertical axis may be changed by selecting
`Edit Segment` from the context menu (right mouse button on the left edge of the table).

Once segments are defined *PDO Items* can be defined. PDO items are contiguous
areas in the PDO that have a defined length and can be assigned a name, data-type
and EtherCAT/CoE index number.

Create, edit or delete items from the context menu in the main area of the table.
Note that items are always contiguous. If you need holes between items (e.g., because
segments are always multiples of 4-bytes) then you may define 'padding' items
by assigning them index number zero.

Arrays of items are supported. Their elements share the common name, index
and datatype but use separate sub-indices. Note that arrays cover a contiguous
area in the PDO.

The GUI supports drag-and-drop for PDO items which facilitates rearranging them
(but of course you always must make sure the items cover the intended place
in the intended segment(s)).

Note that PDO items, their names, data types, index- and sub-index numbers are
simply a kind of 'meta-information' that can be used by the EtherCAT master
and application-developer. The EtherCAT-EVR firmware does not interpret this
information in any way. It just transfers the defined segments of the EVR data
buffer via EtherCAT without any knowledge of their contents.

##### Example
Suppose the EVR data-buffer at your facility features a 64-bit pulse-ID and
4 bytes of auxiliary flags which shall be published on EtherCAT while
the rest of the data-buffer shall not be relevant. The aux-flags are at
offset `0x22` in the data buffer whereas the pulse-ID is encountered at
offset `0x40` in the data buffer. The timing system is originally VME based
and the pulse-ID is represented as big-endian.

We decide to ship the pulse-ID first in the TxPDO, followed by the flags.

We start out by defining a segment that covers the pulse-ID:

  - right-click on empty table to `Create Segment`
  - Assign a name (e.g., 'PulseID'), the correct byte offset into the
    data buffer: `0040` the number of (32-bit) words: `2` and byte-swapping
    of `8-bytes` (EtherCAT is little-endian but our data-buffer supposedly
    uses big-endian layout)
  - click `OK`

Now two new rows were created and we may assign a PDO item representing
the PulseID:

  - right-click into an empty byte-cell and select `New PDO Item`
  - Assign a name: `PulseID`, an index number: e.g., `5000` and select
    `U64` for the type.
  - A new item covering the entire segment has been created. It is
    labeled by index/subindex in the table (you can see the name when
    hovering). The hyphens indicate that the item spans multiple rows
    in the table.

Note that the segment name is only for internal use by the tool. The
PDO-item name, OTOH, is potentially retrieved and used by the master.

Next we create a segment to cover the array of flags. Because the
region we need to cover is not word-aligned we need to create a segment
that starts at `0x20` and covers two words:

  - right-click on left side area of the table to `Create Segment`.
  - Assign the name: `Flags`, offset: `0x20`, number of words: `2`.
  - Click `OK`.

Two new rows have appeared. Since we want our flags to start at
offset `0x22` we first define a padding item:

  - right-click into empty table cell `New PDO Item`.
  - Assign name: `PAD`, index: 0000, type: `U16`.
  - click `OK`.

Now we are ready to define the array of four flag bytes:

  - right-click into empty table cell `New PDO Item`.
  - Assign name: `Flags`, index: 5001, number of elements: `4`, type: `U8`.
  - click `OK`.

## EEPROM Image

### Creating Image
A binary EEPROM image can be written by selecting `Write SII (EEPROM) File`
from the `File` menu (main menu bar).

### Uploading Image
The image may be written into the target EEPROM e.g., by using the IgH master
tool `ethercat` `sii_write` command. A restart/reset of the EtherCAT-EVR is
necessary for the new settings to take effect.

Note: setting the IP4 address is possible by reprogramming the EEPROM without
having to know the previous IP4 address.

## Saving XML File
The XML file can be saved from the main `File` menu.
