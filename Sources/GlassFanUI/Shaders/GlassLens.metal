#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Signed distance from `p` to a horizontal capsule: negative inside, zero on the rim.
static float capsuleDistance(float2 p, float2 centre, float2 halfSize) {
    float2 d = abs(p - centre);
    d.x = max(d.x - (halfSize.x - halfSize.y), 0.0);
    return length(d) - halfSize.y;
}

/// What a drop of clear glass shows of the content under it.
///
/// Magnified evenly through its straight middle, the view bends back towards the
/// unmagnified world across the round ends and the very top and bottom - where a
/// thick lens refracts hardest - so the letters under the rim meet the letters
/// outside it with no gap and no seam. Towards the rim the colour channels come apart slightly, as light does
/// through a glass edge, and what is under the glass is lifted towards full
/// strength, the way the labels under a system glass thumb read.
///
/// - lens: x, y, width, height of the drop, in the layer's coordinates.
/// - magnification: 1 leaves the content as it is.
/// - brighten: how much to lift what is under the glass; 1 leaves it.
/// - fringe: how far the colour channels part at the rim, as a fraction of scale.
[[ stitchable ]]
half4 glassLens(float2 position, SwiftUI::Layer layer,
                float4 lens, float magnification, float brighten, float fringe)
{
    float2 halfSize = lens.zw * 0.5;
    float2 centre = lens.xy + halfSize;
    float dist = capsuleDistance(position, centre, halfSize);
    half4 original = layer.sample(position);
    if (dist >= 1.0 || magnification <= 1.001 || halfSize.y <= 0.0) {
        return original;
    }

    float2 offset = position - centre;
    float2 reach = abs(offset);
    // How far in from the ends, over half again the end cap's radius: 0 at the
    // tip, 1 once past the curve. Along the straight middle the view is magnified evenly, so
    // the words there read straight; the bending happens in the round ends, as
    // it does in a real drop.
    float along = smoothstep(0.0, 1.0, clamp((halfSize.x - reach.x) / (halfSize.y * 1.5), 0.0, 1.0));
    // How far in from the top and bottom edges, over the outer third of the height.
    float across = smoothstep(0.0, 1.0, clamp((halfSize.y - reach.y) / (halfSize.y * 0.33), 0.0, 1.0));

    float inverse = 1.0 / magnification;
    float2 scale = float2(mix(1.0, inverse, along), mix(1.0, inverse, along * across));

    // Colour parts only where the glass curves.
    float split = fringe * (1.0 - along * across);
    half4 green = layer.sample(centre + offset * scale);
    half4 red   = layer.sample(centre + offset * scale * (1.0 + split));
    half4 blue  = layer.sample(centre + offset * scale * (1.0 - split));
    half4 seen = half4(red.r, green.g, blue.b, max(green.a, max(red.a, blue.a)));

    // Lift towards full strength, keeping colour premultiplied by the new alpha.
    if (seen.a > 0.0) {
        half lifted = min(seen.a * half(brighten), half(1.0));
        seen.rgb = min(seen.rgb * (lifted / seen.a), half3(lifted));
        seen.a = lifted;
    }

    // Anti-aliased rim.
    half inside = half(clamp(0.5 - dist, 0.0, 1.0));
    return mix(original, seen, inside);
}
