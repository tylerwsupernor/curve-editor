# curve-editor

A curve editor for plugdata, written in Lua with pdlua. Place points, drag them around, bend segments between them. Think Serum's LFOs, but living inside your plugdata patch. The editor sends the finished curve out as a list you can pipe straight into a Pd array, so one shape can drive an LFO, a waveshaper, an envelope, or anything you're building that needs a curve.

Plugdata doesn't have anything like this as a stock object. 'curve-editor' is a reusable building block. Copy two files next to your patch, wire the inlets and outlets, and it slots in like any other Pd object.

This build adds six segment types: Tension, Linear, Square, Triangle, Sine, and Stairs. Each segment retains its controls when its type changes. Dragging, double-click add and remove, live output, snap, grid, full-range waveshaping, and `[daw_storage]` still work. Tension stays the default with the same sample values and mouse response as 1.2.1.

What ships: the object, a right-click help patch with clickable controls, a self-test patch (`src/curve-editor-test.pd`), LFO and waveshaper examples, a [two-segment controls example](examples/segment-controls.pd), and a [waveshaper tutorial](docs/tutorial.md).

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

The editor displays a grid behind the curve on open. `grid 1` shows it and `grid 0` hides it. Grid and snap are independent.

Grid subdivision is 16 by default. `gridsub N` sets the number of subdivisions and the snap step together manually, `gridup` / `griddown` add or remove steps one at a time when clicked.

Bipolar display starts off in the legacy editor. `bipolar 1` keeps the grid as it is and draws a bolder crosshair through the center, `bipolar 0` takes the crosshair back off. It's part of the grid, so `grid 0` hides it too.

`[curve-editor fullrange]` opts into the waveshaping editor at creation. `fullrange 1` converts an existing instance at runtime, and `fullrange 0` returns it to the legacy editor. In full range, both axes cover -1..+1 and the output grows to 513 normalized samples: 256 below zero, the exact zero sample, and 256 above it. Normalized output values still run from 0 to 1, where 0, 0.5, and 1 represent -1, 0, and +1.

Full-range editing starts symmetric. `bipolar 0` keeps only the top-right quadrant editable and shows the origin-reflected negative half as a dim ghost. The point at zero input stays fixed horizontally but can move upward, with its ghost endpoint moving equally downward. `bipolar 1` releases that point in both directions and makes the complete graph independently editable. Switching back to `bipolar 0` intentionally discards negative-side edits and rebuilds them from the positive side. Returning to the legacy editor uses the current positive half.

`size W H` resizes a full-range editor instance in pixels. A single `size N` value makes it square. The default remains 300x300, and the chosen full-range size is saved with the curve.

The grid draws at 0.6 opacity. Grid opacity and color are set in `curve-editor.pd_lua`, edit the file to match your patch. The crosshair gets its own color entry in the same block.

`type i tension|linear|square|triangle|sine|stairs` sets segment i's type. `bend i h` sets its active control from 0 to 1. Segments count left to right from 1; the default full-range positive segment is 2. Ghost segments reject edits, and adding or removing points renumbers later segments. Upward dragging increases h. Square and Stairs reach maximum density at 0.5; Triangle and Sine at 1. Switching types restores each type's previous bend.

The classic curve leaves the left outlet as 257 numbers between 0 and 1. Full-range mode sends 513. Both modes now save numeric v3 state on outlet 2: `-271828 3 range bipolar width height point_count`, then one nine-number record per segment and the final anchor's x and y. Every inactive control is saved too. Old unversioned and v2 states still load as Tension. The complete layout, formulas, and numbering rules are in [segment types](docs/segment-types.md).

## Current limitations

- plugdata standalone does not restore the saved shape on reopen. Saving and restoring the curve shape works in DAWs/presets when in plugin mode.
- Snap, grid toggle, and grid subdivision reset to defaults on every open. Full-range mode, bipolar mode, and full-range size save with the shape through the state list, so they come back wherever the curve does.
- The editor has no Shift-to-snap function (like in Serum) because plugdata never passes modifier keys to pdlua mouse handlers. A host patch can fake it though with `[key]` and `[keyup]` sending `snap 1` and `snap 0` to the inlet if you want.
- Two closely-spaced dots are only grabbable from their outer edges to prevent sticking.
- The drawing keeps corners, peaks, and vertical jumps even when a narrow segment exceeds the fixed table's resolution. Audio still uses the containing patch's table interpolation. These shapes approximate the reference geometry; they do not add bandlimited waveshaping.

The regression checks run from the repository root with `lua tests/curve-editor-test.lua` and `lua tests/segment-types-test.lua`. They cover state, controls, gestures, composition, geometry, drawing, and the exact 1.2.1 Tension sample baseline.

The curve segment math is adapted from Nasko's N-Curve Comp.

A note on how this was made: I built this with a lot of help from an AI assistant. If that's not your thing, no hard feelings.
