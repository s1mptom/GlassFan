#!/usr/bin/env swift
// Generates AppIcon.icns. Kept as a script so the icon is reproducible rather than a
// binary blob nobody can regenerate.
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconset = URL(fileURLWithPath: "build/MacFans.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(size: Int) -> Data? {
    let side = CGFloat(size)
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); return nil }

    // macOS icons sit inside the canvas with a margin, in a rounded square.
    let inset = side * 0.085
    let rect = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let corner = rect.width * 0.2237
    let shape = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let colors = [
        NSColor(srgbRed: 0.26, green: 0.55, blue: 0.93, alpha: 1).cgColor,
        NSColor(srgbRed: 0.11, green: 0.28, blue: 0.62, alpha: 1).cgColor,
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: colors, locations: [0, 1]) {
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: rect.minX, y: rect.maxY),
                                   end: CGPoint(x: rect.maxX, y: rect.minY),
                                   options: [])
    }
    // A soft highlight along the top edge, the way system icons catch light.
    if let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [NSColor(white: 1, alpha: 0.22).cgColor,
                                       NSColor(white: 1, alpha: 0).cgColor] as CFArray,
                              locations: [0, 1]) {
        context.drawLinearGradient(sheen,
                                   start: CGPoint(x: rect.midX, y: rect.maxY),
                                   end: CGPoint(x: rect.midX, y: rect.midY),
                                   options: [])
    }
    context.restoreGState()

    // The fan itself, from the system symbol so it matches the platform's drawing.
    let glyphSide = rect.width * 0.62
    let config = NSImage.SymbolConfiguration(pointSize: glyphSide, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "fan.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        NSColor.white.set()
        let bounds = NSRect(origin: .zero, size: symbol.size)
        symbol.draw(in: bounds)
        bounds.fill(using: .sourceAtop)
        tinted.unlockFocus()

        let target = NSRect(x: rect.midX - symbol.size.width / 2,
                            y: rect.midY - symbol.size.height / 2,
                            width: symbol.size.width,
                            height: symbol.size.height)
        tinted.draw(in: target, from: .zero, operation: .sourceOver, fraction: 0.96)
    }

    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
}

for size in sizes {
    guard let data = render(size: size) else { continue }
    let scale1 = iconset.appendingPathComponent("icon_\(size)x\(size).png")
    try? data.write(to: scale1)
    // The @2x slot of the next size down is the same pixel count.
    let half = size / 2
    if sizes.contains(half) {
        try? data.write(to: iconset.appendingPathComponent("icon_\(half)x\(half)@2x.png"))
    }
}
print("iconset written to \(iconset.path)")
