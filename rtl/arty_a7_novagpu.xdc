## =============================================================================
## arty_a7_novagpu.xdc  —  NovaGPU TS 1T
## Target: Digilent Arty A7-100T (xc7a100tcsg324-1)
## =============================================================================

## ── Clock 100 MHz ─────────────────────────────────────────────
set_property PACKAGE_PIN E3      [get_ports clk]
set_property IOSTANDARD  LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]

## ── Reset — BTN0 (activo bajo) ────────────────────────────────
set_property PACKAGE_PIN C2      [get_ports rst_n]
set_property IOSTANDARD  LVCMOS33 [get_ports rst_n]

## ── LEDs LD0-LD3 ──────────────────────────────────────────────
set_property PACKAGE_PIN H5      [get_ports {led[0]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {led[0]}]

set_property PACKAGE_PIN J5      [get_ports {led[1]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {led[1]}]

set_property PACKAGE_PIN T9      [get_ports {led[2]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {led[2]}]

set_property PACKAGE_PIN T10     [get_ports {led[3]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {led[3]}]

## ── VGA — Pmod JB (R/G) + Pmod JC (B/sync) ───────────────────
## Pmod JB pines: A14 A15 A16 A17 (JB1-JB4) / B14 B15 B16 B17 (JB7-JB10)

## VGA Red [3:0] → Pmod JB superior
set_property PACKAGE_PIN E15     [get_ports {vga_r[0]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {vga_r[0]}]

set_property PACKAGE_PIN E16     [get_ports {vga_r[1]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {vga_r[1]}]

set_property PACKAGE_PIN D15     [get_ports {vga_r[2]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {vga_r[2]}]

set_property PACKAGE_PIN C15     [get_ports {vga_r[3]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {vga_r[3]}]

## VGA Green [3:0] → Pmod JB inferior
set_property PACKAGE_PIN J17     [get_ports {vga_g[0]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {vga_g[0]}]

set_property PACKAGE_PIN J18     [get_ports {vga_g[1]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {vga_g[1]}]

set_property PACKAGE_PIN K15     [get_ports {vga_g[2]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {vga_g[2]}]

set_property PACKAGE_PIN J15     [get_ports {vga_g[3]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {vga_g[3]}]

## VGA Blue [3:0] → Pmod JC superior
set_property PACKAGE_PIN U12     [get_ports {vga_b[0]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {vga_b[0]}]

set_property PACKAGE_PIN V12     [get_ports {vga_b[1]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {vga_b[1]}]

set_property PACKAGE_PIN V10     [get_ports {vga_b[2]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {vga_b[2]}]

set_property PACKAGE_PIN V11     [get_ports {vga_b[3]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {vga_b[3]}]

## VGA HSync / VSync → Pmod JC inferior
set_property PACKAGE_PIN U14     [get_ports vga_hsync]
set_property IOSTANDARD  LVCMOS33 [get_ports vga_hsync]

set_property PACKAGE_PIN V14     [get_ports vga_vsync]
set_property IOSTANDARD  LVCMOS33 [get_ports vga_vsync]

## =============================================================================
## Timing constraints
## =============================================================================
## El clk_pixel viene del divisor RTL (25 MHz) — declarar como generated clock
create_generated_clock -name clk_pixel \
    -source [get_ports clk] \
    -divide_by 4 \
    [get_pins {u_gpu/clk}]

## Relajar timing en paths puramente de display (no críticos)
set_false_path -to [get_ports {vga_r[*] vga_g[*] vga_b[*] vga_hsync vga_vsync}]
set_false_path -to [get_ports {led[*]}]
