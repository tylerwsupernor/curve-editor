# Tutorial: build a waveshaper with curve-editor

What we're building: a patch that plays a 110 Hz sine and redraws its waveform live from the curve. Drag the curve, the timbre changes. The finished version of this exact patch is `examples/waveshaper.pd`, so open it any time to compare. The order matters on a first open. In a fresh plugdata session, open a patch from `src` first so the object loads before the example asks for it.

This assumes the two files from the README install (`curve-editor.pd_lua` and `curve-editor-help.pd`) sit in the same folder as the patch you're about to make.

## 1. The patch and the array

1. Save a new empty patch in that folder.
2. Put an array in it: Put menu, then Array. Name it `shape`, size 513 points. Leave the other settings alone.
3. Why 513: the full-range editor keeps 256 intervals on each side of zero, plus one exact center sample. The normalized array still covers 0 to 1 internally, but it represents a bipolar -1 to +1 transfer function.

Array names are shared across every open patch in the session. If something else already uses `shape`, pick another name. The examples use long names like `curve-editor-shape` for exactly this reason.

## 2. The control side

Create four objects. In plugdata that's the Put menu, then Object, or the Object tool in the toolbar.

- `[loadbang]`
- `[curve-editor fullrange]`
- `[array set shape]`
- `[daw_storage shaper]`

The word `shaper` after `daw_storage` is just an id, any word works.

Wire them like this:

1. `[loadbang]` outlet to `[curve-editor fullrange]`'s inlet. The creation argument makes this a full-range waveshaping editor, and the bang sends its initial curve to the array.
2. `[curve-editor fullrange]`'s left outlet to `[array set shape]`. Every time the curve changes, all 513 numbers get poured into the array.
3. `[curve-editor fullrange]`'s right outlet to `[daw_storage shaper]`. The right outlet carries the raw state, and `daw_storage` remembers it when the patch or DAW project is saved.
4. `[daw_storage shaper]`'s outlet to `[curve-editor fullrange]`'s inlet. On reopen, `daw_storage` replays the saved state here, so the shape comes back.

Those are the same three cords from the help patch, plus the loadbang.

## 3. The signal side

Create these eight objects, top to bottom, and connect each one's outlet to the next one's left inlet.

```
[osc~ 110]
[+~ 1]
[*~ 256]
[tabread4~ shape]
[-~ 0.5]
[*~ 2]
[*~ 0.5]
[dac~]
```

What each one is for:

1. `[osc~ 110]` makes the test tone, a sine swinging between -1 and 1.
2. `[+~ 1]` slides that swing up to 0 to 2, because array positions can't be negative.
3. `[*~ 256]` turns 0 to 2 into 0 to 512. Those are positions in the array.
4. `[tabread4~ shape]` reads the curve at that position and outputs its height, which sits between 0 and 1. This is the box where the sine becomes the curve.
5. `[-~ 0.5]` and `[*~ 2]` slide and stretch 0 to 1 back down to -1 to 1, the range a speaker wants.
6. `[*~ 0.5]` keeps the volume polite.
7. `[dac~]` is the output.

## 4. Try it

1. Turn your system volume down first.
2. Turn audio on in plugdata if it isn't already.
3. Press Cmd+E to enter run mode.
4. Drag the top-right curve around. The dim bottom-left line follows as its exact opposite-polarity mirror, and the tone follows both halves live.
5. Send `bipolar 1` to unlock the whole graph. Negative-side edits then stay independent until `bipolar 0` deliberately rebuilds that side from the positive curve.

The curve is the waveshaper. Nothing else in the patch edits the sound.

## 5. The values, spelled out

- The curve travels through the patch as 513 normalized numbers between 0 and 1. Positions 0, 256, and 512 represent bipolar coordinates -1, 0, and +1.
- The reading side is one mapping: signal value in, table position out. Signal plus 1, times 256. A signal at -1 reads the left edge of the curve, a signal at 1 reads the right edge.
- The writing side is the reverse: the curve height comes out between 0 and 1, and gets recentered to -1 to 1 before it hits the speaker.
- The same 0-to-1 output scales to anything. Multiply by 500 for a frequency range of 0 to 500 Hz. Use it as-is for amplitude. Route it anywhere a 0-to-1 number makes sense.

## 6. Saving and the extras

- Saving goes through `[daw_storage]`, which is already wired. It works when the patch runs as a plugin, tested in Ableton Live. plugdata standalone does not restore the shape on reopen, that's a known limit.
- A `snap 1` message into `[curve-editor]`'s inlet turns on a 1/10 grid for points and clicks and halves bend speed. `snap 0` turns it off. Snap starts off every time the patch opens.
- The old positive-only `x y bend` preset format still loads. In a full-range editor it becomes the positive half and gets mirrored. New saved state starts with `-271828 2 1`, then stores the bipolar mode, editor size, and complete curve.

## Next

The LFO in `examples/lfo.pd` is the same idea pointed at time instead of signal. A `[phasor~]` sweeps through the array over and over, and the curve becomes a repeating envelope. Open it and compare the two reading chains.
