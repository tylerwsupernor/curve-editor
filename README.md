# curve-editor

A curve editor for plugdata, written in Lua with pdlua. Place points, drag them around, bend segments between them. Think Serum's LFOs, but living inside your plugdata patch. The editor sends the finished curve out as 257 numbers you can pipe straight into a Pd array, so one shape can drive an LFO, a waveshaper, an envelope, or anything you're building that needs a curve.

Plugdata doesn't have anything like this as a stock object. 'curve-editor' is designed to be a reusable building block: copy two files next to your patch, wire the inlets and outlets, and it slots in like any other Pd object.

Status: version 1.1.2. Dragging, bending, double-click add and remove, live output while dragging, snap, grid with adjustable subdivision, and saving through `[daw_storage]` all work, verified in standalone and in plugin mode (tested in Ableton Live 12 on Mac). 

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

The grid draws at 0.6 opacity. Grid opacity and color are set in `curve-editor.pd_lua` — edit the file to match your patch.

The curve leaves the left outlet as one list of 257 numbers between 0 and 1. Scale them where you use them. The right outlet sends the raw state as `x y bend` triples, and a message box holding that same format works as a preset. Both examples include one. Right-click the object and select "Help" to reveal the built-in guide.

## Current limitations

- plugdata standalone does not restore the saved shape on reopen. Saving and restoring the curve shape works in DAWs/presets when in plugin mode.
- Snap, grid toggle, and grid subdivision all reset to defaults on every open. None are saved with the shape.
- The editor has no Shift-to-snap function (like in Serum) because plugdata never passes modifier keys to pdlua mouse handlers. A host patch can fake it though with `[key]` and `[keyup]` sending `snap 1` and `snap 0` to the inlet if desired.
- Fixed at 300x300, no size message.
- Two closely-spaced dots are only grabbable from their outer edges to prevent sticking.

The curve segment math is adapted from Nasko's N-Curve Comp.

A note on how this was made: I built this with a lot of help from an AI assistant. If that's not your thing, no hard feelings — it's an easy skip.
