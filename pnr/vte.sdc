# Copyright 2026 Daniel Tyukov
# SPDX-License-Identifier: Apache-2.0
#
# Constraints for the LibreLane place and route run. Supplied explicitly rather than
# letting the flow fall back to a generic SDC, because the design has two asynchronous
# clocks and a generic single clock constraint would report meaningless numbers.
#
# The pixel clock is set to the 1024x768 requirement, the most demanding mode in the
# table. The register clock is set to 50 MHz, the figure the bandwidth arithmetic in
# docs/design.md is worked at.

set ::env(CLOCK_PERIOD) 15.3846

create_clock -name clk_pix -period 15.3846 [get_ports clk_pix_i]
create_clock -name clk_reg -period 20.0000 [get_ports clk_i]

# Every path between the two domains is a gray coded FIFO pointer or a single bit through
# a two flop synchroniser, so they must not be timed against each other.
set_clock_groups -asynchronous -group [get_clocks clk_pix] -group [get_clocks clk_reg]

set_clock_uncertainty 0.25 [get_clocks clk_pix]
set_clock_uncertainty 0.25 [get_clocks clk_reg]
set_clock_transition 0.15 [get_clocks clk_pix]
set_clock_transition 0.15 [get_clocks clk_reg]

set_input_delay  0.0 -clock clk_reg [get_ports {rst_ni s_axil_* fetch_gnt_i fetch_rvalid_i fetch_rdata_i}]
set_input_delay  0.0 -clock clk_pix [get_ports {rst_pix_ni}]
set_output_delay 0.0 -clock clk_reg [get_ports {fetch_req_o fetch_addr_o frame_o underrun_o}]
set_output_delay 0.0 -clock clk_pix [get_ports {hsync_o vsync_o de_o red_o green_o blue_o}]

set_driving_cell -lib_cell sg13g2_buf_4 -pin X [all_inputs]
set_load 0.05 [all_outputs]
set_max_fanout 24 [current_design]
