#!/usr/bin/env swift
// Generates AppIcon.icns. Kept as a script so the icon is reproducible rather than a
// binary blob nobody can regenerate.
//
// Direction A from the icon canvas: six swept blades and
// the wake they drag, on a pane of glass that is the whole tile. Drawn in the
// canvas's own 1024-unit, y-down space, so every number below is the number on
// the canvas. The blade formula is a copy of GlassFanUI's FanGeometry - change
// one, change both.
import AppKit
import CoreImage

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconset = URL(fileURLWithPath: "build/GlassFan.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// MARK: Blade geometry (mirror of FanGeometry)

enum Blade {
    static let count = 6, root = 0.24, sweep = -0.62, sweepPower = 1.5
    static let width = 0.18, tipBluntness = 0.32, rootFraction = 0.45, hub = 0.27
    static let orientation = -sweep * 0.55

    static func outline(samples: Int = 26) -> [CGPoint] {
        var lead: [CGPoint] = [], trail: [CGPoint] = []
        for i in 0...samples {
            let u = Double(i) / Double(samples)
            let t = 1 - (1 - u) * (1 - u)
            let r = root + t * (1 - root)
            let phi = sweep * pow(t, sweepPower)
            let half = width * pow(1 - t, tipBluntness) * (rootFraction + (1 - rootFraction) * 1.35 * t)
            let dth = half / r
            lead.append(CGPoint(x: r * sin(phi + dth), y: -r * cos(phi + dth)))
            trail.append(CGPoint(x: r * sin(phi - dth), y: -r * cos(phi - dth)))
        }
        return trail + lead.reversed().dropFirst()
    }

    static func path(centre: CGPoint, radius: CGFloat, turn: Double = 0) -> CGPath {
        let blade = CGMutablePath()
        let pts = outline()
        blade.move(to: pts[0])
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, pts.count - 1)]
            blade.addCurve(to: p2,
                           control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                           control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        blade.closeSubpath()
        let all = CGMutablePath()
        for i in 0..<count {
            let t = CGAffineTransform(translationX: centre.x, y: centre.y)
                .scaledBy(x: radius, y: radius)
                .rotated(by: orientation + turn + Double(i) * 2 * .pi / Double(count))
            all.addPath(blade, transform: t)
        }
        return all
    }
}

// MARK: Drawing helpers

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}

func bitmap(_ size: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let k = CGFloat(size) / 1024
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: k, y: -k)            // canvas space: 1024 units, y down
    return ctx
}

/// A disc blurred by `sigma`, as a radial gradient: flat to r - sigma, gone by r + 2 sigma.
func softDisc(_ ctx: CGContext, centre: CGPoint, r: CGFloat, sigma: CGFloat, _ hex: UInt32, _ alpha: CGFloat) {
    let outer = r + 2 * sigma
    ctx.drawRadialGradient(gradient([(0, color(hex, alpha)), ((r - sigma) / outer, color(hex, alpha)),
                                     (r / outer, color(hex, alpha * 0.5)), (1, color(hex, 0))]),
                           startCenter: centre, startRadius: 0, endCenter: centre, endRadius: outer, options: [])
}

/// Draws an image made by `bitmap` back pixel for pixel, whatever the current transform.
func drawBase(_ ctx: CGContext, _ image: CGImage, _ side: CGFloat) {
    ctx.saveGState()
    ctx.concatenate(ctx.ctm.inverted())
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    ctx.restoreGState()
}

// MARK: The icon

func render(size: Int) -> Data? {
    let side = CGFloat(size), k = side / 1024
    let ctx = bitmap(size)
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tileShape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    let centre = CGPoint(x: 512, y: 512)
    let fanRadius: CGFloat = 350

    ctx.saveGState()
    ctx.addPath(tileShape); ctx.clip()

    // The desktop behind the glass.
    ctx.drawLinearGradient(gradient([(0, color(0x1a2b52)), (0.55, color(0x0c1227)), (1, color(0x150f2c))]),
                           start: CGPoint(x: 100, y: 100), end: CGPoint(x: 924, y: 924), options: [])
    softDisc(ctx, centre: CGPoint(x: 700, y: 740), r: 300, sigma: 80, 0x3987e5, 0.6)
    softDisc(ctx, centre: CGPoint(x: 290, y: 250), r: 210, sigma: 80, 0x199e70, 0.28)

    // The pane.
    ctx.drawLinearGradient(gradient([(0, color(0xffffff, 0.17)), (0.5, color(0xffffff, 0.05)), (1, color(0xffffff, 0.09))]),
                           start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 120); ctx.scaleBy(x: 1, y: 170.0 / 470.0)
    softDisc(ctx, centre: .zero, r: 470, sigma: 80, 0xffffff, 0.08)
    ctx.restoreGState()

    // The wake: copies of the blades turned back against the spin, fading,
    // blurred, and faded out near the hub where they all converge.
    let wakeCtx = bitmap(size)
    let pitch = 2 * Double.pi / Double(Blade.count)
    for g in 1..<16 {
        let f = Double(g) / 16
        wakeCtx.addPath(Blade.path(centre: centre, radius: fanRadius, turn: -f * pitch * 0.62))
        wakeCtx.setFillColor(color(0xcfe5ff, 0.34 * pow(1 - f, 1.6)))
        wakeCtx.fillPath()
    }
    wakeCtx.setBlendMode(.destinationIn)
    let hubR = fanRadius * Blade.hub
    wakeCtx.drawRadialGradient(gradient([(0, color(0, 0)), (hubR * 0.92 / 385, color(0, 0)),
                                         (hubR * 1.25 / 385, color(0, 1)), (1, color(0, 1))]),
                               startCenter: centre, startRadius: 0, endCenter: centre, endRadius: 385,
                               options: [.drawsAfterEndLocation])
    if let raw = wakeCtx.makeImage() {
        let blurred = CIImage(cgImage: raw).clampedToExtent()
            .applyingGaussianBlur(sigma: 1.6 * 3.5 * k).cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
        if let image = CIContext().createCGImage(blurred, from: blurred.extent) {
            drawBase(ctx, image, side)
        }
    }

    // Blades and hub, lifted off the glass by a shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -3.2 * 3.5 * k), blur: 4.5 * 3.5 * 2 * k,
                  color: color(0x030612, 0.55))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.saveGState()
    ctx.addPath(Blade.path(centre: centre, radius: fanRadius)); ctx.clip()
    ctx.drawRadialGradient(gradient([(0.25, color(0xffffff)), (1, color(0xdbe7fb))]),
                           startCenter: centre, startRadius: 0, endCenter: centre, endRadius: fanRadius,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
    let hubRect = CGRect(x: centre.x - hubR, y: centre.y - hubR, width: 2 * hubR, height: 2 * hubR)
    ctx.saveGState()
    ctx.addEllipse(in: hubRect); ctx.clip()
    let hubLight = CGPoint(x: centre.x - 0.24 * hubR, y: centre.y - 0.36 * hubR)
    ctx.drawRadialGradient(gradient([(0, color(0xf5f8ff)), (1, color(0xc7d6ee))]),
                           startCenter: hubLight, startRadius: 0, endCenter: hubLight, endRadius: 1.8 * hubR,
                           options: [.drawsAfterEndLocation])
    ctx.restoreGState()
    let inner = hubR * 0.46
    ctx.addEllipse(in: CGRect(x: centre.x - inner, y: centre.y - inner, width: 2 * inner, height: 2 * inner))
    ctx.setStrokeColor(color(0x0b1226, 0.16)); ctx.setLineWidth(hubR * 0.06); ctx.strokePath()
    ctx.addEllipse(in: hubRect)
    ctx.setStrokeColor(color(0xffffff, 0.7)); ctx.setLineWidth(0.9 * 3.5); ctx.strokePath()
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    ctx.restoreGState()   // tile clip

    // The rim: bright at the top, where glass catches the light.
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 183.5, cornerHeight: 183.5, transform: nil))
    ctx.setLineWidth(3)
    ctx.replacePathWithStrokedPath(); ctx.clip()
    ctx.drawLinearGradient(gradient([(0, color(0xffffff, 0.85)), (0.35, color(0xffffff, 0.2)),
                                     (0.75, color(0xffffff, 0.1)), (1, color(0xffffff, 0.32))]),
                           start: CGPoint(x: 100 + 0.2 * 824, y: 100), end: CGPoint(x: 100 + 0.5 * 824, y: 924), options: [])
    ctx.restoreGState()

    guard let image = ctx.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
}

for size in sizes {
    guard let data = render(size: size) else { continue }
    try? data.write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    // The @2x slot of the next size down is the same pixel count.
    let half = size / 2
    if sizes.contains(half) {
        try? data.write(to: iconset.appendingPathComponent("icon_\(half)x\(half)@2x.png"))
    }
}
print("iconset written to \(iconset.path)")
