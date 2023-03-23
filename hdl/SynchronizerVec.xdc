# SCOPE_TO_REF SynchronizerVec

set_max_delay -datapath_only -from [get_clocks -of_object [get_ports clkA]] -through [get_pins -of_objects [get_cells datA_reg*] -filter {REF_PIN_NAME==Q}] [get_property PERIOD [get_clocks -of_objects [get_ports clkB]]]
set_max_delay -datapath_only -from [get_clocks -of_object [get_ports clkB]] -through [get_pins -of_objects [get_cells datB_reg*] -filter {REF_PIN_NAME==Q}] [get_property PERIOD [get_clocks -of_objects [get_ports clkA]]]
