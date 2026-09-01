# Tutorial: build a waveshaper with curve-editor

What we're building: a patch that plays a 110 Hz sine and redraws its waveform live from the curve. Drag the curve, the timbre changes. The finished version of this exact patch is `examples/waveshaper.pd`, so open it any time to compare. The order matters on a first open. In a fresh plugdata session, open a patch from `src` first so the object loads before the example asks for it.

This assumes the two files from the README install (`curve-editor.pd_lua` and `curve-editor-help.pd`) sit in the same folder as the patch you're about to make.

## 1. The patch and the array

1. Save a new empty patch in that folder.
2. Put an array in it: Put menu, then Array. Name it `shape`, size 257 points. Leave the other settings alone.
3. Why 257: the editor draws the curve as 256 steps across the width, plus one extra that repeats the last value, so the shape loops without a click at the seam.

Array names are shared across every open patch in the session. If something else already uses `shape`, pick another name. The examples use long names like `curve-editor-shape` for exactly this reason.

## 2. The control side

Create four objects. In plugdata that's the Put menu, then Object, or the Object tool in the toolbar.

- `[loadbang]`
- `[curve-editor]`
- `[array set shape]`
- `[daw_storage shaper]`

The word `shaper` after `daw_storage` is just an id, any word works.

Wire them like this:

1. `[loadbang]` outlet to `[curve-editor]`'s inlet. This makes the curve appear the moment the patch opens.
2. `[curve-editor]`'s left outlet to `[array set shape]`. Every time the curve changes, all 257 numbers get poured into the array.
3. `[curve-editor]`'s right outlet to `[daw_storage shaper]`. The right outlet carries the raw state, and `daw_storage` remembers it when the patch or DAW project is saved.
4. `[daw_storage shaper]`'s outlet to `[curve-editor]`'s inlet. On reopen, `daw_storage` replays the saved state here, so the shape comes back.

Those are the same three cords from the help patch, plus the loadbang.

## 3. The signal side

Create these eight objects, top to bottom, and connect each one's outlet to the next one's left inlet.

```
[osc~ 110]
[+~ 1]
[*~ 128]
[tabread4~ shape]
[-~ 0.5]
[*~ 2]
[*~ 0.5]
[dac~]
```

What each one is for:

1. `[osc~ 110]` makes the test tone, a sine swinging between -1 and 1.
2. `[+~ 1]` slides that swing up to 0 to 2, because array positions can't be negative.
3. `[*~ 128]` turns 0 to 2 into 0 to 256. Those are positions in the array.
4. `[tabread4~ shape]` reads the curve at that position and outputs its height, which sits between 0 and 1. This is the box where the sine becomes the curve.
5. `[-~ 0.5]` and `[*~ 2]` slide and stretch 0 to 1 back down to -1 to 1, the range a speaker wants.
6. `[*~ 0.5]` keeps the volume polite.
7. `[dac~]` is the output.

## 4. Try it

1. Turn your system volume down first.
2. Turn audio on in plugdata if it isn't already.
3. Press Cmd+E to enter run mode.
4. Drag the curve around. The tone follows it live. Bending the middle of the curve hard makes obvious distortion, and a flat middle squashes the note small.

The curve is the waveshaper. Nothing else in the patch edits the sound.

## 5. The values, spelled out

- The curve travels through the patch as 257 numbers between 0 and 1. Position 0 in the array is the curve at x=0, position 256 is the curve at x=1.
- The reading side is one mapping: signal value in, table position out. Signal plus 1, times 128. A signal at -1 reads the left edge of the curve, a signal at 1 reads the right edge.
- The writing side is the reverse: the curve height comes out between 0 and 1, and gets recentered to -1 to 1 before it hits the speaker.
- The same 0-to-1 output scales to anything. Multiply by 500 for a frequency range of 0 to 500 Hz. Use it as-is for amplitude. Route it anywhere a 0-to-1 number makes sense.

## 6. Saving and the extras

- Saving goes through `[daw_storage]`, which is already wired. It works when the patch runs as a plugin, tested in Ableton Live. plugdata standalone does not restore the shape on reopen, that's a known limit.
- A `snap 1` message into `[curve-editor]`'s inlet turns on a 1/10 grid for points and clicks and halves bend speed. `snap 0` turns it off. Snap starts off every time the patch opens.
- A preset is a message box holding the state in `x y bend` triples. The preset box in `examples/waveshaper.pd` holds `0 0 0.75 0.5 0.5 0.75 1 1`: three points, each with an x and a y, and a bend value after each point except the last one. A state saved by the editor has one more number at the end, the bipolar flag: 1 shows the center crosshair, 0 hides it.

## Next

The LFO in `examples/lfo.pd` is the same idea pointed at time instead of signal. A `[phasor~]` sweeps through the array over and over, and the curve becomes a repeating envelope. Open it and compare the two reading chains.
