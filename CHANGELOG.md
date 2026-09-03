# Changelog

## 1.1.6

Bug fix: a few small defects in the help patch, none of them in the object itself. The base clear button had a doubled cord and the last doc line still taught the dead blend formula.

## 1.1.5

Base/Your Curve/Results compositing. `base <list>` on the first inlet loads a Base curve, `base clear` takes it off. With a Base loaded the output becomes Results(x) = Your Curve(Base(x)): the Base warps where along Your Curve each x lands, so a flat line reads flat, an untouched diagonal gives the Base exactly, and a preset gets bent, not redrawn. Until a base loads, Results is just Your Curve, so existing patches behave as before. Outlet 1 outputs Results, outlet 2 still saves Your Curve only. The test patch got `base clear` and three test-shape buttons to check the composite.

## 1.1.4

Bipolar display. `bipolar 1` keeps the grid as it is and draws a bolder crosshair through the center, `bipolar 0` takes it off. It starts off, and `grid 0` hides it with the rest of the grid. Unlike snap and the grid, it saves with the shape. The state list ends with one extra number for it now, and the loader still reads the older lists without it. Help patch and test patch got the buttons.

## 1.1.3

Bug fix: a short or malformed list into the first inlet could leave a partial curve behind. The loader now checks the whole list first. A wrong atom count or a non-number gets refused with one console line and the current curve stays standing. Out-of-range x and y values are clamped into 0-1, with a note on the console. Normal loads behave exactly as before, no new messages, no saved-format change.

## 1.1.2

Help patch rebuild: every control is now a clickable button, grouped to match the test patch, the doc text is shortened for readability, and the four gestures are captioned next to the output graph they describe.

## 1.1.1

The grid density is settable. `gridsub N` on the first inlet sets the drawn divisions and the snap step together, so the ruler and the clicks agree at any density. `gridup` / `griddown` step it one per press for patch buttons, with a floor of 1 (frame only) and a ceiling of 50. `grid 0` is still the full off and the two stay independent. Density starts at 16 on every open, not saved, just like snap and the grid toggle. The grid lines are at 0.6 opacity now, so they read a bit thinner and quieter overall. Also fixed: three double-click bugs that could leave stuck or unremovable dots, found during testing.

## 1.1

The editor has a 10x10 grid shown behind the curve, it acts as the visual reference for the snap points. It's shown on every open and `grid 1` / `grid 0` messages toggle it. Snap still starts off initially, so the two act independently from one another. The draw colors moved into one labeled block, so recoloring a copy for a host patch's palette means editing that block.

## 1.0.1

The editor is square now, 300x300 instead of 300x200, so the default diagonal is a true 45 degree line. Help patch and examples relaid out to fit.

## 1.0.0

First release. Curve editor object for plugdata: drag anchors, bend segments, double-click to add or remove points, snap messages, 257-value curve output, saving through daw_storage. Ships with a help patch, two examples, and a build tutorial.
