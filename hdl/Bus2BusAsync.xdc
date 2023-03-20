# set SCOPE_TO_REF -> Bus2BusAsync

set_max_delay -datapath_only -from [get_clocks -of_objects [get_ports clkMst]] -through [get_nets reqMstLoc*] [get_property PERIOD [get_clocks -of_objects [get_ports clkSub]]]

set_max_delay -datapath_only -from [get_clocks -of_objects [get_ports clkSub]] -through [get_nets repSubLoc*] [get_property PERIOD [get_clocks -of_objects [get_ports clkMst]]]

