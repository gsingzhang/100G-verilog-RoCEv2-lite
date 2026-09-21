TARGET_TAP = tapdev
TARGET_TB = tb
TARGET_DPI = tb_svdpi
BUILD_DIR = work
SIMULATOR ?= VIVADO
MAIN_DIR ?= ../..
LICENCE_SERVER ?=

TARGET_TAP_PID_FILE = tapdev.pid

SIM_EXTRA_LIST = sim_extra_files.txt

VCS_INCDIR =

ifeq ($(SIMULATOR), VIVADO)
VLOG = xvlog
VHD  = xvhdl
VSIM = xsim
VDPI = xsc
VLOG_SV_OPT = -sv
VHD_STD_OPT = -2008
VOPTARGS =
VSIMCMDS = -gui -tclbatch run.tcl
else ifeq ($(SIMULATOR), QUESTA)
VLOG = vlog
VHD  = vcom
VSIM = vsim
VDPI = vlog
VLOG_SV_OPT = -sv
VHD_STD_OPT = -2008
VOPTARGS = -voptargs=+acc
VSIMCMDS = -do "run -all"
else ifeq ($(SIMULATOR), VCS)
VLOG = vlogan
VHD  = vhdlan
VSIM = ./simv
VELAB = vcs
VLOG_SV_OPT = -sverilog -timescale=1ns/1ps -kdb
VLOG_V_OPT = -sverilog -timescale=1ns/1ps -kdb
VHD_STD_OPT = -vhdl08 -kdb
VOPTARGS =
VSIMCMDS = -l simv.log
VCS_INCDIR = +incdir+$(FPGA_PROJ_DIR)/lib/RoCE/lib/Tbps_CRC/core_src
else
VLOG = vlog
VHD  = com
VSIM = vsim
VDPI = vlog
endif

VIVADO_PATH ?= /home/gxzhang/gx/gxprogram/xilinx/2025.2.1

XILINX  = $(VIVADO_PATH)/data/vhdl/src/unisims
XPM     = $(VIVADO_PATH)/data/ip/xpm/
XPM_MEM = $(VIVADO_PATH)/data/ip/xpm/xpm_memory/hdl
CC = gcc -lrt
CFLAGS = -Wall -O -lrt

# Source list: single source of truth is the synthesis filelist of the
# fpga_100g project (paths relative to FPGA_PROJ_DIR).
FPGA_PROJ_DIR = $(MAIN_DIR)/example/VCU118/fpga_100g
FPGA_MK = $(FPGA_PROJ_DIR)/fpga/Makefile
SYN_FILES := $(shell awk '/^SYN_FILES \+=/{sub(/^SYN_FILES \+= */,"");print}' $(FPGA_MK))

# fpga-only sources not needed in sim: top level, board glue, CMAC IP wrappers
FPGA_ONLY = rtl/fpga.v rtl/fpga_core.sv rtl/eth_xcvr_phy_wrapper.v \
	rtl/eth_xcvr_phy_quad_wrapper.v rtl/debounce_switch.v rtl/sync_signal.v \
	ip/cmac_gty_wrapper.v ip/cmac_gty_ch_wrapper.v ip/cmac_pad.v

SYN_SIM_FILES := $(filter-out $(FPGA_ONLY),$(SYN_FILES))

SYN_VHD := $(filter %.vhd,$(SYN_SIM_FILES))
SYN_V   := $(filter %.v,$(SYN_SIM_FILES))
SYN_SV  := $(filter %.sv,$(SYN_SIM_FILES))

EXTRA_VHD := $(shell awk -F. '$$NF=="vhd"' $(SIM_EXTRA_LIST))
EXTRA_V   := $(shell awk -F. '$$NF=="v"' $(SIM_EXTRA_LIST))
EXTRA_SV  := $(shell awk -F. '$$NF=="sv"' $(SIM_EXTRA_LIST))

all: buildtap buildsim
buildtap: tapdev
buildsim: comp

tapdev: tapdev.c
	gcc -o tapdev -Wall -O tapdev.c -pthread -lrt

dirs:
	mkdir -p $(BUILD_DIR) unisim xpm
ifeq ($(SIMULATOR), VCS)
	@printf 'WORK > DEFAULT\nDEFAULT : ./work\n' > synopsys_sim.setup
endif

xpm: dirs
ifeq ($(SIMULATOR), VCS)
	$(VHD) $(VHD_STD_OPT) -work work $(XPM)/xpm_VCOMP.vhd
	$(VLOG) -work work -sverilog -kdb $(XPM)/xpm_fifo/hdl/xpm_fifo.sv $(XPM)/xpm_cdc/hdl/xpm_cdc.sv $(XPM_MEM)/xpm_memory.sv
	$(VLOG) -work work -kdb $(XILINX)/../../../verilog/src/glbl.v
else
	$(VLOG) -work glbl $(XILINX)/../../../verilog/src/glbl.v
	$(VHD) -work work $(XPM)/xpm_VCOMP.vhd
	$(VLOG) -work work -sv $(XPM)/xpm_fifo/hdl/xpm_fifo.sv
	$(VLOG) -work work -sv $(XPM)/xpm_cdc/hdl/xpm_cdc.sv
	$(VLOG) -work work -sv $(XPM_MEM)/xpm_memory.sv
endif

hdl: dirs
	$(info Using simulator: $(SIMULATOR))
	$(if $(SYN_VHD),$(VHD) -work work $(VHD_STD_OPT) $(addprefix $(FPGA_PROJ_DIR)/,$(SYN_VHD)))
	$(if $(SYN_V),$(VLOG) -work work $(VLOG_V_OPT) $(VCS_INCDIR) $(addprefix $(FPGA_PROJ_DIR)/,$(SYN_V)))
	$(if $(SYN_SV),$(VLOG) -work work $(VLOG_SV_OPT) $(VCS_INCDIR) $(addprefix $(FPGA_PROJ_DIR)/,$(SYN_SV)))
	$(if $(EXTRA_VHD),$(VHD) -work work $(VHD_STD_OPT) $(addprefix $(MAIN_DIR)/,$(EXTRA_VHD)))
	$(if $(EXTRA_V),$(VLOG) -work work $(VLOG_V_OPT) $(VCS_INCDIR) $(addprefix $(MAIN_DIR)/,$(EXTRA_V)))
	$(if $(EXTRA_SV),$(VLOG) -work work $(VLOG_SV_OPT) $(VCS_INCDIR) $(addprefix $(MAIN_DIR)/,$(EXTRA_SV)))

comp: xpm hdl
ifeq ($(SIMULATOR), VIVADO)
	$(VDPI) $(TARGET_DPI).c
	xelab work.tb glbl.glbl -sv_lib dpi -debug typical --timescale 1ns/1ps
else ifeq ($(SIMULATOR), VCS)
	$(VELAB) -full64 -sverilog -timescale=1ns/1ps -debug_access+all -kdb -ignore initializer_driver_checks $(TARGET_DPI).c $(TARGET_TB) glbl -o simv -LDFLAGS "-lrt" -l vcs.log
else
	$(VLOG) -work work $(VLOG_SV_OPT) $(MAIN_DIR)/sim/tb.sv
endif

tap: tapdev
	sudo ./$(TARGET_TAP) tap0

sim:
ifeq ($(SIMULATOR), VIVADO)
	env "PATH=$(PATH)" "LM_LICENSE_FILE=$(LICENCE_SERVER)" $(VSIM) $(VOPTARGS) work.$(TARGET_TB)#glbl.glbl -gui
else ifeq ($(SIMULATOR), VCS)
	$(VSIM) $(VSIMCMDS)
else
	env "PATH=$(PATH)" "LM_LICENSE_FILE=$(LICENCE_SERVER)" $(VSIM) $(VOPTARGS) work.$(TARGET_TB)
endif


.PHONY: clean
clean:
	sudo rm -f *.o $(TARGET_TAP)
	sudo rm -f *.so transcript *.vcd
	sudo rm -rf $(BUILD_DIR)
	sudo rm -rf csrc simv* *.log xpm surf unisim work *.vpd *.key DVEfiles DEFAULT.DB WORK *.so output
	sudo rm -rf simv.daidir synopsys_sim.setup .vlogansetup* ucli.key
	sudo rm -rf xsim.dir *.pb *.log *.jou *.wdb .Xil glbl
