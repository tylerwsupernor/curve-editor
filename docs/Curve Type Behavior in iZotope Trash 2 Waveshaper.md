# Curve Type Behavior in iZotope Trash 2 Waveshaper

## Overview

This report examines how the "Curve Type" setting in iZotope Trash 2’s Trash module waveshaper behaves, with emphasis on the per‑segment choices (tension, linear, square, triangle, sine, and step/quantize) and how they respond to user movement of points in the graph. It synthesizes information from official documentation and detailed tutorial videos to infer the underlying mapping from input amplitude to output amplitude for each curve type and to relate this to audible results in distortion processing.[^1][^2][^3][^4]

## Waveshaper Fundamentals in Trash 2

Trash 2’s core distortion is implemented as a waveshaper that maps input sample amplitudes (x‑axis) to output sample amplitudes (y‑axis) using a user‑editable curve. The default straight diagonal line from bottom‑left to top‑right corresponds to a unity‑gain linear mapping where output amplitude equals input amplitude and no distortion is introduced beyond any base algorithm. Moving points away from this line changes how different input levels are scaled, compressed, expanded, or inverted, generating non‑linear distortion and new harmonics in the signal.[^3][^4][^5][^1]

The graph is divided into quadrants representing positive and negative input values; in symmetrical mode both sides mirror each other, while bipolar mode allows different curves for positive and negative halves of the waveform. The central horizontal/vertical crossing represents the zero‑crossing region of the signal; changing the curve around this region strongly affects higher‑frequency components, transient shape, and clickiness, while outer regions focus more on high‑amplitude portions of the waveform (e.g., low‑frequency energy like kicks and bass).[^4][^6][^7][^3]

## Segment‑Based Curve Editing

The user edits the waveshaper by adding control points (nodes) along the input‑output graph; Trash 2 then connects adjacent pairs of points using a chosen segment type, collectively referred to by iZotope as the curve type. For each pair of points, the curve type determines the interpolation function used between those points, which can be a straight line, a smoothed curve, a sequence of squares or triangles, sinusoidal segments, or stepwise quantization.[^3][^4]

In the UI, the segment type for the currently selected connection can be changed via a pop‑up or context menu: tension (curved), linear, square, triangle, sine, and a stair‑step/quantization mode. Additionally, certain modes (especially square and step) provide a density parameter that changes how many discrete shapes or steps are packed between the two points, controlled by dragging a small handle in the middle of the segment.[^4][^3]

## Linear Curve Type

### Mathematical Behavior

The linear curve type connects adjacent points with a straight line, establishing a simple affine mapping between input and output amplitude in that segment. If two points are at[^3][^4]
\[(x_1, y_1)\] and \[(x_2, y_2)\], the output \(y\) for an input \(x\) in that interval is approximately
\[y = y_1 + (y_2 - y_1) \cdot \frac{x - x_1}{x_2 - x_1}.\]
Although the exact internal implementation is proprietary, the observed behavior in tutorials corresponds to a continuous linear interpolation with no additional curvature or modulation.[^3]

### Audible Effect and Response to Movement

With linear segments, waveshaping acts like piecewise gain scaling and clipping: sections above the unity line compress peaks, sections below attenuate them, and hard horizontal segments near the top or bottom approximate soft or hard clipping. Moving a point upward along the y‑axis in the mid‑level region raises output for those input levels and adds mild harmonic content; dragging it downward attenuates that region and can introduce gated effects when the line approaches zero output.[^4][^3]

Because interpolation is straight, transitioning between points is abrupt in curvature but continuous in amplitude; there are no additional mini‑cycles or quantization artifacts between nodes. Linear segments are therefore best suited for simple compression curves, asymmetrical clipping, and precise control over amplitude mapping without extra oscillations.[^4][^3]

## Tension (Curved) Curve Type

### Mathematical Behavior

The tension curve type replaces the straight line between two points with a smooth, continuously curved function that can bulge above or below the straight line depending on a tension parameter. In the UI, tension is adjusted by a small handle that changes the local curvature while leaving the endpoints fixed, similar to a cubic spline or Bézier‑style interpolation between control points.[^3][^4]

Although iZotope does not publish the exact formula, the behavior suggests a parametric curve where the slope at each endpoint is modulated to produce either concave or convex shapes relative to the underlying linear segment. The result is a smooth, non‑piecewise transition that avoids sharp corners, distributing non‑linearity more gradually across that input range.[^4][^3]

### Audible Effect and Response to Movement

Curved tension segments produce smoother, more analog‑like distortion, as they introduce gradual changes in slope that resemble transfer curves of tape or tube devices rather than hard clipping. Increasing curvature (bulging upward) in mid‑level regions enhances saturation by boosting intermediate amplitudes and creating even and odd harmonics in a more rounded way; bulging downward compresses those amplitudes and can add subtle soft‑knee limiting.[^8][^3][^4]

Moving the tension handle changes where distortion is concentrated: tightening curvature near the zero‑crossing makes small signals more non‑linear and bright, while concentrating curvature near the extremes focuses saturation on louder parts of the signal. Because the mapping remains continuous and differentiable, tension segments avoid the abrupt gate‑like artifacts seen with square or step modes unless the curve is pushed near zero output or sharply inverted.[^7][^4]

## Square Curve Type

### Mathematical Behavior

In square mode, the segment between two points is subdivided into a sequence of rectangular “squares,” each representing a brief region of near‑constant output followed by a sudden jump to another level. Trash 2 lets the user adjust the number (density) of these squares by dragging a central handle: increasing density packs more rectangles into the same input interval, while decreasing density yields fewer, broader rectangles.[^3][^4]

Functionally, the mapping in square mode approximates a piecewise constant function: for each sub‑interval in input amplitude, output is held at a fixed value until crossing a threshold, where it steps to another value. The exact thresholds and levels are determined by the endpoints and the chosen density, but conceptually it is akin to multi‑level hard clipping.[^4][^3]

### Audible Effect and Response to Movement

Square segments create very aggressive, harmonically rich distortion, often resembling gated or “bit‑crushy” textures because many input levels collapse to a limited set of output levels. Packing more squares (higher density) maps small differences in input amplitude to frequent discontinuous jumps in output, generating strong high‑frequency components and noisy, buzzy timbres.[^3][^4]

Dragging the whole segment toward zero output makes more of the input range map to silence or near‑silence, creating a hard gating effect where only certain amplitude bands break through. Conversely, raising the peak of the square pattern increases perceived loudness and creates extreme clipping, especially when combined with high drive or pre‑gain.[^3]

Because square mode is highly non‑continuous at internal boundaries, movements of points that change which parts of the waveform fall into each square can drastically alter timbre even with small edits. The outer quadrants (high amplitude) squares particularly affect low‑frequency content like kicks, while inner squares near the zero‑crossing add high‑frequency buzz and “grain.”[^7][^4]

## Triangle Curve Type

### Mathematical Behavior

Triangle mode subdivides the segment into repeating triangular waveforms: output ramps linearly up and down between intermediate levels while respecting endpoint positions. As in square mode, a density parameter controls how many triangles appear in the segment; increasing density yields more frequent up‑down cycles over the same input amplitude range.[^4][^3]

Mathematically, the mapping approximates a sawtooth‑like or triangle‑wave transfer function applied to the input amplitude: for each sub‑interval, output increases linearly to a peak then decreases linearly, repeating across the range. This is equivalent to applying a non‑linear transfer that injects a periodic modulation into the static amplitude mapping.[^4][^3]

### Audible Effect and Response to Movement

Triangle segments introduce strong, periodic non‑linearity that tends to produce pronounced odd and even harmonics, often causing a “buzzy” yet somewhat more regular timbre than square mode. The up‑down nature of the mapping means that certain input amplitudes are amplified while nearby ones are attenuated, so the waveform becomes highly reshaped in a pattern reminiscent of ring‑modulated or folded waves.[^3][^4]

Increasing triangle density concentrates more cycles into the same input region, making distortion more complex and bright as more rapid changes in slope appear across amplitude. Moving the endpoints changes the overall tilt and range of the triangles, effectively biasing which amplitudes are boosted or cut; this lets users emphasize specific dynamic regions of the source (e.g., boosting mid‑level snare hits while attenuating ghost notes).[^3]

Because triangle mode maintains linear ramps rather than flat steps, it feels slightly smoother than square mode yet still highly synthetic and animated, especially when applied asymmetrically in bipolar mode.[^6][^3]

## Sine Curve Type

### Mathematical Behavior

Sine mode connects points using one or more sinusoidal arcs, producing a smooth, oscillatory mapping between input and output amplitude. As with triangle and square, a density‑like control adjusts how many sine cycles are packed into the segment, effectively scaling the angular frequency of the sine function in the amplitude domain.[^4][^3]

Conceptually, if endpoints are at \[(x_1, y_1)\] and \[(x_2, y_2)\], the mapping can be viewed as
\[y = y_\text{mid} + A \cdot \sin(\omega (x - x_\text{mid}) + \phi),\]
with parameters chosen so that the sine curve passes through both endpoints and respects the density setting. This yields a smooth periodic transfer function that smoothly oscillates around some midline rather than sharply stepping or cornering.[^4]

### Audible Effect and Response to Movement

Sine segments produce complex yet flowing distortion, adding rich harmonic content without the severe alias‑prone edges of square or step modes. Because the mapping oscillates, certain ranges of input amplitude are alternately boosted and cut, leading to wave folding and dynamic tone changes as the source’s amplitude traverses the sine cycles.[^3][^4]

Increasing sine density creates more folds in the amplitude transfer, which can yield formant‑like peaks and comb‑filter‑like tonal structures in the distorted sound. Moving points modifies both the amplitude and bias of the sine oscillation: pulling the segment upward increases overall gain and saturation; shifting it downward can create soft gating; tilting endpoints introduces asymmetry that emphasizes certain parts of the waveform.[^4]

When used near the zero‑crossing, sine mode heavily reshapes the micro‑structure of the waveform around its midline, strongly affecting perceived brightness and transient attack. Applied only to positive or negative half cycles (via bipolar mode), sine segments can create asymmetrical wave folding that gives rise to unusual “rectified” or half‑wave‑modulated timbres.[^7][^4]

## Stair‑Step / Quantization Curve Type

### Mathematical Behavior

The stairstep mode (described in tutorials as “stairstepping” or quantization) replaces continuous interpolation with a series of horizontal steps at discrete output levels across the input range. The density control adjusts the number of steps: higher settings add more, smaller steps; lower settings yield fewer, larger steps.[^3][^4]

Mathematically, the mapping acts like an amplitude quantizer: input amplitude is rounded to one of a finite set of output values determined by segment endpoints and density. Unlike square mode, which alternates rectangles with jumps, the stairstep mode uses a single monotonically rising series of steps (unless inverted) that approximates a coarse staircase version of the underlying line.[^4][^3]

### Audible Effect and Response to Movement

Stairstep segments create distortion reminiscent of bit‑depth reduction, because many nearby input values collapse to the same output level, injecting quantization noise and high‑frequency components. However, tutorial authors stress that this is not identical to a true bitcrusher: actual digital bit‑depth processes modulate noise characteristics via encoder behavior, whereas Trash 2’s stairstep mode is a deterministic transfer function on amplitude.[^3][^4]

Increasing step density makes the mapping closer to a smooth curve while still quantized, yielding subtler digital harshness; decreasing density exaggerates “grid snapping” and produces more obvious stair‑stepped artifacts. Moving endpoints or the entire segment upward increases perceived loudness and sharpens distortion; dragging toward zero compresses dynamics and can produce stuttering gate‑like effects when many steps lie near silence.[^3]

Because quantization primarily affects mid‑level and low‑level amplitudes, placing stairstep segments around the zero‑crossing region tends to emphasize high‑frequency fizz and transient grain; applying them only in outer quadrants focuses digital harshness on peaks while allowing quiet details to pass more cleanly.[^7][^4]

## Interaction with Movement, Density, and Bipolar Mode

### Point Movement and Local Mapping

In all curve types, moving a control point vertically changes the output amplitude for all input values in its neighborhood, effectively redistributing dynamic emphasis across the waveform. Horizontal movement changes which input amplitudes fall under a given non‑linear behavior: sliding a point left brings its effects into lower‑level signals; sliding right restricts non‑linearity to louder transients.[^4][^3]

The zero‑crossing region is especially sensitive: small adjustments there can radically alter perceived brightness, clickiness, and aliasing, because this is where many harmonics overlap and where frequent waveform crossings occur. Pushing the curve toward zero at the center can mute or heavily compress subtle details, while pulling it away injects strong non‑linearity into the heart of the waveform.[^4]

### Density Controls in Non‑Linear Modes

Square, triangle, sine, and stairstep modes all expose some form of density parameter that controls how many discrete structures (squares, triangles, sine cycles, or steps) are embedded between endpoints. Higher density increases complexity of the transfer function, adding more rapid changes in slope or level across amplitude; this usually raises high‑frequency harmonic content and may increase aliasing if over‑sample settings are low.[^8][^3][^4]

Lower density simplifies the transfer, making behavior closer to a single fold or simple clip and often reducing harshness, at the cost of less detailed timbral shaping. For design, density is best thought of as “non‑linearity granularity”: more granularity yields more detailed micro‑structure in how the waveform is reshaped.[^3]

### Bipolar Mode and Asymmetrical Distortion

In symmetrical mode, the positive and negative quadrants of the waveshaper share identical curves, so any curve type and movement affects both halves of the waveform equally and maintains a symmetric transfer function. Enabling bipolar mode unlocks separate control over positive and negative quadrants, allowing different curve types and node placements on each side.[^6][^3]

Any time the positive half‑cycle mapping differs from the negative half‑cycle mapping, Trash 2 produces asymmetrical distortion, which can shift DC offset and create more complex harmonic content, including stronger even harmonics and rectified or saw‑like waveforms. Applying aggressive curve types (square, sine, triangle, or stairstep) only to one half while leaving the other relatively linear can generate “half‑wave” saturation and unique timbres that emphasize either compressive or expansive behavior on specific parts of the cycle.[^6][^7]

Careful use of DC filters and over‑sampling options is recommended when using intense asymmetrical shapes, as tutorials note that extreme offset or aliasing can introduce clicks or headroom issues if left unaddressed.[^4]

## Relationship to Base Algorithms and Multiband Mode

Trash 2’s Trash module offers many built‑in distortion algorithms (amp simulations, fuzz, saturation, experimental types) that appear as red base curves in the waveshaper display; the user’s custom curve (yellow) is combined with this base to yield a composite result (often shown in another color). Curve type choices therefore operate on top of, or in conjunction with, the underlying algorithm’s transfer function, modifying its effective mapping rather than replacing it entirely.[^9][^4]

This means that the exact audible result of a given curve type depends heavily on which algorithm is active: for example, a mild sine‑density segment on top of a tape‑like saturation curve will sound different from the same segment over an aggressive fuzz algorithm. Curve types are best understood as a second layer of waveshaping that lets users fine‑tune or radically disrupt the base algorithm.[^9][^8]

In multiband mode, Trash 2 splits the input into up to four frequency bands, each with its own waveshaper and filter stages; curve types can be chosen independently per band. This enables highly targeted distortion design: for instance, using tension and linear segments in low‑frequency bands to preserve punch while applying sine or triangle segments with high density in the mid‑high bands to create animated harmonics.[^2][^4]

## Practical Implications for Sound Design

### Curve Type Selection by Goal

For subtle analog‑style enhancement and saturation, tension and linear segments, possibly combined with gentle sine arcs of low density, provide smooth non‑linearity and controllable compression without severe artifacts. For hard digital destruction, square and stairstep modes, with moderate to high density and strong endpoint movements, yield gated, bit‑crushy, and noisy timbres.[^8][^3][^4]

Triangle and sine modes sit between these extremes, offering animated folding and harmonic structures that can sound synthetic yet musical, especially when tuned carefully and applied in frequency‑specific bands. Asymmetrical use via bipolar mode can further emphasize uniqueness by shifting waveform balance and DC offset to produce modern “glitchy” or “grindy” textures.[^2][^6][^3]

### Movement Strategies for Controlled Results

Tutorial authors emphasize incremental movement of central points and density handles rather than drawing extreme shapes in one step, as small adjustments often produce significant timbral shifts. Starting from the default unity line, users can gradually pull mid‑range points upward for saturation, lower extreme points for soft clipping, and then swap curve types to explore how oscillatory or stepped mappings change the harmonic profile.[^10][^11]

Working zoomed‑in on specific quadrants helps visualize how the chosen curve type reshapes that portion of the transfer function and gives better control over where non‑linearity is concentrated. Combining this with band‑solo in multiband mode allows designers to audition, for example, how a high‑density sine segment in the upper band affects cymbal air without simultaneously mangling kick fundamentals.[^2][^3][^4]

## Limitations of Available Information

iZotope’s public manuals and help documentation describe Trash 2’s waveshaper conceptually but do not provide explicit mathematical formulas for each curve type’s interpolation or density behavior. Detailed behavior must therefore be inferred from tutorials, user demonstrations, and observable UI responses, which accurately show qualitative patterns but may omit implementation nuances like exact spline orders or internal scaling.[^1][^3][^4]

As a result, while this report can confidently describe the relative behavior—such as square mode mapping many inputs to constant outputs or sine mode embedding oscillatory arcs—it cannot claim an exact closed‑form expression for the transfer functions. Nonetheless, the synthesis of multiple authoritative tutorials and documentation provides a reliable foundation for understanding and exploiting Trash 2’s curve types in practical sound design.[^1][^4]

---

## References

1. [iZotope Trash 2 Help Documentation | Distortion Plug-in](https://help.izotope.com/docs/izotope-trash2-help.pdf)

2. [iZotope Trash 2: How to Use Multiband Mode | Music Production | Sound Design | Berklee Online](https://www.youtube.com/watch?v=dLsLq7w1G08) - Download Your Free Music Production Handbook Now: https://berkonl.in/3JBxeTK
Earn Your Music Product...

3. [iZotope Trash 2: Basic Waveshaping | Music Production | Sound Design | Berklee Online](https://www.youtube.com/watch?v=7nTNZMqgGiU) - Download Your Free Music Production Handbook Now: https://berkonl.in/3JBxeTK
Earn Your Music Product...

4. [Trash 2 4 - Waveshaping](https://www.youtube.com/watch?v=yQejl6T0w-g) - We look at the Waveshaper! These things tend to be shrouded in mystery and I do what I can to remove...

5. [iZotope Trash2 Wave Shaper](https://www.youtube.com/watch?v=3SWOsaAyuRo) - A basic overview of the Wave Shaper within Trash 2. Check out our full review at http://www.recordin...

6. [iZotope Trash 2: Asymmetrical Distortion | Music Production | Sound Design | Berklee Online](https://www.youtube.com/watch?v=p1650lPFWik) - Download Your Free Music Production Handbook Now: https://berkonl.in/3JBxeTK
Earn Your Music Product...

7. [Waveshaper Shapes?](https://www.reddit.com/r/edmproduction/comments/53icn2/waveshaper_shapes/)

8. [Free iZotope Trash 2 License For Novation Sound Collective ...](https://synthanatomy.com/2019/08/free-izotope-trash-2-license-for-novation-sound-collective-community.html) - Get a free license for iZotope Trash 2 license, a powerful multiband distortion plugin as a member o...

9. [iZotope Trash 2 review](https://www.musicradar.com/reviews/tech/izotope-trash-2-570299) - Update time for the multiband distortion plugin

10. [How to properly use Izotope's Trash 2?](https://www.reddit.com/r/edmproduction/comments/stjkjw/how_to_properly_use_izotopes_trash_2/) - How to properly use Izotope's Trash 2?

11. [How to properly use Izotope's Trash 2?](https://www.reddit.com/r/edmproduction/comments/stjkjw/how_to_properly_use_izotopes_trash_2/hx4btg9/) - How to properly use Izotope's Trash 2?

