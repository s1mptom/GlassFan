import SwiftUI

/// The numbers behind the drop's rim, in one place rather than spread through the
/// shader's call sites.
///
/// The rim's profile was read pixel by pixel off Activity Monitor's drop: depths are
/// points in from the edge, for a drop 19pt tall from centre to edge, scaled for others.
final class LensTuning: Sendable {
    static let shared = LensTuning()

    /// How far the segmented drop stands past its platter when up.
    let growX: Double = 12
    let growY: Double = 10

    /// The bead round the rim - the ashtray's wall, in two zones over `rimWidth`
    /// points. Nearest the edge the outer wall shows what lies `beadOut` points beyond
    /// the drop, squeezed; behind it the inner wall shows what lies `beadIn` points
    /// further in, drawn outward, at strength `beadMix`. `beadBlur` is how much the
    /// bead scatters, `rimSharp` how fast it fades into the floor.
    let beadOut: Double = 1.6
    let beadIn: Double = 2.6
    let beadMix: Double = 0.9
    let beadBlur: Double = 0.8
    let rimWidth: Double = 6.0
    let rimSharp: Double = 1.4
    /// How far the colours part at the rim, and how much of that survives along the
    /// straight sides; the blur across the rim; how much brighter the rim makes what
    /// it bends.
    let dispersion: Double = 0.5
    let straightDispersion: Double = 0.6
    let frostBase: Double = 0.15
    let frostGain: Double = 0.5
    let gather: Double = 1.3

    /// The dark line at the edge: its width, and how dark.
    let edgeWidth: Double = 0.9
    let edgeDark: Double = 0.45
    /// The rim's own coloured reflection: 0 for none.
    let iridescence: Double = 0.0

    var lensArguments: [Shader.Argument] {
        [.float4(Float(beadOut), Float(rimWidth), Float(rimSharp), Float(beadIn)),
         .float4(Float(beadMix), Float(beadBlur), 0, 0),
         .float4(Float(dispersion), 0, Float(straightDispersion), Float(frostBase)),
         .float4(Float(frostGain), Float(gather), 0, 0)]
    }

    var lightArguments: [Shader.Argument] {
        [.float4(Float(edgeWidth), Float(edgeDark), 0, Float(iridescence))]
    }
}
