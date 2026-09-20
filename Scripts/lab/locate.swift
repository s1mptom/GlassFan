import AppKit
import ApplicationServices

// Prints Activity Monitor's front window and every radio button / segment in it, with
// screen frames (top-left origin, points). Read-only.
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "com.glassfan.app").first else {
    print("not running"); exit(1)
}
let ax = AXUIElementCreateApplication(app.processIdentifier)
func attr<T>(_ e: AXUIElement, _ name: String) -> T? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success else { return nil }
    return v as? T
}
func frame(_ e: AXUIElement) -> CGRect? {
    guard let p: AXValue = attr(e, kAXPositionAttribute), let s: AXValue = attr(e, kAXSizeAttribute) else { return nil }
    var pt = CGPoint.zero, sz = CGSize.zero
    AXValueGetValue(p, .cgPoint, &pt); AXValueGetValue(s, .cgSize, &sz)
    return CGRect(origin: pt, size: sz)
}
func walk(_ e: AXUIElement, depth: Int) {
    let role: String = attr(e, kAXRoleAttribute) ?? "?"
    let title: String = attr(e, kAXTitleAttribute) ?? attr(e, kAXDescriptionAttribute) ?? ""
    if ["AXRadioButton", "AXRadioGroup", "AXButton", "AXToolbar"].contains(role) || depth == 0 {
        let f = frame(e).map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "-"
        let value: Any = attr(e, kAXValueAttribute) ?? ""
        print(String(repeating: "  ", count: depth) + "\(role) '\(title)' \(f) value=\(value)")
    }
    guard depth < 9, let kids: [AXUIElement] = attr(e, kAXChildrenAttribute) else { return }
    for k in kids { walk(k, depth: depth + 1) }
}
if let windows: [AXUIElement] = attr(ax, kAXWindowsAttribute) {
    for w in windows {
        let t: String = attr(w, kAXTitleAttribute) ?? ""
        print("WINDOW '\(t)' \(frame(w).map { "\($0)" } ?? "-")")
        walk(w, depth: 1)
    }
}
