import SwiftUI

/// The numbers behind the drop's rim, in one place, so the glass lab can turn them
/// while the drop is on screen. The defaults are the app's look; the lab changes
/// them for its process only.
///
/// The rim's profile was read pixel by pixel off Activity Monitor's drop: depths are
/// points in from the edge, for a drop 19pt tall from centre to edge, scaled for others.
@Observable
final class LensTuning: @unchecked Sendable {
    nonisolated(unsafe) static let shared = LensTuning()

    /// How far the segmented drop stands past its platter when up.
    var growX: Double = 12
    var growY: Double = 10
    /// The body's magnification, for the lab's drop.
    var magnification: Double = 1.1

    /// The bead round the rim - the ashtray's wall, in two zones over `rimWidth`
    /// points. Nearest the edge the outer wall shows what lies `beadOut` points beyond
    /// the drop, squeezed; behind it the inner wall shows what lies `beadIn` points
    /// further in, drawn outward, at strength `beadMix`. `beadBlur` is how much the
    /// bead scatters, `rimSharp` how fast it fades into the floor.
    var beadOut: Double = 1.6
    var beadIn: Double = 2.6
    var beadMix: Double = 0.9
    var beadBlur: Double = 0.8
    var rimWidth: Double = 6.0
    var rimSharp: Double = 1.4
    /// How far the colours part at the rim, and how much of that survives along the
    /// straight sides; the blur across the rim; how much brighter the rim makes what
    /// it bends.
    var dispersion: Double = 0.5
    var straightDispersion: Double = 0.6
    var frostBase: Double = 0.15
    var frostGain: Double = 0.5
    var gather: Double = 1.3

    /// The dark line at the edge: its width, and how dark.
    var edgeWidth: Double = 0.9
    var edgeDark: Double = 0.45
    /// The rim's own coloured reflection: 0 for none.
    var iridescence: Double = 0.0

    /// The lab's drop.
    var dropWidth: Double = 120
    var dropHeight: Double = 46

    /// `GLASSFAN_TUNE="pullStrength=3,flatEnd=5"`: knobs set at launch, by the names
    /// above, for a run of the lab or of the app itself.
    init() {
        for pair in (ProcessInfo.processInfo.environment["GLASSFAN_TUNE"] ?? "").split(separator: ",") {
            let kv = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2, let value = Double(kv[1]), let path = Self.knobs[kv[0]] else { continue }
            self[keyPath: path] = value
        }
    }

    /// The app's own numbers, whatever the environment says.
    init(defaults: Void) {}

    static let knobs: [String: ReferenceWritableKeyPath<LensTuning, Double>] = [
        "growX": \.growX, "growY": \.growY, "magnification": \.magnification,
        "beadOut": \.beadOut, "beadIn": \.beadIn, "beadMix": \.beadMix, "beadBlur": \.beadBlur,
        "rimWidth": \.rimWidth, "rimSharp": \.rimSharp,
        "dispersion": \.dispersion, "straightDispersion": \.straightDispersion,
        "frostBase": \.frostBase, "frostGain": \.frostGain, "gather": \.gather,
        "edgeWidth": \.edgeWidth, "edgeDark": \.edgeDark, "iridescence": \.iridescence,
        "dropWidth": \.dropWidth, "dropHeight": \.dropHeight,
    ]

    var lensArguments: [Shader.Argument] {
        [.float4(Float(beadOut), Float(rimWidth), Float(rimSharp), Float(beadIn)),
         .float4(Float(beadMix), Float(beadBlur), 0, 0),
         .float4(Float(dispersion), 0, Float(straightDispersion), Float(frostBase)),
         .float4(Float(frostGain), Float(gather), 0, 0)]
    }

    var lightArguments: [Shader.Argument] {
        [.float4(Float(edgeWidth), Float(edgeDark), 0, Float(iridescence))]
    }

    func reset() {
        let fresh = LensTuning(defaults: ())
        for path in Self.knobs.values { self[keyPath: path] = fresh[keyPath: path] }
    }

    /// The knobs as a line to paste back into the defaults.
    var summary: String {
        Self.knobs.keys.sorted().map { "\($0)=\(self[keyPath: Self.knobs[$0]!])" }.joined(separator: ",")
    }
}
