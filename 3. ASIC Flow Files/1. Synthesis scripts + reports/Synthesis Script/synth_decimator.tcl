# ============================================================
#      GENUS SYNTHESIS SCRIPT FOR DECIMATOR CHAIN (SCL 180nm)
# ============================================================

set design_name "Decimator_Chain_Top"
set top         $design_name

# ---------- RTL Files ----------
set verilog_files [list \
  rtl/Decimator_Chain_Top.v \
  rtl/Stage1_CIC.v \
  rtl/Stage2_HB1.v \
  rtl/Stage3_HB2.v \
  rtl/Stage4_HB3.v \
  rtl/Stage5_FIR.v
]

# ---------- SCL 180nm Libraries ----------
set libdir     "/home/students/scl180/stdcell/fs120/4M1IL/liberty/lib_flow_ff"
set target_lib "$libdir/tsl18fs120_scl_ff.lib"

set_db init_lib_search_path $libdir
set_db library $target_lib
set_db design_process_node 180

# ---------- Disable bad/unsupported cells ----------
set_dont_use [get_lib_cells */slbhb1]
set_dont_use [get_lib_cells */slbhb2]
set_dont_use [get_lib_cells */slbhb4]
set_dont_use [get_lib_cells */slchq1]
set_dont_use [get_lib_cells */slchq2]
set_dont_use [get_lib_cells */slclq1]
set_dont_use [get_lib_cells */slclq2]
set_dont_use [get_lib_cells */adiode]
set_dont_use [get_lib_cells */cload1]

# ---------- Create Directories ----------
file mkdir logs
file mkdir reports
file mkdir results

# ---------- Read RTL ----------
set_db init_hdl_search_path { ./rtl }
read_hdl $verilog_files
elaborate $top

check_design > reports/check_design.rpt

# ============================================================
#                  CLOCK & IO CONSTRAINTS
# ============================================================

create_clock -name core_clk -period 100.0 [get_ports clk]

set data_inputs [remove_from_collection [all_inputs] [get_ports {clk reset clk_enable}]]

set_input_delay 5 -clock core_clk $data_inputs
set_output_delay 5 -clock core_clk [all_outputs]

set_drive 0 $data_inputs
set_load 0.05 [all_outputs]

# ============================================================
#                  SYNTHESIS SETTINGS
# ============================================================

# These 3 are known-good in your log
set_db syn_generic_effort medium
set_db syn_map_effort    medium
set_db syn_opt_effort    medium

# NO dp_extract / dp_optimize / hdl_* attributes here
# If you want to try retiming and it errors, just comment it out:
# set_db retime true

# ============================================================
#                  RUN SYNTHESIS
# ============================================================

syn_generic
syn_map
syn_opt
# ============================================================
#                  REPORTS
# ============================================================

report_timing > reports/timing.rpt
report_area   > reports/area.rpt
report_power  > reports/power.rpt
report_qor    > reports/qor.rpt

# ============================================================
#                  OUTPUT FILES
# ============================================================

write_hdl  -mapped           > results/${design_name}_mapped.v
write_sdc                     > results/${design_name}.sdc
write_sdf -version 3.0 -design $design_name > results/${design_name}.sdf
write_design -innovus -basename results/${design_name}

exit



