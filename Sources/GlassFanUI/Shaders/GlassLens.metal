#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// A drop of glass over the content of a layer, built part by part from Apple's own -
// the segmented control's drop in Activity Monitor, read off fifteen held frames and
// fitted to them. Down a column through its straight side, from the edge in:
//
//   a dark hairline;
//   a thin line of colour - what lies ~4pt further in, pulled out to the rim, its
//   channels parted, softer and wider round the ends;
//   the ground in place, seen through glass that dims it (L' = 0.62 L + 26 levels);
//   and, where the drop stands over a track, the track's own band 1-3pt inside its
//   edge showing what lies beyond that edge - which is why the track looks narrower
//   inside the drop. That band belongs to the track, not to the drop: it stays in the
//   same place as the drop's outline moves. A list's rows are tracks too, each its own.
//
// The body does not refract. Labels under the drop come out a tenth bigger about their
// own middles, and only well inside the track, so the track's rounded ends stay round.
// The outline is SwiftUI's continuous rounded shape, and the rim is sampled four times
// a pixel, so the pulled-in line does not step along a curve. LensTuning holds every
// number.

struct DropHit {
    float dist;       // signed distance to the rim: negative inside
    float2 outward;   // unit normal of the rim, pointing out
};

/// A rectangle with rounded corners, the continuous kind SwiftUI draws; `box` is x,
/// y, width, height.
///
/// A continuous corner leaves each straight edge a little before a circular one would
/// and sits inside it until just past where the arc would have begun: 1.4% of the
/// radius at most, a Gaussian in the distance past that point, measured off SwiftUI's
/// own paths for a capsule and for a 14pt corner alike - and off Apple's drop, which
/// is SwiftUI's capsule to a tenth of a point. An edge of no length (a capsule's ends)
/// has none.
static float roundBox(float2 p, float4 box, float radius) {
    float2 halfSize = box.zw * 0.5;
    float2 centre = box.xy + halfSize;
    float r = min(radius, min(halfSize.x, halfSize.y));
    float2 a = abs(p - centre);
    float2 q = a - halfSize + r;
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    float2 u = (a - (halfSize - r)) / max(r, 1e-3) - 0.13;
    float2 s = select(float2(0.26), float2(0.2), u < 0.0);
    float2 bump = exp(-(u / s) * (u / s));
    float2 edge = smoothstep(0.0, 0.3 * r, halfSize - r);
    return d + 0.0142 * r * (bump.x * edge.x + bump.y * edge.y);
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


/// A small blur: five taps in a cross while slight, the middle and eight round a
/// circle once it passes a third of a point - a cross that wide leaves a plus of ghosts.
static half4 softened(SwiftUI::Layer layer, float2 p, float amount) {
    if (amount < 0.05) { return layer.sample(p); }
    if (amount < 0.3) {
        return layer.sample(p) * 0.36h
             + (layer.sample(p + float2(amount, 0)) + layer.sample(p - float2(amount, 0))
              + layer.sample(p + float2(0, amount)) + layer.sample(p - float2(0, amount))) * 0.16h;
    }
    half4 sum = layer.sample(p) * 0.2h;
    for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.785398 + 0.3927;
        sum += layer.sample(p + amount * float2(cos(a), sin(a))) * 0.1h;
    }
    return sum;
}

/// The numbers, unpacked once: see LensTuning for what each is.
struct Rim {
    float shadowDark, shadowAt, shadowWidth, shadowUp;
    float innerShade, innerAt, innerWidth, innerBottom;
    float lineAt, lineReach, lineWidth, rbShift;
    float bandFrom, bandTo, bandReach, ledgeLift;
    float capPull, bodyAt, endSpread;
    float edgeDark, lineGain, ledgeChroma, ledgeGain;
    float endReach, rbBlur, blurDepth, endGlass;
    float endBlur, lineSpread, endWidth, endChroma;
};

static Rim unpack(float4 kA, float4 kB, float4 kC, float4 kD, float4 kE, float4 kF, float4 kG, float4 kH) {
    Rim k;
    k.shadowDark = kG.x; k.shadowAt = kG.y; k.shadowWidth = max(kG.z, 0.3); k.shadowUp = kG.w;
    k.innerShade = kH.x; k.innerAt = kH.y; k.innerWidth = max(kH.z, 0.3); k.innerBottom = kH.w;
    k.lineAt = kA.x; k.lineReach = kA.y; k.lineWidth = max(kA.z, 0.1); k.rbShift = kA.w;
    k.bandFrom = kB.x; k.bandTo = kB.y; k.bandReach = kB.z; k.ledgeLift = kB.w;
    k.capPull = kC.y; k.bodyAt = kC.z; k.endSpread = kC.w;
    k.edgeDark = kD.x; k.lineGain = kD.y; k.ledgeChroma = kD.z; k.ledgeGain = kD.w;
    k.endReach = kE.x; k.rbBlur = kE.y; k.blurDepth = max(kE.z, 0.1); k.endGlass = kE.w;
    k.endBlur = kF.x; k.lineSpread = kF.y; k.endWidth = max(kF.z, 0.2); k.endChroma = kF.w;
    return k;
}

/// How far inside the nearest of the tracks (x, y, width, height, four floats each) the
/// point is - negative outside all of them - and which one that is.
static float insideTracks(float2 p, device const float *tracks, int floats, float radius, thread float4 &nearest) {
    float best = -1000.0;
    for (int i = 0; i + 3 < floats; i += 4) {
        float4 box = float4(tracks[i], tracks[i + 1], tracks[i + 2], tracks[i + 3]);
        if (box.z <= 0.0) { continue; }
        float within = -roundBox(p, box, radius);
        if (within > best) { best = within; nearest = box; }
    }
    return best;
}

/// The drop at one point: what the glass shows there.
static half4 lensAt(float2 position, SwiftUI::Layer layer,
                    float4 head, float4 tail, float radius, float neck,
                    float magnification, float lift, float motion, Rim k,
                    device const float *tracks, int trackFloats, float trackRadius,
                    device const float *anchors, int anchorCount) {
    DropHit shape = drop(position, head, tail, radius, neck);
    float d = shape.dist;
    if (d > 1.0) { return layer.sample(position); }

    float4 bounds = float4(min(head.xy, tail.xy), 0.0, 0.0);
    bounds.zw = max(head.xy + head.zw, tail.xy + tail.zw) - bounds.xy;
    float2 halfSize = bounds.zw * 0.5;
    float2 centre = bounds.xy + halfSize;
    float2 p = position - centre;
    float r = min(radius, thickness(head, tail) * 0.5);

    float2 normal = shape.outward;
    float depth = max(-d, 0.0);
    // How far into a rounded end or corner: 0 along a straight side.
    float2 ext = halfSize - float2(r);
    float2 away = abs(p) - ext;
    float cx = ext.x > 0.5 ? smoothstep(0.0, r * 0.5, away.x) : 1.0;
    float cy = ext.y > 0.5 ? smoothstep(0.0, r * 0.5, away.y) : 1.0;
    float capness = min(cx, cy);
    // The share of the rim's normal across the drop's length: 1 facing up or down on
    // a wide drop, 0 at the tips of its ends.
    float across = ext.x >= ext.y ? abs(normal.y) : abs(normal.x);

    // Outside the outline only the hairline's tail reaches: no lift, no parted colours.
    float inside = smoothstep(0.25, -0.25, d);
    float reach = lift * inside;

    float u = (depth - k.lineAt) / (k.lineWidth * mix(1.0, k.endWidth, capness));
    float line = max(1.0 - u * u, 0.0);
    float body = smoothstep(k.bodyAt - 0.5, k.bodyAt, depth);
    float t = clamp(depth / 4.5, 0.0, 1.0);
    float cap = clamp(k.capPull, -1.98, 1.98) * (1.0 - t) * (1.0 - t);
    float rimW = smoothstep(k.blurDepth, 0.0, depth);

    // The track's band, and how far inside the track the labels grow.
    float band = 0.0, grows = 1.0;
    float2 outward = float2(0.0);
    float4 track = float4(0.0);
    float within = insideTracks(position, tracks, trackFloats, trackRadius, track);
    if (track.z > 0.0) {
        // Measured on a dark track only: on a light one the band would show the light
        // ground beyond the edge as bright lines, so there it is left out.
        band = smoothstep(k.bandFrom - 0.25, k.bandFrom + 0.25, within)
             * (1.0 - smoothstep(k.bandTo - 0.25, k.bandTo + 0.25, within));
        const float e = 0.5;
        float2 slope = float2(roundBox(position + float2(e, 0), track, trackRadius) - roundBox(position - float2(e, 0), track, trackRadius),
                              roundBox(position + float2(0, e), track, trackRadius) - roundBox(position - float2(0, e), track, trackRadius));
        outward = normalize(slope + float2(1e-6, 0.0)) * k.bandReach * band;
        grows = smoothstep(3.0, 6.0, within);
    }
    // Labels grow about their own middles: the nearest anchor, or the drop's.
    float anchorX = centre.x;
    for (int i = 0; i < anchorCount; i++) {
        if (i == 0 || abs(anchors[i] - position.x) < abs(anchorX - position.x)) { anchorX = anchors[i]; }
    }
    float2 anchor = float2(anchorX, centre.y) - centre;
    float grow = mix(1.0, magnification, grows);
    float2 grown = anchor + (p - anchor) / grow;

    float lobeReach = k.lineReach * mix(1.0, mix(k.endReach, 1.0, across), capness) * line;
    float spread = (k.lineSpread + k.endSpread * capness) * (1.0 + 0.4 * abs(motion));
    float2 at[3];
    for (int c = 0; c < 3; c++) {
        float s = float(c - 1);                                   // red -1, green 0, blue +1
        float lobe = lobeReach * (1.0 + s * spread);
        float rb = (c == 1 ? 0.0 : 1.0) * k.rbShift * rimW;
        float2 rimAt = p - normal * (lobe + rb - s * k.ledgeChroma);
        float2 capAt = grown - normal * (lobe + rb + cap * (1.0 + s * spread) - s * k.endChroma * rimW);
        float2 here = mix(mix(rimAt, grown, body), capAt, capness) + outward;
        at[c] = centre + mix(p, here, reach);
    }
    float rim = rimW * reach;
    float blur = 0.18 * line * reach + k.endBlur * capness * rim;
    float rbSoft = blur + k.rbBlur * rim;
    half4 g = softened(layer, at[1], blur);
    half3 colour = half3(softened(layer, at[0], rbSoft).r, g.g, softened(layer, at[2], rbSoft).b);
    half coverage = g.a;

    colour *= half(1.0 + (k.lineGain - 1.0) * line * lift);
    // The glass round the rim: on dark ground it dims and lifts what it covers
    // (L' = 0.63 L + 25 levels), on light it leaves it as it is - the tuning for each.
    float glass = max((1.0 - body) * mix(1.0, k.endGlass, capness), band) * reach;
    colour = mix(colour, colour * half(k.ledgeGain) + half(k.ledgeLift) * coverage, half(glass));
    // Inside, a darkening under the top edge and a touch of light under the bottom one.
    float innerAt = (depth - k.innerAt) / k.innerWidth;
    colour *= half(1.0 - k.innerShade * exp(-innerAt * innerAt)
                   * mix(k.innerBottom, 1.0, smoothstep(0.3, -0.3, normal.y)) * reach);
    // The hairline and the shadow are glassLight's: past the track there is nothing in
    // this layer for them to darken.
    return half4(colour, coverage);
}

/// - head, tail: x, y, width, height of the drop's two ends in the layer's
///   coordinates; the same box twice for a drop that is not drawn out.
/// - radius: corner radius of each end; neck: radius of the bridge between them.
/// - magnification: how much bigger labels come out under the drop, eased in with the lift.
/// - lift: 0 for a platter at rest, 1 for the drop fully up. Everything scales with it.
/// - motion: the drop's speed along its way, -1...1; the colours part further with it.
/// - darkInk: 1 when the content is dark marks on a light ground (the tuning differs;
///   the shader no longer does).
/// - tracks, trackRadius: the tracks under the drop (x, y, width, height each) and their
///   corner radius - a segmented control's one, a list's rows - for the band inside
///   their edges and to keep labels growing only well inside them. None for none.
/// - anchors: the middles of the labels along x, which grow about them; none for the
///   drop's own middle.
[[ stitchable ]]
half4 glassLens(float2 position, SwiftUI::Layer layer,
                float4 head, float4 tail, float radius, float neck,
                float magnification, float lift, float motion, float darkInk,
                float4 kA, float4 kB, float4 kC, float4 kD, float4 kE, float4 kF, float4 kG, float4 kH,
                device const float *tracks, int trackFloats, float trackRadius,
                device const float *anchors, int anchorCount)
{
    if (lift <= 0.002 || thickness(head, tail) <= 1.0) { return layer.sample(position); }
    Rim k = unpack(kA, kB, kC, kD, kE, kF, kG, kH);
    float d = dropDist(position, head, tail, radius, neck);
    if (d > 1.5) { return layer.sample(position); }
    float4 nearest = float4(0.0);
    float within = insideTracks(position, tracks, trackFloats, trackRadius, nearest);
    // One sample where nothing changes fast: deep in the body away from the track's
    // band, and in the shadow outside.
    bool calm = (d < -max(k.bodyAt, k.blurDepth) - 1.0 && (within < k.bandFrom - 1.0 || within > k.bandTo + 1.0))
             || d > 1.5;
    if (calm) {
        return lensAt(position, layer, head, tail, radius, neck, magnification, lift, motion, k,
                      tracks, trackFloats, trackRadius, anchors, anchorCount);
    }
    // Four, on a rotated grid across a 2x pixel.
    const float2 offsets[4] = { float2(-0.0625, -0.1875), float2(0.1875, -0.0625),
                                float2(0.0625, 0.1875), float2(-0.1875, 0.0625) };
    half4 sum = half4(0.0h);
    for (int i = 0; i < 4; i++) {
        sum += lensAt(position + offsets[i], layer, head, tail, radius, neck, magnification, lift, motion, k,
                      tracks, trackFloats, trackRadius, anchors, anchorCount);
    }
    return sum * 0.25h;
}

/// Over the drop and round it, dark only: the hairline at the outline and the shadow
/// the lifted drop casts - darkest a few points out and mostly below it, 13 levels on
/// white, a level or two on dark. Drawn as black over whatever is there, content or
/// window, because where the drop stands past its track the lens's own layer is empty
/// and has nothing to darken.
///
/// kE = edgeDark; kF = shadowDark, shadowAt, shadowWidth, shadowUp (see LensTuning).
static float glassShade(float2 p, float4 head, float4 tail, float radius, float neck, float lift, float4 kE, float4 kF) {
    DropHit shape = drop(p, head, tail, radius, neck);
    float d = shape.dist;
    float hair = (d + 0.25) / 0.4;
    float edge = kE.x * exp(-hair * hair);
    float at = (d - kF.y) / max(kF.z, 0.3);
    float shadow = kF.x * exp(-at * at) * mix(kF.w, 1.0, max(shape.outward.y, 0.0)) * smoothstep(-0.25, 0.25, d);
    return (1.0 - (1.0 - edge) * (1.0 - shadow)) * lift;
}

[[ stitchable ]]
half4 glassLight(float2 position, half4 color, float4 head, float4 tail, float radius, float neck,
                 float lift, float motion, float darkInk, float4 kE, float4 kF)
{
    if (lift <= 0.002 || thickness(head, tail) <= 1.0) { return half4(0.0); }
    float d = dropDist(position, head, tail, radius, neck);
    if (d > kF.y + 2.5 * max(kF.z, 0.3) || d < -1.5) { return half4(0.0); }
    float shade;
    if (abs(d + 0.25) < 1.2) {
        // Four samples across the hairline, which is under a pixel wide.
        shade = 0.25 * (glassShade(position + float2(-0.0625, -0.1875), head, tail, radius, neck, lift, kE, kF)
                      + glassShade(position + float2(0.1875, -0.0625), head, tail, radius, neck, lift, kE, kF)
                      + glassShade(position + float2(0.0625, 0.1875), head, tail, radius, neck, lift, kE, kF)
                      + glassShade(position + float2(-0.1875, 0.0625), head, tail, radius, neck, lift, kE, kF));
    } else {
        shade = glassShade(position, head, tail, radius, neck, lift, kE, kF);
    }
    return half4(0.0h, 0.0h, 0.0h, half(shade));
}
