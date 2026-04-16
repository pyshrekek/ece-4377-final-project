# ECE 4377 Final Project

Graphics engine written in VHDL. Displays an image on VGA monitor via the DE2-115's VGA output.

Current top-level wiring renders into an external-SRAM double framebuffer (`FRAMEBUFFER_SRAM.vhd`) and scans out the front buffer to VGA.

## Runtime controls (DE2-115)

- `SW(0)`: show/hide spheres
- `SW(1)`: show/hide cubes
- `SW(2)`: hold to zoom in
- `SW(3)`: hold to zoom out
- `SW(4)`: enable cube RGB color cycling (turning it off freezes current cycle color)
- `SW(5)`: enable sphere RGB color cycling (turning it off freezes current cycle color)
- `KEY(0..3)`: pan right/left/down/up
