---
name: glass-lab
description: Tune and inspect GlassFan's liquid-glass drop (the segmented control's lens and the curve-group drop) without a pointer - place the drop on a test ground, set any rim knob, take lossless screenshots, compare with Apple's drop.
---

# Glass lab

The drop's rim is driven by numbers in `Sources/GlassFanUI/LensTuning.swift` (defaults = the
app's look) and rendered by `Sources/GlassFanUI/Shaders/GlassLens.metal`. The lab window
(`Sources/GlassFanUI/GlassLab.swift`, opened with `GLASSFAN_LAB=1`) shows a drop over a test
ground with every knob on a slider.

## Screenshots from the shell (preferred - nothing moves on the user's screen)

```
Scripts/build-app.sh                      # after any code change
Scripts/glass-lab.sh -z 280,190,300,70 out.png                 # defaults, drop over the small track
Scripts/glass-lab.sh -t "pullStrength=2.5,flatEnd=6" -c -z 280,190,300,70 out.png   # defaults vs tuned, stacked
Scripts/glass-lab.sh -p lines -d 400,120 -s 200x80 out.png     # bigger drop over coloured lines
```

Knob names: growX growY magnification straightScale capsScale pullStrength pullEnd flatEnd
jumpOut slope bodyStart dispersionOuter dispersionInner straightDispersion frostBase frostGain
gather edgeWidth edgeDark dropWidth dropHeight. Bench coordinates (1180x700 window): the small track (34pt) spans x 262-584, centred on y 224;
the big one (44pt) is centred on y 303; the coloured lines span y 367-420; the small track's
labels are at x≈308 Overview, 384 Fans, 457 Sensors, 541 Settings. Lines pattern: coloured
lines y 158-240 (full width), columns x 100-300 and grid x 323-523 at y 265-380, white lines
y 420-470. Text pattern: rows centred on x 423 at y 243 (11pt), 286 (13pt), 332 (17pt), 384 (24pt). Zoom rectangles are in bench points; `-m` sets the magnification (default 4).

Read the result with the Read tool. To measure, dump a pixel column with the profile tool:
`python3 Scripts/lab/col.py shot.png <x-px> <y0> <y1> label` (2x pixels, prints r g b and luma).

Once numbers look right, write them into `LensTuning`'s defaults - the app reads no env.

## The reference

Apple's drop, read off Activity Monitor (lossless), depths in points from the edge for a drop
19pt from centre to edge, standing 4pt past the track: 0-1 dark edge (luma 17); 1-2.5 a
coloured line (the track's bright edge, drawn out and dispersed); 2.5-3.5 window background;
3.5-5 the track's edge in place (luma 83); 5-7.5 background again (48) - the image jumps
outward; 7.5+ the track fill (67), narrower than outside, text slightly bigger. Colour
fringes are strong at the curved ends, faint along the straight sides.

What reproduces this without artefacts (found on the lines ground): the bevel pulls the image
in from ~4pt (the rim's coloured line), the body is evenly magnified, and the dark 5-7.5pt
zone is a *shade ring* (`ringDark`), not refraction - an outward-sampling lobe there copies
text twice and zigzags lines crossing the curved ends. Keep `jumpOut` at 0.

## Real drags (only when the lab is not enough)

With Accessibility granted to claude.app, `Scripts/lab/dragxy.swift` (compile with `swiftc -O`)
drags any app with real mouse events: `dragxy <bundle-id> <pt/s> x,y x,y ...`; `locate.swift`
prints an app's window and buttons in screen points. Warn the user first - the cursor moves -
and quit the installed app before driving the demo build, or the events land in the wrong one.
Take lossless PNGs with `screencapture -x -R x,y,w,h` during the drag, not video.

## Checking the app itself, not only the lab

The tab drop in the app is 76x41 over a 34pt track (4pt clearance, as Apple's 84x46 over 38);
the lab's default drop is not - pass `-s 76x41` on the small track, or `-p apple -s 84x46
-d 298,241`. To hold the app's own drop without a pointer: `GLASSFAN_DEMO=1 GLASSFAN_PRESS="465,26"
./GlassFan.app/Contents/MacOS/GlassFan` (window lands at screen 360,141; tabs at y 166) with `.build/lab/backdrop &` started first (a plain dark window behind
the app - its backing is translucent and shows whatever is behind), then
`screencapture -x -R690,135,340,60`; the drop is then centred at px (270,64) of that crop -
profile column 270, not the cap region. Quit the installed app first.
