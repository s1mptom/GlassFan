import AppKit
import SwiftUI

/// The live reading's dot and the label beside it, moved by Core Animation.
///
/// They were two SwiftUI views with `.animation(.easeInOut(duration: 0.8))` keyed on the
/// reading - and a reading arrives every second, so an animation was in flight four
/// fifths of the time. Every frame of an in-flight SwiftUI animation lays the whole
/// window out again, at the display's rate: on a busy Mac, which is when the readings
/// move most, that measured eleven points of a core and three quarters of everything
/// this screen cost. Here the layers are told where to go once a second and the render
/// server moves them, so between readings the app does nothing at all.
struct LiveMarker: NSViewRepresentable {
    /// The dot's centre, in the editor's coordinates - y down, as SwiftUI has it.
    var dot: CGPoint
    /// The label's centre, in the same coordinates.
    var label: CGPoint
    var reading: String
    /// Dimmed while a point is being set, which is what matters then.
    var dimmed: Bool
    /// How long the glide takes, matching the animation it replaces.
    var duration: CFTimeInterval = 0.8

    func makeNSView(context: Context) -> LiveMarkerView { LiveMarkerView() }

    func updateNSView(_ view: LiveMarkerView, context: Context) {
        view.show(dot: dot, label: label, reading: reading, dimmed: dimmed, duration: duration)
    }
}

/// The view behind `LiveMarker`: two layers and nothing else.
final class LiveMarkerView: NSView {
    private let dotLayer = CALayer()
    private let labelLayer = CALayer()

    /// What is drawn, so that nothing is rasterised twice for the same reading.
    private var drawnReading: String?
    private var drawnAppearance: NSAppearance.Name?
    private var drawnScale: CGFloat = 0

    /// Where they were last asked to be, in SwiftUI's coordinates, so a resize can put
    /// them back without waiting for the next reading.
    private var dotAt: CGPoint = .zero
    private var labelAt: CGPoint = .zero
    /// The first placing arrives with the screen; gliding in from a corner is not a
    /// reading moving.
    private var placed = false

    private let diameter: CGFloat = 11

    init() {
        super.init(frame: .zero)
        let root = CALayer()
        root.addSublayer(dotLayer)
        root.addSublayer(labelLayer)
        // Layer-hosting, and the layer is set before `wantsLayer`. The other way round
        // makes the view layer-*backed*, and AppKit then wraps every write to these
        // layers in an implicit animation of its own.
        layer = root
        wantsLayer = true
        dotLayer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        dotLayer.cornerRadius = diameter / 2
    }

    required init?(coder: NSCoder) { fatalError("LiveMarkerView is not made from a nib") }

    /// Decoration: every click belongs to the plot underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        redraw()
    }

    override func layout() {
        super.layout()
        // The y flip needs the height, and the height is only known here.
        place(animated: false)
    }

    func show(dot: CGPoint, label: CGPoint, reading: String, dimmed: Bool, duration: CFTimeInterval) {
        dotAt = dot
        labelAt = label
        if reading != drawnReading { drawnReading = reading; redraw() }
        let settled = placed
        place(animated: settled, duration: duration)
        placed = true
        set(opacity: dimmed ? 0.25 : 1, on: labelLayer, animated: settled)
    }

    // MARK: Drawing

    /// Both layers' pictures. Only the label's changes with the reading; the dot is the
    /// same disc for ever, and is a rounded rectangle rather than a picture.
    private func redraw() {
        let appearance = effectiveAppearance
        let scale = window?.backingScaleFactor ?? 2
        var heat = NSColor.orange, ink = NSColor.white, surface = NSColor.black
        appearance.performAsCurrentDrawingAppearance {
            heat = NSColor(Palette.heat)
            ink = NSColor(Palette.ink)
            surface = NSColor(Palette.surface)
        }
        withoutAnimation {
            dotLayer.backgroundColor = heat.cgColor
            if let reading = drawnReading,
               let (image, size) = pill(reading, ink: ink, surface: surface,
                                        appearance: appearance, scale: scale) {
                labelLayer.contents = image
                labelLayer.contentsScale = scale
                labelLayer.bounds = CGRect(origin: .zero, size: size)
            }
        }
        drawnAppearance = appearance.name
        drawnScale = scale
    }

    /// The reading on its capsule, drawn once per reading: an 11pt line with monospaced
    /// digits, nine points of air either side and four above and below, on the same
    /// translucent capsule the rest of the interface uses for a small label.
    private func pill(_ reading: String, ink: NSColor, surface: NSColor,
                      appearance: NSAppearance, scale: CGFloat) -> (CGImage, CGSize)? {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let text = NSAttributedString(string: reading, attributes: [.font: font, .foregroundColor: ink])
        let textSize = text.size()
        let size = CGSize(width: ceil(textSize.width) + 18, height: ceil(textSize.height) + 8)
        guard let context = CGContext(data: nil,
                                      width: Int(size.width * scale), height: Int(size.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        appearance.performAsCurrentDrawingAppearance {
            let capsule = NSBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.25, dy: 0.25),
                                       xRadius: size.height / 2, yRadius: size.height / 2)
            surface.withAlphaComponent(0.82).setFill()
            capsule.fill()
            ink.withAlphaComponent(0.12).setStroke()
            capsule.lineWidth = 0.5
            capsule.stroke()
            text.draw(at: CGPoint(x: 9, y: (size.height - textSize.height) / 2))
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage().map { ($0, size) }
    }

    // MARK: Moving

    private func place(animated: Bool, duration: CFTimeInterval = 0.8) {
        guard bounds.height > 0 else { return }
        move(dotLayer, to: flipped(dotAt), animated: animated, duration: duration)
        move(labelLayer, to: flipped(labelAt), animated: animated, duration: duration)
    }

    /// SwiftUI counts down the screen and layers count up it.
    private func flipped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: bounds.height - point.y)
    }

    private func move(_ layer: CALayer, to point: CGPoint, animated: Bool, duration: CFTimeInterval) {
        let from = layer.presentation()?.position ?? layer.position
        withoutAnimation { layer.position = point }
        guard animated, from != point else { layer.removeAnimation(forKey: "move"); return }
        let glide = CABasicAnimation(keyPath: "position")
        // From where it actually is, not from where the last one was aiming: a reading
        // that lands mid-glide carries on from here rather than jumping back.
        glide.fromValue = NSValue(point: from)
        glide.toValue = NSValue(point: point)
        glide.duration = duration
        glide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(glide, forKey: "move")
    }

    private func set(opacity: Float, on layer: CALayer, animated: Bool) {
        guard layer.opacity != opacity else { return }
        guard animated else { withoutAnimation { layer.opacity = opacity }; return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
        fade.toValue = opacity
        fade.duration = 0.15
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        withoutAnimation { layer.opacity = opacity }
        layer.add(fade, forKey: "fade")
    }

    private func withoutAnimation(_ change: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        change()
        CATransaction.commit()
    }
}
