
# General configuration

set_property CONFIG_VOLTAGE 1.8                        [current_design]

#-----------------------SPI X4 模式----------------------------
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design] 
set_property CONFIG_MODE SPIx4 [current_design] 
set_property BITSTREAM.CONFIG.CONFIGRATE 51.0 [current_design] 

# 125 MHz
set_property -dict {LOC H23  IOSTANDARD LVDS} [get_ports clk_100mhz_p] ;actually 100MHz
set_property -dict {LOC H24  IOSTANDARD LVDS} [get_ports clk_100mhz_n] ;actually 100MHz
create_clock -period 10.000 -name clk_100mhz [get_ports clk_100mhz_p]



# LEDs
set_property -dict {LOC B11  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {led[0]}] ;#not connected
set_property -dict {LOC C11  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {led[1]}] ;#not connected
set_property -dict {LOC J11  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {led[2]}]
set_property -dict {LOC H12  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {led[3]}]
set_property -dict {LOC J12  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {led[4]}]
set_property -dict {LOC J13  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {led[5]}]
set_property -dict {LOC J14  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {led[6]}]
set_property -dict {LOC J15  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {led[7]}]

set_false_path -to [get_ports {led[*]}]
set_output_delay 0 [get_ports {led[*]}]

# Reset button
set_property -dict {LOC C12  IOSTANDARD LVCMOS33} [get_ports reset_n]

set_false_path -from [get_ports {reset}]
set_input_delay 0 [get_ports {reset}]

# Push buttons
set_property -dict {LOC B10  IOSTANDARD LVCMOS33} [get_ports btnu]
set_property -dict {LOC B9   IOSTANDARD LVCMOS33} [get_ports btnl]
set_property -dict {LOC D9   IOSTANDARD LVCMOS33} [get_ports btnd]
set_property -dict {LOC D10  IOSTANDARD LVCMOS33} [get_ports btnr]
set_property -dict {LOC D11  IOSTANDARD LVCMOS33} [get_ports btnc]

set_false_path -from [get_ports {btnu btnl btnd btnr btnc}]
set_input_delay 0 [get_ports {btnu btnl btnd btnr btnc}]

# DIP switches
set_property -dict {LOC E10  IOSTANDARD LVCMOS33} [get_ports {sw[0]}]
set_property -dict {LOC F9   IOSTANDARD LVCMOS33} [get_ports {sw[1]}]
set_property -dict {LOC F10  IOSTANDARD LVCMOS33} [get_ports {sw[2]}]
set_property -dict {LOC G9   IOSTANDARD LVCMOS33} [get_ports {sw[3]}]

set_false_path -from [get_ports {sw[*]}]
set_input_delay 0 [get_ports {sw[*]}]


# QSFP28 Interfaces
set_property -dict {LOC D2  } [get_ports {qsfp1_rx_p[0]}] ;
set_property -dict {LOC D1  } [get_ports {qsfp1_rx_n[0]}] ;
set_property -dict {LOC F7  } [get_ports {qsfp1_tx_p[0]}] ;
set_property -dict {LOC F6  } [get_ports {qsfp1_tx_n[0]}] ;
set_property -dict {LOC C4  } [get_ports {qsfp1_rx_p[1]}] ;
set_property -dict {LOC C3  } [get_ports {qsfp1_rx_n[1]}] ;
set_property -dict {LOC E5  } [get_ports {qsfp1_tx_p[1]}] ;
set_property -dict {LOC E4  } [get_ports {qsfp1_tx_n[1]}] ;
set_property -dict {LOC B2  } [get_ports {qsfp1_rx_p[2]}] ;
set_property -dict {LOC B1  } [get_ports {qsfp1_rx_n[2]}] ;
set_property -dict {LOC D7  } [get_ports {qsfp1_tx_p[2]}] ;
set_property -dict {LOC D6  } [get_ports {qsfp1_tx_n[2]}] ;
set_property -dict {LOC A4  } [get_ports {qsfp1_rx_p[3]}] ;
set_property -dict {LOC A3  } [get_ports {qsfp1_rx_n[3]}] ;
set_property -dict {LOC B7  } [get_ports {qsfp1_tx_p[3]}] ;
set_property -dict {LOC B6  } [get_ports {qsfp1_tx_n[3]}] ;
set_property -dict {LOC K7  } [get_ports qsfp1_mgt_refclk_0_p] ;
set_property -dict {LOC K6  } [get_ports qsfp1_mgt_refclk_0_n] ;

set_property -dict {LOC J9   IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports qsfp1_modsell]
set_property -dict {LOC A10  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports qsfp1_resetl]
set_property -dict {LOC G10  IOSTANDARD LVCMOS33 PULLUP true} [get_ports qsfp1_modprsl]
set_property -dict {LOC C9   IOSTANDARD LVCMOS33 PULLUP true} [get_ports qsfp1_intl]
set_property -dict {LOC E11  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports qsfp1_lpmode]

# 156.25 MHz MGT reference clock
create_clock -period 6.400 -name qsfp1_mgt_refclk_0 [get_ports qsfp1_mgt_refclk_0_p]

set_false_path -to [get_ports {qsfp1_modsell qsfp1_resetl qsfp1_lpmode}]
set_output_delay 0 [get_ports {qsfp1_modsell qsfp1_resetl qsfp1_lpmode}]
set_false_path -from [get_ports {qsfp1_modprsl qsfp1_intl}]
set_input_delay 0 [get_ports {qsfp1_modprsl qsfp1_intl}]


# 156.25 MHz MGT reference clock
#create_clock -period 6.400 -name qsfp2_mgt_refclk_0 [get_ports qsfp2_mgt_refclk_0_p]

set_false_path -to [get_ports {qsfp2_modsell qsfp2_resetl qsfp2_lpmode}]
set_output_delay 0 [get_ports {qsfp2_modsell qsfp2_resetl qsfp2_lpmode}]
set_false_path -from [get_ports {qsfp2_modprsl qsfp2_intl}]
set_input_delay 0 [get_ports {qsfp2_modprsl qsfp2_intl}]


