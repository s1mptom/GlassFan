import AppKit
// backdrop [r g b]: a plain window behind everything launched after it, covering the
// area where GlassFan's window lands, so screenshots do not show what is behind the app's
// translucent backing. Runs until killed.
let a = CommandLine.arguments
let colour = a.count >= 4 ? NSColor(red: CGFloat(Double(a[1])!), green: CGFloat(Double(a[2])!), blue: CGFloat(Double(a[3])!), alpha: 1)
                          : NSColor(white: 0.08, alpha: 1)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.main!.frame
let window = NSWindow(contentRect: NSRect(x: 200, y: screen.height - 900, width: 1400, height: 800),
                      styleMask: .borderless, backing: .buffered, defer: false)
window.backgroundColor = colour
window.level = .normal
window.orderFront(nil)
app.run()
