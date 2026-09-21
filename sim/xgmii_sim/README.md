# FPGA_XGMII_interactive_sim
Interactive simulation of the HDL network stack.

## ARGUMENTS
Change them as required
- `SIMULATOR`: `VIVADO`, `QUESTA` or `VCS` (might add Riviera and Xcelium)
- `MAIN_DIR`: main repo directory
- `LICENCE_SERVER`: Licence server required to run QUESTA
- `VIVADO_PATH`: VIVADO installation path, default is `/tools/Xilinx/Vivado/2022.2`
## Compile the HDL modules
The source filelist is taken from the synthesis filelist (`SYN_FILES`) of the
`example/VCU118/fpga_100g` project, plus the sim-only files listed in
`sim_extra_files.txt`.
```
make comp SIMULATOR=VIVADO VIVADO_PATH=<Your-vivado-path>
```
## Open the TAP device tapdev
```
make tapdev
make tap
```
Sudo permissions are required here, plus this is a freerunning script.
*Remember to give an IP address to the TAP device*
```
sudo ifconfig tap0 22.1.212.21 mtu 4200
```

## Run the sim
```
make sim SIMULATOR=VIVADO LICENCE_SERVER=<your-lic-server>
```
## Run the sim (VCS)
```
make comp SIMULATOR=VCS
make sim SIMULATOR=VCS
```
# VM setup
Vitrual machine(s) with SoftRocE are available in the `roce-x11` folder. *REMEBER* to bridge the tap device to the vm and give it a different IP. 
```
cd roce-x11
vagrant up
vagrant ssh softroce<1,2>
sudo ifconfig tap0 22.1.212.31 mtu 4200
```
Here you can run your application, RoCE device is labeled as `eth1_rxe` and the GID should shuld be 1.
