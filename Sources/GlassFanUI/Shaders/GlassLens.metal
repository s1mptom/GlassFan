#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// A drop of glass over the content of a layer, shaped like an ashtray and measured
// off Apple's own: a low flat floor that magnifies a little and holds still, and a
// bead round the rim whose two walls each show something different - what lies beyond
// the edge, squeezed, and what lies further in, drawn outward - with the colours
// parting and the light scattering as they cross it. The bead has no light of its own;
// it is seen only through what it does. LensTuning holds every number.

struct DropHit {
    float dist;       // signed distance to the rim: negative inside
    float2 outward;   // unit normal of the rim, pointing out
};

/// A rectangle with rounded corners; `box` is x, y, width, height.
static float roundBox(float2 p, float4 box, float radius) {
    float2 halfSize = box.zw * 0.5;
    float2 centre = box.xy + halfSize;
    float r = min(radius, min(halfSize.x, halfSize.y));
    float2 q = abs(p - centre) - halfSize + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

static float segmentDist(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
    return length(pa - ba * h);
}

/// A minimum that melts two shapes into one where they come within `k` of each other.
static float smoothMin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

/// The drop: a head and a tail, each a rounded box, and between their centres a bridge
/// of radius `neck`, all melted together - so a drop pulled out of one place into
/// another necks between them the way a liquid does. With the tail on the head, a
/// radius of half the height and no neck, it is a capsule.
static float dropDist(float2 p, float4 head, float4 tail, float radius, float neck) {
    float d = roundBox(p, head, radius);
    float2 headCentre = head.xy + head.zw * 0.5, tailCentre = tail.xy + tail.zw * 0.5;
    // Melted over a good part of its thickness once the ends are apart, so the join
    // reads as liquid pulled between two places rather than two pills touching - but
    // only as far as they are apart. A smooth minimum of two nearly equal distances
    // comes out a quarter of its width *less* than either: with head and tail a point
    // apart, the whole drop swelled ten points past the glass drawn under it, and its
    // light ringed a row it should have sat on.
    float k = min(0.45 * min(min(head.z, head.w), min(tail.z, tail.w)),
                  0.6 * distance(headCentre, tailCentre));
    float tailDist = roundBox(p, tail, radius);
    d = k > 0.5 ? smoothMin(d, tailDist, k) : min(d, tailDist);
    if (neck > 0.0) {
        float bridge = segmentDist(p, headCentre, tailCentre) - neck;
        d = k > 0.5 ? smoothMin(d, bridge, k) : min(d, bridge);
    }
    return d;
}

/// The distance, and the rim's normal from the distance's slope.
static DropHit drop(float2 p, float4 head, float4 tail, float radius, float neck) {
    DropHit hit;
    hit.dist = dropDist(p, head, tail, radius, neck);
    const float e = 0.5;
    float2 slope = float2(
        dropDist(p + float2(e, 0.0), head, tail, radius, neck) - dropDist(p - float2(e, 0.0), head, tail, radius, neck),
        dropDist(p + float2(0.0, e), head, tail, radius, neck) - dropDist(p - float2(0.0, e), head, tail, radius, neck));
    float l = length(slope);
    hit.outward = l > 1e-4 ? slope / l : float2(0.0, 1.0);
    return hit;
}

/// The drop's thickness: its narrowest side. The bevel is cut from half of it.
static float thickness(float4 head, float4 tail) {
    return min(min(head.z, head.w), min(tail.z, tail.w));
}

/// Premultiplied "top over bottom".
static half4 over(half4 top, half4 bottom) {
    return top + bottom * (1.0h - top.a);
}

/// The frost on the rim: a small blur. Five taps in a cross while it is slight; past
/// a point and a half, nine - the cross and its diagonals - so what is under the
/// edge of the glass melts, as under Apple's, rather than showing twice.
static half4 frosted(SwiftUI::Layer layer, float2 p, float2 along, float2 across, float spread) {
    if (spread < 0.05) { return layer.sample(p); }
    half4 sum = layer.sample(p) * 2.0h
        + layer.sample(p + along * spread) + layer.sample(p - along * spread)
        + layer.sample(p + across * spread) + layer.sample(p - across * spread);
    if (spread < 1.5) { return sum / 6.0h; }
    float d = spread * 0.7071;
    sum += layer.sample(p + (along + across) * d) + layer.sample(p - (along + across) * d)
         + layer.sample(p + (along - across) * d) + layer.sample(p - (along - across) * d);
    return sum / 10.0h;
}

/// - head, tail: x, y, width, height of the drop's two ends in the layer's
///   coordinates; the same box twice for a drop that is not drawn out.
/// - radius: corner radius of each end; neck: radius of the bridge between them.
/// - magnification: of the body, at its centre; 1 leaves the content as it is.
/// - lift: 0 for a platter at rest, 1 for the drop fully up. Everything scales with it.
/// - motion: the drop's speed along its way, -1...1. Dispersion grows with it and the
///   light swings with it, as it does on glass that is moving.
/// - darkInk: 1 when the content is dark marks on a light ground.
[[ stitchable ]]
half4 glassLens(float2 position, SwiftUI::Layer layer,
                float4 head, float4 tail, float radius, float neck,
                float magnification, float lift, float motion, float darkInk,
                float4 kA, float4 kB, float4 kC, float4 kD)
{
    // The rim's numbers, from LensTuning: see there for what each is.
    float beadOut = kA.x, rimWidth = kA.y, rimSharp = kA.z, beadIn = kA.w;
    float beadMix = kB.x, beadBlur = kB.y;
    float dispersion = kC.x, straightDisp = kC.z, frostBase = kC.w;
    float frostGain = kD.x, gatherGain = kD.y;
    half4 original = layer.sample(position);
    float4 bounds = float4(min(head.xy, tail.xy), 0.0, 0.0);
    bounds.zw = max(head.xy + head.zw, tail.xy + tail.zw) - bounds.xy;
    float2 halfSize = bounds.zw * 0.5;
    float2 centre = bounds.xy + halfSize;
    float half_ = thickness(head, tail) * 0.5;
    if (lift <= 0.002 || half_ <= 0.5) { return original; }

    DropHit shape = drop(position, head, tail, radius, neck);
    if (shape.dist > 2.5) { return original; }

    float2 normal = shape.outward;
    float2 tangent = float2(-normal.y, normal.x);
    float depth = max(-shape.dist, 0.0);
    bool dark = darkInk > 0.5;

    // An ashtray, not a dome: a low flat floor, and a bead of glass round the rim.
    //
    // The floor is flat, so what is under it only comes a little closer - the labels
    // grow by a tenth and do not slide about as the drop moves. The bead is round, so
    // light crosses it twice: one image of what lies beyond the edge, one of what lies
    // further in, laid over each other. That is why a single bright line under Apple's
    // drop - the ground's own edge - shows up twice near the rim, and why the bead
    // itself is invisible: it has no light of its own, only what it bends, splits and
    // scatters. Two whole images blended, never one folded: folding is what tore text
    // and lines at the ends of the drop.
    float2 offset = position - centre;
    float2 floorAt = centre + offset / magnification;

    // The bead has two walls, and each shows something different. Nearest the edge the
    // outer wall, sloping up and away, shows what lies beyond the drop, squeezed - so
    // the ground under the drop reads a little narrower. Behind it the inner wall,
    // sloping down into the floor, shows what lies further in, drawn outward - which is
    // what makes a line crossing the drop hook outwards at the ends rather than in.
    // Where the two meet is the line that cuts the dark ground inside Apple's drop.
    float outerEnd = rimWidth * 0.4;
    float wallOut = smoothstep(outerEnd, 0.0, depth) * lift;
    float wallIn = smoothstep(outerEnd * 0.5, outerEnd * 1.4, depth)
                 * smoothstep(rimWidth, outerEnd * 1.4, depth) * lift;
    float bead = max(wallOut, wallIn);

    // How much the colours part, and how much the bead scatters what it bends: both
    // grow towards the edge, and the colours part most where the rim curves.
    float2 ext = halfSize - float2(radius);
    float2 away = abs(offset) - ext;
    float cx = ext.x > 0.5 ? smoothstep(0.0, radius * 0.6, away.x) : 1.0;
    float cy = ext.y > 0.5 ? smoothstep(0.0, radius * 0.6, away.y) : 1.0;
    float curved = min(cx, cy);
    float spread = dispersion * bead * mix(straightDisp, 1.0, curved) * (1.0 + 0.4 * abs(motion));
    float frost = (frostBase + frostGain * bead) * lift;
    float scatter = beadBlur * bead;

    // The two faces of the bead, each with its colours parted along the way.
    half3 sumRGB = half3(0.0), sumW = half3(0.0), perChannel = half3(0.0);
    half4 mid = half4(0.0);
    for (int i = 0; i < 7; i++) {
        float t = float(i) / 6.0;
        float f = 1.0 - spread * (1.0 - 2.0 * t);
        half3 w = half3(exp(-pow((t - 0.05) / 0.3, 2.0)), exp(-pow((t - 0.5) / 0.28, 2.0)), exp(-pow((t - 0.95) / 0.3, 2.0)));
        half4 flat_ = frosted(layer, floorAt, normal, tangent, frost);
        half4 outer = frosted(layer, floorAt + normal * beadOut * wallOut * f, normal, tangent, frost + scatter);
        half4 inner = frosted(layer, floorAt - normal * beadIn * wallIn * f, normal, tangent, frost + scatter);
        half4 through = mix(mix(flat_, inner, half(wallIn * beadMix)), outer, half(wallOut));
        sumRGB += through.rgb * w;
        perChannel += through.a * w;
        sumW += w;
        if (i == 3) { mid = through; }
    }
    half3 colour = sumRGB / sumW;
    perChannel /= sumW;
    float pull = bead;

    half coverage = max(perChannel.r, max(perChannel.g, perChannel.b));
    half4 seen;
    if (dark) {
        // Dark marks on a light ground have no colour to split; what parts at a
        // real edge is the light behind them, so each fringe takes the colour
        // that got past the mark.
        half3 ink = mid.a > 0.0 ? mid.rgb / mid.a : half3(0.0);
        seen = half4(half3(coverage) - perChannel * (half3(1.0) - ink), coverage);
    } else {
        seen = half4(colour, coverage);
    }
    // The bevel gathers light: whatever it bends is brighter the nearer the edge.
    if (pull > 0.0 && seen.a > 0.0) {
        half gather = half(1.0 + gatherGain * pull * lift);
        half boosted = min(seen.a * gather, 1.0h);
        seen.rgb = min(seen.rgb * (boosted / seen.a), half3(boosted));
        seen.a = boosted;
    }
    // Marks under the glass read at full strength, as under a system glass thumb;
    // a faint ground under it stays as faint as it was.
    if (seen.a > 0.0) {
        half lifted = min(seen.a * half(1.0 + 0.8 * lift * smoothstep(0.15, 0.5, float(seen.a))), 1.0h);
        seen.rgb = min(seen.rgb * (lifted / seen.a), half3(lifted));
        seen.a = lifted;
    }

    // A crisp edge: glass is not soft at its rim.
    half inside = half(smoothstep(0.6, -0.6, shape.dist));
    return mix(original, seen, inside);
}

/// The light on the drop is next to none, and none of it glows: the edge itself,
/// dark, where the glass is seen side-on, and the faintest line where the bevel
/// folds into the flat. The colour at the rim is the bevel's own, from what it bends.
///
/// A colour effect of its own, over the refracted labels rather than part of
/// them: SwiftUI composites a layer effect's translucent output twice over a band
/// of the layer wherever it is allowed to sample far afield, and the light, all
/// translucent, came out as a bright stripe across the drop.
[[ stitchable ]]
half4 glassLight(float2 position, half4 color, float4 head, float4 tail, float radius, float neck,
                 float lift, float motion, float darkInk, float4 kE)
{
    float half_ = thickness(head, tail) * 0.5;
    if (lift <= 0.002 || half_ <= 0.5) { return half4(0.0); }
    DropHit shape = drop(position, head, tail, radius, neck);
    if (shape.dist > 2.5) { return half4(0.0); }

    bool dark = darkInk > 0.5;
    float depth = max(-shape.dist, 0.0);
    float scale = clamp(half_ / 19.0, 0.55, 1.0);
    float edge = 1.0 - smoothstep(0.55 * kE.x * scale, kE.x * scale, depth);
    // Iridescence: the rim's own reflection, split by wavelength - a fine line along
    // the straight sides, a wider band round the curved ends, its hue turning with
    // the direction of the surface. kE.w sets how much.
    float2 offset = position - (min(head.xy, tail.xy) + (max(head.xy + head.zw, tail.xy + tail.zw) - min(head.xy, tail.xy)) * 0.5);
    float2 halfSize = (max(head.xy + head.zw, tail.xy + tail.zw) - min(head.xy, tail.xy)) * 0.5;
    float2 ext = halfSize - float2(radius);
    float2 away = abs(offset) - ext;
    float cx = ext.x > 0.5 ? smoothstep(0.0, radius * 0.6, away.x) : 1.0;
    float cy = ext.y > 0.5 ? smoothstep(0.0, radius * 0.6, away.y) : 1.0;
    float curved = min(cx, cy);
    float iridWidth = mix(1.6, 4.5, curved) * scale;
    float irid = pow(1.0 - smoothstep(0.0, iridWidth, depth), 1.5) * smoothstep(0.0, 0.7, depth);
    float hue = atan2(shape.outward.y, shape.outward.x) / (2.0 * M_PI_F) * 3.0 + depth / iridWidth;
    half3 iridColour = half3(0.5 + 0.5 * cos(2.0 * M_PI_F * (hue + float3(0.0, 0.33, 0.67))));
    half highlight = half(irid * kE.w * mix(0.35, 1.0, curved) * lift);
    half3 tint = mix(half3(1.0), iridColour, 0.85h);
    half shade = half(edge * (dark ? kE.y : min(kE.y + 0.1, 1.0)) * lift);

    half inside = half(smoothstep(0.6, -0.6, shape.dist));
    return over(half4(tint * highlight, highlight), half4(0.0, 0.0, 0.0, shade)) * inside;
}
