# ECE 4377 Final Project

Graphics engine written in VHDL. Displays an image on VGA monitor via the DE2-115's VGA output.

## Runtime controls (DE2-115)

- `SW(0)`: show/hide spheres
- `SW(1)`: show/hide cubes
- `SW(2)`: hold to zoom in
- `SW(3)`: hold to zoom out
- `SW(4)`: enable cube RGB color cycling
- `SW(5)`: enable sphere RGB color cycling
- `SW(16)`: continuously rotate cube clockwise
- `SW(17)`: continuously rotate cube counterclockwise
- `KEY(0..3)`: pan right/left/down/up

## Framebuffer architecture

- The design now uses a 640x480 RGB565 **double framebuffer** in external SRAM.
- VGA scans out from a front buffer while `GRAPHICS_LAYER` renders into a back buffer.
- Front-buffer reads are prioritized as scan coordinates advance; remaining cycles are used for back-buffer writes.
- Buffers swap on `vert_sync` only after a full back-buffer render completes.
- Animation phase updates are keyed off completed buffer swaps so one rendered frame uses one consistent scene state.
