import AppKit
import SwiftUI

/// A scripted run of the curve-group drop in the real app, for looking at it frame by
/// frame: clicks, then slow drags with pauses, as a hand makes them.
///
/// `GLASSFAN_DEMO=1 GLASSFAN_DROP_SCRIPT=1`, and `GLASSFAN_DEMO_CURVES=2` or `3`. Demo
/// mode only, so it never talks to the daemon and cannot touch the fans. It opens the
/// Fans screen, posts mouse events to its own window (the pointer does not move), logs
/// every event and every frame of the drop to standard error, and quits.
///
/// A picture of one control in a window of its own did not show what the real screen
/// did - the sidebar, its scroll view and the window's own glass all change how the
/// drop looks - so this runs on the real thing.
@MainActor
enum DropScript {
    static let isEnabled = DemoFixture.isEnabled
        && ProcessInfo.processInfo.environment["GLASSFAN_DROP_SCRIPT"] == "1"

    /// Layers switched off for a run, to tell which one draws what:
    /// `GLASSFAN_DROP_OFF=light,glass,lens,frames`.
    static let off: Set<String> = isEnabled
        ? Set((ProcessInfo.processInfo.environment["GLASSFAN_DROP_OFF"] ?? "").split(separator: ",").map(String.init))
        : []

    /// `GLASSFAN_DEBUG_TRACK=1`: the segmented control's ground in loud colours, to see
    /// what the drop does with an edge it crosses.
    static let debugTrack = ProcessInfo.processInfo.environment["GLASSFAN_DEBUG_TRACK"] == "1"

    /// The drop list's rows, in the window's content coordinates (top-left origin).
    static var rows: [Int: CGRect] = [:]

    private static let start = Date()

    nonisolated static func log(_ line: String) {
        let stamp = String(format: "%7.3f ", Date().timeIntervalSince(start))
        FileHandle.standardError.write(Data((stamp + line + "\n").utf8))
    }

    /// `GLASSFAN_CLICKS="x,y x,y ..."` (demo mode): clicks at those points in the
    /// window, a second and a half apart, starting two seconds in - to check that
    /// something can be clicked where it is drawn. `GLASSFAN_PRESS="x,y"` holds a
    /// press there instead, for a look at what a press draws.
    static func clicks() {
        guard DemoFixture.isEnabled else { return }
        let env = ProcessInfo.processInfo.environment
        func points(_ key: String) -> [CGPoint] {
            (env[key] ?? "").split(separator: " ").compactMap { pair in
                let xy = pair.split(separator: ",").compactMap { Double($0) }
                return xy.count == 2 ? CGPoint(x: xy[0], y: xy[1]) : nil
            }
        }
        for (i, point) in points("GLASSFAN_CLICKS").enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2 + Double(i) * 1.5) {
                post(.leftMouseDown, point)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { post(.leftMouseUp, point) }
                log("clicked \(point)")
            }
        }
        if let point = points("GLASSFAN_PRESS").first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { post(.leftMouseDown, point); log("pressing \(point)") }
        }
        drag(through: points("GLASSFAN_DRAG"))
    }

    /// `GLASSFAN_DRAG="x,y x,y ..."` (demo mode): presses at the first point two
    /// seconds in, then drags through the rest at a hand's pace - 80 points a
    /// second - stopping half a second at each, and lets go at the last. For a
    /// look at a drop in motion anywhere in the window, the tabs included.
    private static func drag(through path: [CGPoint]) {
        guard let first = path.first else { return }
        var t = 2.0
        func at(_ delay: Double, _ action: @escaping () -> Void) {
            t += delay
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: action)
        }
        at(0, { post(.leftMouseDown, first); log("drag: down at \(first)") })
        at(0.5, {})
        var from = first
        for to in path.dropFirst() {
            let seconds = max(hypot(to.x - from.x, to.y - from.y) / 80, 0.05)
            let steps = max(Int(seconds * 60), 1)
            for step in 1...steps {
                let f = CGFloat(step) / CGFloat(steps)
                let point = CGPoint(x: from.x + (to.x - from.x) * f, y: from.y + (to.y - from.y) * f)
                at(seconds / Double(steps), { post(.leftMouseDragged, point) })
            }
            let reached = to
            at(0, { log("drag: at \(reached)") })
            at(0.5, {})
            from = to
        }
        let end = from
        at(0, { post(.leftMouseUp, end); log("drag: up at \(end)") })
    }

    static func begin() {
        clicks()
        guard isEnabled else { return }
        UserDefaults.standard.set("fans", forKey: Screen.storageKey)
        UserDefaults.standard.set(0, forKey: FansView.selectedKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { run() }
    }

    private static var window: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) }
    }

    private static func centre(_ index: Int) -> CGPoint? {
        rows[index].map { CGPoint(x: $0.midX, y: $0.midY) }
    }

    private static func post(_ type: NSEvent.EventType, _ point: CGPoint) {
        guard let window, let content = window.contentView else { return }
        // A click in a window that is not key only brings it forward; one elsewhere on
        // the screen mid-run would have the rest of the run click at nothing.
        if type == .leftMouseDown, !window.isKeyWindow {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
        let location = NSPoint(x: point.x, y: content.bounds.height - point.y)
        guard let event = NSEvent.mouseEvent(
            with: type, location: location, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)
        else { return }
        NSApp.postEvent(event, atStart: false)
    }

    private static func run() {
        guard let window, let first = centre(0), let second = centre(1) else {
            log("no drop list on screen - is the fan in Curve mode with two curves?")
            NSApp.terminate(nil)
            return
        }
        let frame = window.frame
        let screen = window.screen?.frame.height ?? 0
        log("WINDOW \(Int(frame.minX)) \(Int(screen - frame.maxY)) \(Int(frame.width)) \(Int(frame.height))")
        log(String(format: "EPOCH %.3f", start.timeIntervalSince1970))
        log("ROWS " + rows.sorted { $0.key < $1.key }
            .map { "\($0.key):\(Int($0.value.minY))-\(Int($0.value.maxY))" }.joined(separator: " "))

        var t = 0.5
        func at(_ delay: Double, _ action: @escaping () -> Void) {
            t += delay
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: action)
        }
        func click(_ point: CGPoint, _ name: String) {
            at(0, { post(.leftMouseDown, point); log("click \(name)") })
            at(0.02, { post(.leftMouseUp, point) })
        }
        /// Legs of (points down, seconds); a leg of 0 points is a pause.
        func drag(from: CGPoint, legs: [(CGFloat, Double)], _ name: String) {
            at(0, { post(.leftMouseDown, from); log("drag \(name): down at \(Int(from.y))") })
            var y = from.y
            for (distance, seconds) in legs {
                let steps = max(Int(seconds * 60), 1)
                for _ in 0..<steps {
                    y += distance / CGFloat(steps)
                    let point = CGPoint(x: from.x, y: y)
                    at(seconds / Double(steps), { post(.leftMouseDragged, point) })
                }
                let reached = y
                at(0, { log("drag \(name): at \(Int(reached))") })
            }
            let end = CGPoint(x: from.x, y: y)
            at(0.05, { post(.leftMouseUp, end); log("drag \(name): up at \(Int(end.y))") })
        }

        click(second, "row 2")
        at(1.6, {})
        click(first, "row 1")
        at(1.6, {})
        let down = second.y - first.y
        drag(from: first, legs: [(down * 0.2, 0.5), (0, 0.7), (down * 0.35, 0.8), (0, 0.7),
                                 (down * 0.45, 0.8), (0, 0.8)], "down")
        at(1.2, {})
        // Over to the next row in one move, then held there, still, for three seconds.
        drag(from: second, legs: [(-down, 0.6), (0, 3.0)], "over and hold")
        at(1.6, {})
        // A nudge: a little way at a middling pace, and stop - where lumps once showed.
        drag(from: second, legs: [(12, 0.25), (0, 0.8), (-22, 0.35), (0, 0.8), (10, 0.2), (0, 0.6)], "nudge")
        at(1.4, {})
        drag(from: second, legs: [(-down * 0.5, 1.2), (0, 0.6), (-down * 0.5, 1.2), (0, 0.6)], "up")
        at(2.0, { log("done"); NSApp.terminate(nil) })
    }
}
