import Testing
@testable import GlassFanUI

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

import FanKit

/// A fan the daemon could not hold has to say which of the two things went wrong.
/// They look the same from a distance and mean opposite things to whoever reads
/// them: one is something to go and fix, the other is the machine overruling us.
@Suite("Fan failure wording")
struct FanFailureWordingTests {
    private func reading(_ failure: FanWriteFailure?, error: String?) -> FanReading {
        FanReading(index: 0, actualRPM: 0, targetRPM: 0,
                   limits: FanLimits(minRPM: 1350, maxRPM: 5349),
                   mode: .fixed, forced: false, drivingTemp: nil, emergency: false,
                   writeError: error, writeFailure: failure)
    }

    @Test("a held fan says nothing")
    func silenceWhenHolding() {
        let held = reading(nil, error: nil)
        #expect(held.failureCaption == nil)
        #expect(held.failureSubtitle == nil)
        #expect(!held.alerting)
    }

    @Test("a refusal and a discarded write read differently")
    func theTwoFailuresDiffer() {
        let refused = reading(.refused, error: "…")
        let ignored = reading(.ignored, error: "…")
        #expect(refused.failureCaption != ignored.failureCaption)
        #expect(refused.failureSubtitle != ignored.failureSubtitle)
        #expect(refused.alerting && ignored.alerting)
    }

    @Test("a daemon too old to say which one is taken at its word about the fact")
    func olderDaemonStillSaysSomething() {
        let old = reading(nil, error: "SMC key F0Tg refused the write")
        #expect(old.failureCaption == reading(.refused, error: "…").failureCaption)
        #expect(old.alerting)
    }

    @Test("taking control is not a failure and does not colour the fan red")
    func acquiringIsProgress() {
        // Every second of the five to thirteen the thermal manager takes to let go
        // arrives as a refused write. Reported as one, it reads as something broken
        // that the user should go and fix, which is how it was first reported.
        let taking = FanReading(index: 0, actualRPM: 0, targetRPM: 3000,
                                limits: FanLimits(minRPM: 1350, maxRPM: 5349),
                                mode: .curve, forced: false, drivingTemp: 31, emergency: false,
                                writeError: "SMC refused F0Md with status 0x82",
                                writeFailure: nil, acquiring: true)
        #expect(taking.failureCaption != reading(.refused, error: "…").failureCaption)
        #expect(taking.failureSubtitle != reading(.refused, error: "…").failureSubtitle)
        #expect(!taking.alerting)
        // A real refusal still does.
        #expect(reading(.refused, error: "…").alerting)
    }

    @Test("an emergency colours the fan even while the daemon is holding it")
    func emergencyAlerts() {
        let emergency = FanReading(index: 0, actualRPM: 5349, targetRPM: 5349,
                                   limits: FanLimits(minRPM: 1350, maxRPM: 5349),
                                   mode: .curve, forced: true, drivingTemp: 99, emergency: true)
        #expect(emergency.alerting)
        #expect(emergency.failureCaption == nil)
    }
}
