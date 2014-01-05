# Automatically constrain PLL and other generated clocks
derive_pll_clocks -create_base_clocks

# Automatically calculate clock uncertainty to jitter and other effects.
derive_clock_uncertainty


# Constrain the input I/O path

set_input_delay -clock CLOCK_50 -max 12 [all_inputs]
set_input_delay -clock CLOCK_50 -min 12 [all_inputs]

# Constrain the output I/O path

set_output_delay -clock CLOCK_50 -max 12 [all_outputs]
set_output_delay -clock CLOCK_50 -min 12 [all_outputs]
