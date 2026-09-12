import Testing
@testable import MacFansUI

/// The two glass dials were reported as not doing what they say: Tone appeared
/// inert, and Frost appeared to change the tone. Both were true, because one
/// veil carried both jobs - its opacity was the frosting and its lightness was
/// the tone, so at Frost 0 there was no veil for a tone to colour, and Tone's
/// authority scaled with Frost.
///
/// These assert the separation rather than particular numbers, and they do it
/// on the arithmetic alone. An earlier version resolved the veils as Colors;
/// an adaptive Color resolves through AppKit, and doing that from a test that
/// runs off the main actor hung the runner - seven times, silently.
@Suite("Glass dials")
struct GlassStyleTests {

    @Test("the tone moves the backing across its whole travel")
    func toneHasAuthority() {
        let dark = GlassStyle.apparentLightness(tint: -1)
        let middle = GlassStyle.apparentLightness(tint: 0)
        let light = GlassStyle.apparentLightness(tint: 1)

        #expect(dark < middle)
        #expect(middle < light)
        // Both ends have to arrive somewhere useful: a light end that is mid-grey
        // is the one backing no ink reads well on, and that is what it used to be.
        #expect(dark < 0.05)
        #expect(light > 0.8)
    }

    @Test("the tone is monotonic, with no flat stretch to feel like a dead dial")
    func toneIsMonotonic() {
        let steps = stride(from: -1.0, through: 1.0, by: 0.1).map {
            GlassStyle.apparentLightness(tint: $0)
        }
        for (before, after) in zip(steps, steps.dropFirst()) {
            #expect(after > before)
        }
    }

    /// The regression, and the mechanism that fixes it: the frost veil is the
    /// lightness of the material it covers, so however much of it goes down the
    /// backing stays the lightness it was. Frost therefore does not appear in
    /// `apparentLightness` at all - only the tone can move it.
    @Test("the frosting does not touch the tone")
    func frostIsLightnessNeutral() {
        // The frost veil's colour is the material's own level; only its opacity
        // is a function of the dial.
        #expect(abs(GlassStyle.materialLevel - GlassStyle.apparentLightness(tint: 0)) < 0.001)
        for frost in [0.0, 0.25, 0.5, 0.75, 1.0] {
            #expect(GlassStyle.frostOpacity(frost) >= 0)
            #expect(GlassStyle.frostOpacity(frost) < 1)
        }
    }

    @Test("more frosting means a denser veil, and the ends are honest")
    func frostSetsDensity() {
        let clear = GlassStyle.frostOpacity(0)
        let half = GlassStyle.frostOpacity(0.5)
        let solid = GlassStyle.frostOpacity(1)

        #expect(clear == 0)
        #expect(half > clear)
        #expect(solid > half)
        // Never fully opaque: some of the desktop always shows, or it is not glass.
        #expect(solid < 1)
    }

    /// The other half of the original complaint: at every frost, Tone must do
    /// something. Its veil is separate, so its opacity cannot depend on Frost.
    @Test("the tone has the same authority at every frost")
    func toneIsIndependentOfFrost() {
        #expect(GlassStyle.toneOpacity(1) > 0.5)
        #expect(GlassStyle.toneOpacity(-1) == GlassStyle.toneOpacity(1))
        #expect(GlassStyle.toneOpacity(0) == 0)
        #expect(GlassStyle.toneIsWhite(0.3))
        #expect(!GlassStyle.toneIsWhite(-0.3))
    }

    @Test("the ink flips at +40% on the tone dial, and only there")
    func inkFlipsWithTheTone() {
        #expect(GlassStyle.isLight(tint: -1) == false)
        #expect(GlassStyle.isLight(tint: 0) == false)
        #expect(GlassStyle.isLight(tint: 0.39) == false)
        #expect(GlassStyle.isLight(tint: 0.4) == true)
        #expect(GlassStyle.isLight(tint: 1) == true)
    }

    /// Out of the box the glass matches the system: dark glass on a dark Mac,
    /// light on a light one - and each default sits on the right side of the
    /// ink flip, so neither ships as white text on a light pane or the reverse.
    @Test("defaults follow the appearance and land on the right side of the flip")
    func defaultsFollowAppearance() {
        #expect(GlassStyle.defaultFrost == 0.5)
        #expect(GlassStyle.defaultTint(dark: true) == -0.5)
        #expect(GlassStyle.defaultTint(dark: false) == 0.5)
        #expect(GlassStyle.isLight(tint: GlassStyle.defaultTint(dark: true)) == false)
        #expect(GlassStyle.isLight(tint: GlassStyle.defaultTint(dark: false)) == true)
    }

    @Test("values beyond the dials' travel are clamped rather than extrapolated")
    func outOfRangeIsClamped() {
        #expect(GlassStyle.apparentLightness(tint: 5) == GlassStyle.apparentLightness(tint: 1))
        #expect(GlassStyle.apparentLightness(tint: -5) == GlassStyle.apparentLightness(tint: -1))
        #expect(GlassStyle.frostOpacity(9) == GlassStyle.frostOpacity(1))
        #expect(GlassStyle.toneOpacity(9) == GlassStyle.toneOpacity(1))
    }
}
