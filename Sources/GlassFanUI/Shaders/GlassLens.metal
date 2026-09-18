#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// A drop of thick glass over the content of a layer, built as the published
// breakdowns of Apple's Liquid Glass describe it: a shape with a bevelled rim,
// refraction through that rim by Snell's law, dispersion in proportion to how
// hard the rim bends, a frosting of what it bends, Fresnel reflection at grazing
// angles, and glare where a fixed light catches the curve.

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

/// Five taps in a small cross, for the frost on the rim.
static half4 frosted(SwiftUI::Layer layer, float2 p, float2 along, float2 across, float spread) {
    if (spread < 0.05) { return layer.sample(p); }
    return (layer.sample(p) * 2.0h
            + layer.sample(p + along * spread) + layer.sample(p - along * spread)
            + layer.sample(p + across * spread) + layer.sample(p - across * spread)) / 6.0h;
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
                float magnification, float lift, float motion, float darkInk)
{
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

    // Body: a shallow dome, most magnified at the centre and a little less out
    // towards the ends, so what is under it bows as it would under a real drop.
    float2 offset = position - centre;
    float2 normalised = offset / halfSize;
    float dome = clamp(dot(normalised, normalised), 0.0, 1.0);
    float mag = mix(magnification, 1.0 + (magnification - 1.0) * 0.5, dome);
    float2 through = centre + offset / mag;

    // Rim: refraction through the bevel. A ray meeting the curved surface bends by
    // Snell's law (glass, n = 1.5); the steeper the surface, the further it lands
    // from where it entered. Sampling from further in makes what is inside the
    // drop wrap out across its rim.
    float bevel = min(half_ * 0.95, 18.0);
    float bendAmount = 0.0;
    if (depth < bevel) {
        float steepness = 1.0 - depth / bevel;
        float incident = asin(clamp(steepness, 0.0, 0.9995));
        float transmitted = asin(sin(incident) / 1.5);
        bendAmount = tan(incident - transmitted);        // 0 where flat, ~1.1 at the rim
    }
    float reach = bevel * 0.8 * lift;
    float2 bend = -normal * bendAmount * reach;

    // Dispersion: each colour bends by its own amount, so the colours part where
    // the rim bends hardest, and part further while the drop moves.
    float spread = 0.09 + 0.12 * abs(motion);
    float frost = bendAmount * 1.4 * lift;
    half4 red   = frosted(layer, through + bend * (1.0 - spread), normal, tangent, frost);
    half4 green = frosted(layer, through + bend,                  normal, tangent, frost);
    half4 blue  = frosted(layer, through + bend * (1.0 + spread), normal, tangent, frost);

    half coverage = max(green.a, max(red.a, blue.a));
    half4 seen;
    if (dark) {
        // Dark marks on a light ground have no colour to split; what parts at a
        // real edge is the light behind them, so each fringe takes the colour
        // that got past the mark.
        half3 ink = green.a > 0.0 ? green.rgb / green.a : half3(0.0);
        half3 perChannel = half3(red.a, green.a, blue.a);
        seen = half4(half3(coverage) - perChannel * (half3(1.0) - ink), coverage);
    } else {
        seen = half4(red.r, green.g, blue.b, coverage);
    }
    // What is under the glass reads at full strength, as under a system glass thumb.
    if (seen.a > 0.0) {
        half lifted = min(seen.a * half(1.0 + 0.8 * lift), 1.0h);
        seen.rgb = min(seen.rgb * (lifted / seen.a), half3(lifted));
        seen.a = lifted;
    }

    // Fresnel: towards the rim, where the surface is seen at a grazing angle, the
    // glass turns into a mirror and shows what lies beside it outside - flipped,
    // as a reflection is.
    float grazing = pow(1.0 - clamp(depth / (bevel * 0.75), 0.0, 1.0), 2.2);
    half4 reflected = frosted(layer, position + normal * (2.0 * depth + 2.0), normal, tangent, 0.8);
    seen = over(seen, reflected * half(grazing * 0.5 * lift));

    // A soft edge rather than a cut one.
    half inside = half(smoothstep(1.2, -1.2, shape.dist));
    return mix(original, seen, inside);
}

/// The light on the drop: glare where a fixed light from above left catches the
/// curve facing it and, more faintly, the opposite curve where it leaves the glass;
/// a bright edge where the glass is seen at a grazing angle; and the curve turned
/// away from the light a shade darker, which is what gives the rim its thickness.
/// The light swings a little as the drop moves.
///
/// A colour effect of its own, over the refracted labels rather than part of
/// them: SwiftUI composites a layer effect's translucent output twice over a band
/// of the layer wherever it is allowed to sample far afield, and the light, all
/// translucent, came out as a bright stripe across the drop.
[[ stitchable ]]
half4 glassLight(float2 position, half4 color, float4 head, float4 tail, float radius, float neck,
                 float lift, float motion, float darkInk)
{
    float half_ = thickness(head, tail) * 0.5;
    if (lift <= 0.002 || half_ <= 0.5) { return half4(0.0); }
    DropHit shape = drop(position, head, tail, radius, neck);
    if (shape.dist > 2.5) { return half4(0.0); }

    bool dark = darkInk > 0.5;
    float depth = max(-shape.dist, 0.0);
    float bevel = min(half_ * 0.95, 18.0);

    float angle = (-135.0 + 28.0 * clamp(motion, -1.0, 1.0)) * M_PI_F / 180.0;
    float2 light = float2(cos(angle), sin(angle));
    float facing = dot(shape.outward, light);
    // Drawn out, the drop is thin, and a band sized to its thickness would glaze it
    // over from rim to rim; the light keeps to its edges instead.
    float reach = bevel * (any(head != tail) ? 0.45 : 0.7);
    float band = pow(1.0 - clamp(depth / reach, 0.0, 1.0), 1.8);
    float glare = (pow(max(facing, 0.0), 1.6) + 0.55 * pow(max(-facing, 0.0), 2.0)) * band;
    float edgeLight = pow(1.0 - clamp(depth / 3.0, 0.0, 1.0), 2.0) * (dark ? 0.6 : 0.55);
    half highlight = half(clamp((glare * (dark ? 0.8 : 1.15) + edgeLight) * lift, 0.0, 0.95));
    half shade = half(max(-facing, 0.0) * band * (dark ? 0.10 : 0.22) * lift);

    half inside = half(smoothstep(1.2, -1.2, shape.dist));
    half4 lit = over(half4(half3(highlight), highlight), half4(0.0, 0.0, 0.0, shade)) * inside;

    // On a light ground a clear drop needs its outline to be seen at all: a faint
    // darkening just across the rim, not a line.
    if (dark) {
        half outline = half(pow(1.0 - clamp(abs(shape.dist + 0.3) / 1.8, 0.0, 1.0), 2.0) * 0.2 * lift);
        lit = over(lit, half4(0.0, 0.0, 0.0, outline));
    }
    return lit;
}
