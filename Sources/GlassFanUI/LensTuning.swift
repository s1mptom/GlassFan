import SwiftUI

/// The numbers behind the drop, in one place rather than spread through the shader's
/// call sites.
///
/// Fitted to Apple's own drop - Activity Monitor's segmented control, fifteen frames
/// held at the same places in the dark appearance and in the light - on the glass
/// bench (a separate package, kept off the main branch). Depths are points in from the
/// edge; Apple's drop is 46pt tall. The two sets agree on everything the glass does to
/// where things are - the line, the pull, the parted colours, the growth - and differ
/// in tone: on dark the glass dims and lifts what it covers and its hairline is near
/// black; on light it leaves the ground be and its hairline is grey. The shadow and the
/// darkening under the top edge are the same on both, a few per cent - which is why
/// they were only seen once the light frames were in.
final class LensTuning: Sendable {
    static let shared = LensTuning()

    /// How far the segmented drop stands past its platter when up.
    let growX: Double = 12
    let growY: Double = 10

    /// Every number, in the order the shader unpacks them.
    struct Rim: Sendable {
        /// The thin line of colour: a band `lineWidth` wide at `lineAt` in, showing what
        /// lies `lineReach` further in; red and blue fetched `rbShift` further than green.
        var lineAt, lineReach, lineWidth, rbShift: Double
        /// The track's band, `bandFrom`-`bandTo` inside its edge, showing what lies
        /// `bandReach` beyond it; the glass's lift over the rim.
        var bandFrom, bandTo, bandReach, ledgeLift: Double
        /// How much bigger labels come out (the control's, eased in with the lift);
        /// the ends' own pull; where the rim ends and the body starts; the ends' extra
        /// parting of colours.
        var magnification, capPull, bodyAt, endSpread: Double
        var edgeDark, lineGain, ledgeChroma, ledgeGain: Double
        /// Round the ends: the line's pull facing along the drop, as a share; red and
        /// blue's softening over the outer `blurDepth`; how much of the glass is left.
        var endReach, rbBlur, blurDepth, endGlass: Double
        var endBlur, lineSpread, endWidth, endChroma: Double
        /// The shadow outside, darkest `shadowAt` out, `shadowWidth` wide, `shadowUp` of
        /// it above the drop.
        var shadowDark, shadowAt, shadowWidth, shadowUp: Double
        /// The darkening inside, `innerAt` under the top edge; `innerBottom` of it under
        /// the bottom one (negative: lighter).
        var innerShade, innerAt, innerWidth, innerBottom: Double

        /// Written out plainly: Xcode 26's compiler gave up type-checking the same
        /// thing as one array literal mapped in a closure.
        var arguments: [Shader.Argument] {
            var values: [Double] = []
            values += [lineAt, lineReach, lineWidth, rbShift]
            values += [bandFrom, bandTo, bandReach, ledgeLift]
            values += [magnification, capPull, bodyAt, endSpread]
            values += [edgeDark, lineGain, ledgeChroma, ledgeGain]
            values += [endReach, rbBlur, blurDepth, endGlass]
            values += [endBlur, lineSpread, endWidth, endChroma]
            values += [shadowDark, shadowAt, shadowWidth, shadowUp]
            values += [innerShade, innerAt, innerWidth, innerBottom]
            var packs: [Shader.Argument] = []
            var i = 0
            while i + 3 < values.count {
                let x = Float(values[i]), y = Float(values[i + 1]), z = Float(values[i + 2]), w = Float(values[i + 3])
                packs.append(Shader.Argument.float4(x, y, z, w))
                i += 4
            }
            return packs
        }
    }

    /// The pull round the ends ran into the shader's limit of 1.98 in both fits.
    let dark = Rim(
                 lineAt: 1.372, lineReach: 3.888, lineWidth: 0.903, rbShift: 0.085,
                 bandFrom: 0.856, bandTo: 3.14, bandReach: 4.357, ledgeLift: 0.099,
                 magnification: 1.104, capPull: -1.98, bodyAt: 7.283, endSpread: 0.956,
                 edgeDark: 0.715, lineGain: 1.133, ledgeChroma: 0.073, ledgeGain: 0.633,
                 endReach: 0.065, rbBlur: 1.396, blurDepth: 8.375, endGlass: 0.321,
                 endBlur: 0.643, lineSpread: 0.166, endWidth: 1.62, endChroma: 0.878,
                 shadowDark: 0.049, shadowAt: 5.584, shadowWidth: 5.349, shadowUp: 0.141,
                 innerShade: 0.031, innerAt: 9.444, innerWidth: 4.465, innerBottom: -0.061)
    let light = Rim(
                 lineAt: 1.385, lineReach: 4.979, lineWidth: 1.158, rbShift: 0.056,
                 bandFrom: 0.595, bandTo: 3.926, bandReach: 2.964, ledgeLift: 0.006,
                 magnification: 1.093, capPull: -1.98, bodyAt: 5.467, endSpread: 0.896,
                 edgeDark: 0.301, lineGain: 0.964, ledgeChroma: 0.056, ledgeGain: 1.009,
                 endReach: 0.336, rbBlur: 1.22, blurDepth: 9.312, endGlass: 0.337,
                 endBlur: 0.03, lineSpread: 0.2, endWidth: 2.333, endChroma: 1.001,
                 shadowDark: 0.042, shadowAt: 4.801, shadowWidth: 5.117, shadowUp: 0.034,
                 innerShade: 0.043, innerAt: 10, innerWidth: 4.957, innerBottom: -0.063)

    func lensArguments(light isLight: Bool) -> [Shader.Argument] {
        (isLight ? light : dark).arguments
    }

    /// The dark drawn over the drop and round it: the hairline and the shadow.
    func lightArguments(light isLight: Bool) -> [Shader.Argument] {
        let rim = isLight ? light : dark
        return [.float4(Float(rim.edgeDark), 0, 0, 0),
                .float4(Float(rim.shadowDark), Float(rim.shadowAt), Float(rim.shadowWidth), Float(rim.shadowUp))]
    }
}
