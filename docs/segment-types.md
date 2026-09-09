# Segment types

I added six segment types to the existing inlet. Each segment keeps its settings when its type changes. Tension remains the default, with the same bend math and mouse response as 1.2.1.

| Message | Meaning |
| --- | --- |
| `type i tension` | Smooth power bend. |
| `type i linear` | Two straight sections meeting halfway across the segment. |
| `type i square` | Alternating plateaus at the anchor heights. |
| `type i triangle` | Alternating straight ramps between the anchor heights. |
| `type i sine` | Alternating rounded transitions between the anchor heights. |
| `type i stairs` | A monotonic staircase between the anchor heights. |
| `bend i h` | The active type's normalized control position, from 0 to 1. |

`i` is a 1-based segment number, counting left to right. Segment i joins points i and i+1. The default classic editor has segment 1. The default full-range editor has negative segment 1 and positive segment 2. In symmetric mode, messages to negative ghost segments are rejected; positive edits automatically reflect. Bipolar mode allows both sides. Adding or removing points renumbers later segments.

Both messages require exactly two arguments. Unknown names, non-integer or unavailable indices, non-finite numbers, and bend values outside 0..1 are rejected without changing the curve. Type names are lowercase. Count, polarity, and alignment follow the saved bend position; there are no separate density, polarity, or stepoffset messages in this build.

## Controls and geometry

For the new types, h=0 is the bottom of the control's travel and h=1 is the top. Dragging upward increases h, including on descending and flat segments. Tension uses an adapter: h is `1 - raw bend` on rising/flat segments and `raw bend` on descending segments. This leaves the existing Tension gesture and saved bend values intact. Snap halves drag sensitivity for every type; the grid subdivision does not set segment density.

The formulas below use local position `t=(x-a.x)/(b.x-a.x)` and output `a.y+(b.y-a.y)*F(t)`. All types return the exact anchor height at t=0 and t=1. Equal-height anchors produce a flat line without losing the control setting.

| Type | Default h | Shape and range |
| --- | --- | --- |
| Tension | 0.5 | Existing Nasko power bend, softened through the midpoint Bézier. |
| Linear | 0.5 | Corner at t=0.5. Its height travels between the lower and upper anchor heights. At neutral the whole segment is straight. |
| Square | 0.5 | `c=1+round(14*d)` full cycles, where `d=1-abs(2*h-1)`. There are 2c equal-width plateaus. Below the midpoint the first plateau uses a.y; at/above it the first plateau uses b.y. Maximum is 15 cycles at the midpoint. |
| Triangle | 0 | `r=1+2*round(15*h)` ramps, from 1 to 31. `F(t)=1-abs((r*t mod 2)-1)`. |
| Sine | 0 | The same 1..31 odd half-wave count as Triangle. `F(t)=(1-cos(pi*r*t))/2`. |
| Stairs | 0.5 | `s=2+round(9*d)` rises including boundary jumps, from 2 to 11. Below the midpoint there are s-1 interior plateaus at `(j+0.5)/(s-1)`. At/above it there are s+1 plateaus at `j/s`, including endpoint levels. Plateaus have equal width within each arrangement. |

Here `round(v)=floor(v+0.5)`. Square and Stairs get sparser toward either end of the travel. At h=0, Stairs is one middle-height plateau with jumps at both anchors. At h=1 it has three plateaus at the first, middle, and last heights. At h=0.5 it has 12 levels and 11 rises. These are visual approximations of the reference shapes, with explicit count conventions rather than a shared density range.

Internal jumps return the average of their two plateau heights exactly at the boundary (within 1e-9 in local bin position). The drawing includes both limits at the same x, so jumps are vertical. Shared anchors own their exact sample. Origin reflection reverses Tension and Linear bends; the periodic control positions remain the same. The midpoint-at-jump convention preserves reflection at exact thresholds.

The 1.2.1 floor-based ownership is retained between two Tension segments, including its single early sample at an off-grid anchor. Boundaries touching another type use the actual anchor x. This keeps old all-Tension sample lists unchanged while giving new discontinuous segments explicit boundaries.

Insertion keeps the left segment's settings and starts the right segment as neutral Tension. Deletion keeps the left segment's type and periodic settings, resetting its Tension bend and Linear corner to neutral. A missing center during symmetric rebuilding or conversion back to classic mode starts a neutral segment from the origin to the first positive point.

## Saved state

New saves use numeric version 3 in both range modes:

```
-271828 3 range bipolar width height point_count
x1 y1 raw_tension type linear square triangle sine stairs
...
xN yN
```

Each point except the last starts a nine-number segment record. The final point contributes only x and y. Total length is `9*point_count`. Range is 0 for classic and 1 for full range; bipolar is 0 or 1. Type codes are stable: 0 Tension, 1 Linear, 2 Square, 3 Triangle, 4 Sine, 5 Stairs. Every record saves the inactive types' controls too. `raw_tension` is the existing curvature offset, not the adapted public h value. The other five controls are h values.

Version 3 validates the entire list before adoption: at least two points (three for symmetric full range), increasing x, exact x endpoints at 0 and 1, coordinates and controls within 0..1, known integer type codes, and integer dimensions from 80 to 2000. Classic dimensions are 300 by 300. Symmetric full-range state requires an anchor at x=0.5. Negative geometry is rebuilt from the positive side on restore.

Unversioned `x y bend` lists, their trailing display flag, and version-2 full-range lists remain loadable and become Tension segments. A legacy preset loaded into a full-range editor still migrates to a symmetric positive curve. An explicit version-3 range header restores that range, including classic into full range. The Base is converted with the editor when its range changes. A version-3 list sent through `base` is validated, but only its anchors and Tension bends supply the Base; its type controls and editor settings are ignored. Base data remains outside saved state.

## Output and display limits

The outlets are unchanged: 257 normalized samples in classic mode, 513 in full range, and numeric state on outlet 2. Without a Base, Results equals Your Curve. With a Base, composition still samples the output table at the Base's height.

Your Curve is drawn from segment geometry, including corners, peaks, and vertical jumps. Dense periodic segments use thinner strokes to keep neighboring transitions visible. Results with a Base is drawn from the composed samples. A dense shape inside a narrow segment can have more features than the fixed table can resolve. The drawing preserves the chosen density; the table samples it at its existing spacing. Audio interpolation belongs to the containing patch, so this display does not imply bandlimited waveshaping or an exact audio match to the reference.
