´´text
to clone the project
git clone https://github.com/nova-studios-hw/novagpu-ts1t.git

to navigate to the project or root folder
cd novagpu-ts1t

to compile everything in novagpu_sim
iverilog -o novagpu_sim sim/tb_novagpu_v12.v rtl/*.v

to run the test bench
vvp novagpu_sim
