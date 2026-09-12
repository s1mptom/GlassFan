#!/usr/bin/env swift
// Generates AppIcon.icns. Kept as a script so the icon is reproducible rather than a
// binary blob nobody can regenerate.
//
// The picture is the app's own dial: five blades and the air they drag, on a pane
// of glass over a deep desktop. The blade is the same petal `FanBlades` draws,
// point for point, so the icon and the gauge are one drawing.
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconset = URL(fileURLWithPath: "build/GlassFan.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// One petal from the hub to the rim and back, in a unit square, `spread` times
/// the drawn width - the same curve as `FanBlades.path`.
func petal(in rect: CGRect, spread: CGFloat) -> CGPath {
    let side = min(rect.width, rect.height)
    let o = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * side, y: o.y + y * side) }
    let half = 0.076 * spread
    let path = CGMutablePath()
    path.move(to: p(0.5, 0.5))
    path.addCurve(to: p(0.5, 0.1515), control1: p(0.5, 0.303), control2: p(0.5 - half, 0.197))
    path.addCurve(to: p(0.5, 0.5), control1: p(0.5 + half, 0.197), control2: p(0.5, 0.303))
    path.closeSubpath()
    return path
}

func blades(in rect: CGRect, count: Int, spread: CGFloat, turn: CGFloat) -> CGPath {
    let all = CGMutablePath()
    let c = CGPoint(x: rect.midX, y: rect.midY)
    for i in 0..<count {
        var t = CGAffineTransform(translationX: c.x, y: c.y)
            .rotated(by: turn + CGFloat(i) * 2 * .pi / CGFloat(count))
            .translatedBy(x: -c.x, y: -c.y)
        all.addPath(petal(in: rect, spread: spread), transform: t)
        _ = t
    }
    return all
}

func gradient(_ stops: [(CGFloat, CGFloat, CGFloat, CGFloat)], _ locations: [CGFloat]) -> CGGradient? {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
               colors: stops.map { NSColor(srgbRed: $0.0, green: $0.1, blue: $0.2, alpha: $0.3).cgColor } as CFArray,
               locations: locations)
}

func render(size: Int) -> Data? {
    let side = CGFloat(size)
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    guard let cx = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); return nil }

    // macOS icons sit inside the canvas with a margin, in a rounded square.
    let inset = side * 0.085
    let tile = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let corner = tile.width * 0.2237
    let shape = CGPath(roundedRect: tile, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // The desktop the glass sits over: deep blue into violet, with a warm glow
    // low on the right so the pane has something to refract.
    cx.saveGState()
    cx.addPath(shape); cx.clip()
    if let g = gradient([(0.07, 0.13, 0.30, 1), (0.05, 0.08, 0.20, 1), (0.14, 0.07, 0.24, 1)], [0, 0.55, 1]) {
        cx.drawLinearGradient(g, start: CGPoint(x: tile.minX, y: tile.maxY),
                              end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    }
    if let glow = gradient([(0.35, 0.62, 1.0, 0.55), (0.35, 0.62, 1.0, 0)], [0, 1]) {
        let c = CGPoint(x: tile.midX + tile.width * 0.18, y: tile.midY - tile.height * 0.22)
        cx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c,
                              endRadius: tile.width * 0.55, options: [])
    }

    // The pane: a lighter slab of glass inset from the tile, with a rim that
    // catches light at the top and a sheen across its upper half.
    let paneInset = tile.width * 0.11
    let pane = tile.insetBy(dx: paneInset, dy: paneInset)
    let paneCorner = pane.width * 0.24
    let paneShape = CGPath(roundedRect: pane, cornerWidth: paneCorner, cornerHeight: paneCorner, transform: nil)
    cx.saveGState()
    cx.addPath(paneShape); cx.clip()
    cx.setFillColor(NSColor(white: 1, alpha: 0.10).cgColor)
    cx.fill(pane)
    if let sheen = gradient([(1, 1, 1, 0.26), (1, 1, 1, 0.04), (1, 1, 1, 0)], [0, 0.45, 1]) {
        cx.drawLinearGradient(sheen, start: CGPoint(x: pane.midX, y: pane.maxY),
                              end: CGPoint(x: pane.midX, y: pane.minY), options: [])
    }
    cx.restoreGState()
    cx.addPath(paneShape)
    cx.setStrokeColor(NSColor(white: 1, alpha: 0.32).cgColor)
    cx.setLineWidth(max(side * 0.006, 1))
    cx.strokePath()
    if let rim = gradient([(1, 1, 1, 0.55), (1, 1, 1, 0)], [0, 1]) {
        // The top edge lit a little brighter than the rest of the rim.
        cx.saveGState()
        cx.addPath(paneShape); cx.clip()
        cx.drawLinearGradient(rim, start: CGPoint(x: pane.midX, y: pane.maxY),
                              end: CGPoint(x: pane.midX, y: pane.maxY - pane.height * 0.06), options: [])
        cx.restoreGState()
    }

    // The disc: the air first - the blades swollen wide and blurred, at low
    // strength - then the five crisp blades over it.
    let disc = pane.insetBy(dx: pane.width * 0.03, dy: pane.height * 0.03)
    let turn: CGFloat = 0.32
    cx.saveGState()
    cx.setShadow(offset: .zero, blur: side * 0.05, color: NSColor(srgbRed: 0.80, green: 0.90, blue: 1, alpha: 0.9).cgColor)
    cx.addPath(blades(in: disc, count: 5, spread: 2.8, turn: turn))
    cx.setFillColor(NSColor(srgbRed: 0.80, green: 0.90, blue: 1, alpha: 0.28).cgColor)
    cx.fillPath()
    cx.restoreGState()

    cx.addPath(blades(in: disc, count: 5, spread: 1, turn: turn))
    cx.setFillColor(NSColor(white: 1, alpha: 0.96).cgColor)
    cx.fillPath()
    let hub = disc.width * 0.05
    cx.addEllipse(in: CGRect(x: disc.midX - hub, y: disc.midY - hub, width: hub * 2, height: hub * 2))
    cx.setFillColor(NSColor(white: 1, alpha: 0.96).cgColor)
    cx.fillPath()

    cx.restoreGState()
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
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
