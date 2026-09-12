"""Parametric fan blades. One definition feeds the design canvas and, later,
the Swift drawing: radius R=100 at the tips, centre at 0,0, angle 0 straight up,
positive angles clockwise on screen - the direction the app spins the disc."""
import math

def blade_points(r0, sweep, width, tip_blunt, root_frac, sweep_pow=1.5, n=26):
    lead, trail = [], []
    for i in range(n + 1):
        u = i / n
        t = 1 - (1 - u) ** 2                       # denser near the tip
        r = (r0 + t * (1 - r0)) * 100
        phi = sweep * t ** sweep_pow               # centreline angle; negative = tip lags
        hw = width * (1 - t) ** tip_blunt * (root_frac + (1 - root_frac) * 1.35 * t)
        dth = hw / max(r, 1e-6)
        for pts, sign in ((lead, 1), (trail, -1)):
            th = phi + sign * dth
            pts.append((r * math.sin(th), -r * math.cos(th)))
    return trail + lead[::-1][1:]

def smooth_path(pts):
    """Catmull-Rom through the points as cubic Beziers; closed with a straight
    line at the root, which the hub cap hides."""
    f = lambda p: f"{p[0]:.1f},{p[1]:.1f}"
    d = [f"M{f(pts[0])}"]
    n = len(pts)
    for i in range(n - 1):
        p0 = pts[max(i - 1, 0)]; p1 = pts[i]; p2 = pts[i + 1]; p3 = pts[min(i + 2, n - 1)]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d.append(f"C{f(c1)} {f(c2)} {f(p2)}")
    d.append("Z")
    return " ".join(d)

DIRECTIONS = {
    # name: count, r0, sweep (rad), width, tip bluntness, root fraction, hub radius
    "swept":    dict(count=6, r0=0.24, sweep=-0.62, width=18, tip_blunt=0.32, root_frac=0.45, hub=27),
    "impeller": dict(count=9, r0=0.36, sweep=-0.95, width=10, tip_blunt=0.30, root_frac=0.55, hub=38, sweep_pow=1.15),
    "four":     dict(count=4, r0=0.20, sweep=0.0,   width=30, tip_blunt=0.42, root_frac=0.28, hub=23),
}

def blade_d(name):
    p = DIRECTIONS[name]
    return smooth_path(blade_points(p["r0"], p["sweep"], p["width"], p["tip_blunt"], p["root_frac"],
                                    p.get("sweep_pow", 1.5)))

if __name__ == "__main__":
    for k in DIRECTIONS:
        print(k, len(blade_d(k)), "chars")
