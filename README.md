# curve-editor

A curve editor for plugdata, written in Lua with pdlua. Place points, drag them around, bend segments between them. Think Serum's LFOs, but living inside your plugdata patch. The editor sends the finished curve out as a list you can pipe straight into a Pd array, so one shape can drive an LFO, a waveshaper, an envelope, or anything you're building that needs a curve.

Plugdata doesn't have anything like this as a stock object. 'curve-editor' is a reusable building block. Copy two files next to your patch, wire the inlets and outlets, and it slots in like any other Pd object.

Dragging, bending, double-click add and remove, live output while dragging, snap, grid with adjustable subdivision, opt-in full-range waveshaping, and saving through `[daw_storage]` all work. The legacy 0..1 editor stays the default, so existing envelope, LFO, and curve patches keep their original behavior.

What ships: the object, a right-click help patch with every control as a clickable button, a self-test patch (`src/curve-editor-test.pd`), two example patches, and a step-by-step tutorial in [docs/tutorial.md](docs/tutorial.md).

## Install

1. Copy `curve-editor.pd_lua` and `curve-editor-help.pd` from `src` into the same folder your patch lives in. It has to be the same folder, not a subfolder, and keep the two files together. Pd finds the object next to the patch, and the help patch is what right-clicking and selecting "Help" opens.
2. Create `[curve-editor]` in your patch.
3. Wire three cords, the same way the help patch and the examples do:
   - left outlet to `[array set <array name>]` to fill an array with the curve
   - right outlet to `[daw_storage <any id>]` so the shape saves with the patch
   - the `[daw_storage]` outlet back to `[curve-editor]`'s inlet so the saved shape comes back when the patch opens (this restore works in plugin mode; see limitations for the standalone caveat)
4. Optional: `[loadbang]` into the inlet so the curve appears right when the patch opens.

## Using it

On the patch canvas, Cmd+E (Ctrl+E on Windows/Linux) switches between edit and run mode, and shaping the curve *needs* to be done in run mode. In presentation or plugin view the curve editor is always operable. Drag a dot to move it, drag on the line between two dots to bend the curve, double-click empty space to add a dot, and double-click a dot to remove it. The two end dots are fixed to their respective sides.

Snap is off by default. `snap 1` on the inlet turns on a grid for point placement only (not visible) and halves bend speed, `snap 0` turns it back off.

The editor displays a grid behind the curve as a visual reference on open by default. `grid 1` / `grid 0` hide and show it. Grid and snap are independent from one another.

Grid subdivision is 16 by default. `gridsub N` sets the number of subdivisions and the snap step together manually, `gridup` / `griddown` add or remove steps one at a time when clicked.

Bipolar display starts off in the legacy editor. `bipolar 1` keeps the grid as it is and draws a bolder crosshair through the center, `bipolar 0` takes the crosshair back off. It's part of the grid, so `grid 0` hides it too.

`[curve-editor fullrange]` opts into the waveshaping editor at creation. `fullrange 1` converts an existing instance at runtime, and `fullrange 0` returns it to the legacy editor. In full range, both axes cover -1..+1 and the output grows to 513 normalized samples: 256 below zero, the exact zero sample, and 256 above it. Normalized output values still run from 0 to 1, where 0, 0.5, and 1 represent -1, 0, and +1.

Full-range editing starts symmetric. `bipolar 0` keeps only the top-right quadrant editable and shows the origin-reflected negative half as a dim ghost. The point at zero input stays fixed horizontally but can move upward, with its ghost endpoint moving equally downward. `bipolar 1` releases that point in both directions and makes the complete graph independently editable. Switching back to `bipolar 0` intentionally discards negative-side edits and rebuilds them from the positive side. Returning to the legacy editor uses the current positive half.

`size W H` resizes a full-range editor instance in pixels. A single `size N` value makes it square. The default remains 300x300, and the chosen full-range size is saved with the curve.

The grid draws at 0.6 opacity. Grid opacity and color are set in `curve-editor.pd_lua`, edit the file to match your patch. The crosshair gets its own color entry in the same block.

The legacy curve leaves the left outlet as 257 numbers between 0 and 1. Full-range mode sends 513. The right outlet sends the raw state for `[daw_storage]`. Legacy state keeps the old `x y bend` format and trailing display flag. Full-range state starts with the numeric header `-271828 2 1`, followed by the bipolar mode, width, height, and the complete curve as `x y bend` data. The header explicitly marks state version 2 and the full-range coordinate model while keeping the whole message safe for ordinary Pd list storage.

## Current limitations

- plugdata standalone does not restore the saved shape on reopen. Saving and restoring the curve shape works in DAWs/presets when in plugin mode.
- Snap, grid toggle, and grid subdivision reset to defaults on every open. Full-range mode, bipolar mode, and full-range size save with the shape through the state list, so they come back wherever the curve does.
- The editor has no Shift-to-snap function (like in Serum) because plugdata never passes modifier keys to pdlua mouse handlers. A host patch can fake it though with `[key]` and `[keyup]` sending `snap 1` and `snap 0` to the inlet if you want.
- Two closely-spaced dots are only grabbable from their outer edges to prevent sticking.

The curve segment math is adapted from Nasko's N-Curve Comp.

A note on how this was made: I built this with a lot of help from an AI assistant. If that's not your thing, no hard feelings.
