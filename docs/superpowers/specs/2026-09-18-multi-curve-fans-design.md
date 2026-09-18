# Several curves per fan, and one glass drop for the whole app

Status: approved 2026-09-18. Mockups: the "GlassFan Multi-Curve Fans" design canvas
(boards "B · numbers on the lines, groups as cards", "Default", "Drop").

## Why

A fan follows one curve over one group of sensors. That cannot express "keep the palm
rests below 33 °C, but also react at once when the CPU spikes before the case has warmed".
Several curves, each over its own group of sensors, with the fan at the fastest of them, can.

## Config

- `FanSettings.curves: [CurveRule]`, 1...3, where `CurveRule { sensorKeys: [String]; curve: FanCurve }`.
- Decoding: `curves` when present; otherwise the old `sensorKeys` + `curve` become curve 1,
  so an existing config comes through unchanged.
- Encoding writes `curves` and, again, curve 1 into the old `sensorKeys` / `curve` keys, so
  a 0.1.12 daemon handed a new config still drives by curve 1.
- A new curve starts with two points: 40 °C → 0 rpm, 90 °C → the fan's maximum.
  Points: at least 2, at most 10.
- One sensor may sit in several groups.
- Hysteresis and smoothing stay per fan.

## Control

- Each curve reads the hottest sensor of its own group, with its own hysteresis hold
  (a cooling group must not drag another's hold down).
- The fan's demand is the maximum over the curves' demands; smoothing applies to that.
- Emergency: any assigned sensor in any group at or above the emergency temperature.
- A curve whose group has no readings is skipped; no curve with a reading → the fan goes
  back to the system, as today.
- `FanReading.drivingCurve: Int?` — index of the curve that won. `drivingTemp` is that
  curve's temperature.

## Glass: one drop for the app

- The shader's shape is generalised from a horizontal capsule to a *drop*: two rounded
  rectangles (head and tail) joined by a smooth minimum, with the corner radius a parameter.
  The rim normal comes from the shape's gradient. `glassLens` and `glassLight` keep their
  refraction, dispersion, frost, Fresnel reflection, glare, edge light and shade, and read
  the new shape.
- `GlassSegmented` passes head = tail and radius = half the height: the capsule it has
  today. Its behaviour does not change.
- `GlassDropList` (new) is the vertical list of curve groups. It shares `LensSpring`,
  `LensShaders`, the light and shadow painting, and the lift/land/commit-on-arrival rules
  of the segmented control, and adds:
  - a tail on a softer spring that chases the head, so the drop stretches and necks;
  - thinning and rounding towards a pill with speed, and an extra pinch over a gap;
  - while dragged, sticking to the card under it: each card owns from mid-gap above to
    mid-gap below, and the drop follows the pointer by `t³` inside that stretch;
  - release onto the card whose stretch holds the drop.
- At rest the selected card sits on the same glass platter as a selected segment; on a
  press or a move the platter lifts into the lens. The glass is neutral, as the segmented
  control's; "being edited" is said by the blue number and the blue line.

## Interface

- Sidebar "Curve sensors": one card per curve (number, "editing" / "driving the fan" tags,
  its own "+", sensor chips). "+ curve" in the header while fewer than 3. A card's "✕" on
  hover while more than one curve.
- Plot: the edited curve blue with handles; the driving curve orange with the live marker;
  others dashed grey. Each curve's number sits at its right end, in a margin; numbers are
  kept 20 pt apart — the edited one keeps its place, others step aside with a leader to
  their line's end. Clicking a number edits that curve. Only the edited curve's points
  take drags and double-clicks.
- One curve looks as today: no numbers, no cards.

## Tests

- FanKit: decoding an old config; encoding writes both shapes; max over curves; per-curve
  hysteresis; emergency from any group; `drivingCurve`; point limits.
- UI (pure functions): drop stickiness and ownership; number placement with overlaps.
- Previews: one curve, three curves, the drop held mid-flight.
- Live: 0.1.13 on this M1 Max.
