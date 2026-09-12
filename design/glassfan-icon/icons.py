"""SVG builders for the GlassFan icon, glyph and in-app dial. Every id carries a
per-instance suffix: several of these SVGs share one document on an artboard,
and duplicate ids in inline SVG resolve to whichever came first."""
import math
from fan_geometry import DIRECTIONS, blade_d

BLADE = "#cfe5ff"      # Palette.blade, dark
CALM = "#3987e5"       # Palette.calm, dark
AQUA = "#199e70"       # Palette.series[2], dark

def orientation(name):
    """Turn the set so a blade's mid-length sits on the vertical axis - that is
    what makes a swept, odd-looking star read as balanced."""
    p = DIRECTIONS[name]
    return -math.degrees(p["sweep"]) * 0.55

def blade_defs(name, u):
    p = DIRECTIONS[name]
    d = blade_d(name)
    off = orientation(name)
    uses = "".join(f'<use href="#pb-{u}" transform="rotate({off + i * 360 / p["count"]:.2f})"/>'
                   for i in range(p["count"]))
    return f'<path id="pb-{u}" d="{d}"/><g id="bl-{u}">{uses}</g>'

def wake(name, u, strength, span_frac=0.62, ghosts=16, blur=1.6, color=BLADE):
    """Copies of the blades turned back against the spin, fading - the air a
    blade drags lies behind it only. Negative rotation is counter-clockwise, and
    the disc spins clockwise, so these all fall on the trailing side."""
    p = DIRECTIONS[name]
    pitch = 360 / p["count"]
    uses = []
    for k in range(1, ghosts + 1):
        f = k / ghosts
        a = strength * (1 - f) ** 1.6
        uses.append(f'<use href="#bl-{u}" transform="rotate({-f * pitch * span_frac:.3f})" '
                    f'fill="{color}" opacity="{a:.3f}"/>')
    return (f'<g mask="url(#wm-{u})" filter="url(#wb-{u})">{"".join(uses)}</g>')

def wake_defs(name, u, blur=1.6):
    hub = DIRECTIONS[name]["hub"]
    inner = hub / 100
    return (f'<filter id="wb-{u}" x="-20%" y="-20%" width="140%" height="140%">'
            f'<feGaussianBlur stdDeviation="{blur}"/></filter>'
            f'<radialGradient id="wg-{u}" gradientUnits="userSpaceOnUse" cx="0" cy="0" r="110">'
            f'<stop offset="0" stop-color="#000"/><stop offset="{inner * 0.92:.3f}" stop-color="#000"/>'
            f'<stop offset="{inner * 1.25:.3f}" stop-color="#fff"/><stop offset="1" stop-color="#fff"/></radialGradient>'
            f'<mask id="wm-{u}" maskUnits="userSpaceOnUse" x="-120" y="-120" width="240" height="240">'
            f'<rect x="-120" y="-120" width="240" height="240" fill="url(#wg-{u})"/></mask>')

def hub(name, u, fill_light="#f5f8ff", fill_dark="#c7d6ee", ring="#ffffff", ring_a=0.7, cap_detail=True):
    r = DIRECTIONS[name]["hub"]
    s = (f'<radialGradient id="hg-{u}" cx="0.38" cy="0.32" r="0.9">'
         f'<stop offset="0" stop-color="{fill_light}"/><stop offset="1" stop-color="{fill_dark}"/></radialGradient>')
    body = f'<circle r="{r}" fill="url(#hg-{u})"/>'
    if cap_detail:
        body += (f'<circle r="{r * 0.46:.2f}" fill="none" stroke="#0b1226" stroke-opacity="0.16" stroke-width="{r * 0.06:.2f}"/>'
                 f'<circle r="{r:.2f}" fill="none" stroke="{ring}" stroke-opacity="{ring_a}" stroke-width="0.9"/>')
    return s, body

def icon_svg(name, size, u, show_wake=True):
    p = DIRECTIONS[name]
    hub_defs, hub_body = hub(name, u)
    scale = 3.5
    wake_part = wake(name, u, 0.34) if show_wake else ""
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="{size}" height="{size}" style="display: block">
<defs>
<clipPath id="tc-{u}"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>
<linearGradient id="bg-{u}" x1="0" y1="0" x2="1" y2="1">
<stop offset="0" stop-color="#1a2b52"/><stop offset="0.55" stop-color="#0c1227"/><stop offset="1" stop-color="#150f2c"/></linearGradient>
<filter id="sf-{u}" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="80"/></filter>
<linearGradient id="gl-{u}" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="#fff" stop-opacity="0.17"/><stop offset="0.5" stop-color="#fff" stop-opacity="0.05"/><stop offset="1" stop-color="#fff" stop-opacity="0.09"/></linearGradient>
<linearGradient id="rm-{u}" x1="0.2" y1="0" x2="0.5" y2="1">
<stop offset="0" stop-color="#fff" stop-opacity="0.85"/><stop offset="0.35" stop-color="#fff" stop-opacity="0.2"/><stop offset="0.75" stop-color="#fff" stop-opacity="0.1"/><stop offset="1" stop-color="#fff" stop-opacity="0.32"/></linearGradient>
<radialGradient id="bf-{u}" gradientUnits="userSpaceOnUse" cx="0" cy="0" r="100">
<stop offset="0.25" stop-color="#ffffff"/><stop offset="1" stop-color="#dbe7fb"/></radialGradient>
<filter id="lf-{u}" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="3.2" stdDeviation="4.5" flood-color="#030612" flood-opacity="0.55"/></filter>
{wake_defs(name, u)}
{hub_defs}
{blade_defs(name, u)}
</defs>
<g clip-path="url(#tc-{u})">
<rect x="100" y="100" width="824" height="824" fill="url(#bg-{u})"/>
<circle cx="700" cy="740" r="300" fill="{CALM}" opacity="0.6" filter="url(#sf-{u})"/>
<circle cx="290" cy="250" r="210" fill="{AQUA}" opacity="0.28" filter="url(#sf-{u})"/>
<rect x="100" y="100" width="824" height="824" fill="url(#gl-{u})"/>
<ellipse cx="512" cy="120" rx="470" ry="170" fill="#fff" opacity="0.08" filter="url(#sf-{u})"/>
<g transform="translate(512 512) scale({scale})">
{wake_part}
<g filter="url(#lf-{u})"><use href="#bl-{u}" fill="url(#bf-{u})"/>{hub_body}</g>
</g>
</g>
<rect x="101.5" y="101.5" width="821" height="821" rx="183.5" fill="none" stroke="url(#rm-{u})" stroke-width="3"/>
</svg>'''

def glyph_svg(name, size, u, color, hub_color, show_wake=False, wake_strength=0.34):
    p = DIRECTIONS[name]
    r = p["hub"]
    w = wake(name, u, wake_strength, color=color) if show_wake else ""
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="-110 -110 220 220" width="{size}" height="{size}" style="display: block">
<defs>{wake_defs(name, u)}{blade_defs(name, u)}</defs>
{w}<use href="#bl-{u}" fill="{color}"/><circle r="{r}" fill="{color}"/>
<circle r="{r * 0.46:.2f}" fill="none" stroke="{hub_color}" stroke-opacity="0.22" stroke-width="{r * 0.07:.2f}"/>
</svg>'''

def dial_parts(name, size, u, rpm, max_rpm=5348.0, controlled=True, show_value=True):
    """The overview dial as the app draws it - track, speed arc, number - and,
    separately, the turning layer, so an artboard can spin only that."""
    c = size / 2
    lw = size * 0.023
    rr = c - lw / 2
    circ = 2 * math.pi * rr
    frac = min(max(rpm / max_rpm, 0), 1)
    track = f'<circle cx="{c}" cy="{c}" r="{rr:.2f}" fill="none" stroke="#fff" stroke-opacity="0.09" stroke-width="{lw:.2f}" stroke-linecap="round" stroke-dasharray="{0.75 * circ:.2f} {circ:.2f}" transform="rotate(135 {c} {c})"/>'
    arc = ""
    if frac > 0:
        arc = (f'<circle cx="{c}" cy="{c}" r="{rr:.2f}" fill="none" stroke="url(#ag-{u})" stroke-width="{lw:.2f}" stroke-linecap="round" '
               f'stroke-dasharray="{0.75 * frac * circ:.2f} {circ:.2f}" transform="rotate(135 {c} {c})"/>')
    static = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" width="{size}" height="{size}" style="position: absolute; left: 0; top: 0">
<defs><linearGradient id="ag-{u}" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="{CALM}"/><stop offset="1" stop-color="{AQUA}"/></linearGradient></defs>
{track}{arc}</svg>'''
    spinning = rpm > 0
    tint = BLADE if controlled else "#ffffff"
    ink = 0.16 if spinning else 0.07
    tip = size * 0.348
    k = tip / 100
    p = DIRECTIONS[name]
    turning = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" width="{size}" height="{size}" style="display: block">
<defs>{wake_defs(name, u, blur=1.4)}{blade_defs(name, u)}</defs>
<g transform="translate({c} {c}) scale({k:.4f})" opacity="{ink}">
{wake(name, u, 0.9, color=tint) if spinning else ""}
<use href="#bl-{u}" fill="{tint}"/><circle r="{p["hub"]}" fill="{tint}"/>
</g></svg>'''
    return static, turning, spinning
