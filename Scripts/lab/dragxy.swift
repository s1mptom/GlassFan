import AppKit
import CoreGraphics
// dragxy <bundle-id> <speed pt/s> x,y x,y ... : activates the app, presses at the first
// point, glides through the rest with half-second pauses, releases; puts the cursor back.
let args = CommandLine.arguments
let bundle = args[1]; let speed = CGFloat(Double(args[2])!)
let pts = args[3...].map { s -> CGPoint in let p = s.split(separator: ",").map { CGFloat(Double($0)!) }; return CGPoint(x: p[0], y: p[1]) }
let saved = CGEvent(source: nil)?.location ?? pts[0]
func post(_ t: CGEventType, _ p: CGPoint) { CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap) }
func stamp(_ s: String) { print(String(format: "%.3f %@", Date().timeIntervalSince1970, s)); fflush(stdout) }
NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.activate()
usleep(400_000)
var at = pts[0]
post(.mouseMoved, at); usleep(200_000)
stamp("down"); post(.leftMouseDown, at); usleep(700_000)
for to in pts.dropFirst() {
    let d = hypot(to.x - at.x, to.y - at.y)
    let steps = max(Int(d / speed * 60), 1); let from = at
    for i in 1...steps {
        let f = CGFloat(i) / CGFloat(steps)
        at = CGPoint(x: from.x + (to.x - from.x) * f, y: from.y + (to.y - from.y) * f)
        post(.leftMouseDragged, at); usleep(16_667)
    }
    stamp("at \(Int(to.x)),\(Int(to.y))"); usleep(700_000)
}
stamp("up"); post(.leftMouseUp, at); usleep(300_000)
post(.mouseMoved, saved); stamp("done")
