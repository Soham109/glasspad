import AppKit
import ApplicationServices

/// Small typed helpers over the Accessibility API (public, needs the Accessibility permission
/// Glasspad already has for input). Used by the window tiling and Control Center buttons.
enum AXUI {
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = attribute(element, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        guard let v = attribute(element, name), let array = v as? [AnyObject] else { return [] }
        return array.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] { elements(element, kAXChildrenAttribute) }

    static func string(_ element: AXUIElement, _ name: String) -> String? { attribute(element, name) as? String }

    static func identifier(_ element: AXUIElement) -> String? { string(element, "AXIdentifier") }

    static func int(_ element: AXUIElement, _ name: String) -> Int? { (attribute(element, name) as? NSNumber)?.intValue }

    static func bool(_ element: AXUIElement, _ name: String) -> Bool? { (attribute(element, name) as? NSNumber)?.boolValue }

    @discardableResult
    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    static func frame(_ window: AXUIElement) -> CGRect? {
        guard let p = attribute(window, kAXPositionAttribute), let s = attribute(window, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    static func setPosition(_ window: AXUIElement, _ point: CGPoint) -> Bool {
        var p = point
        guard let v = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v) == .success
    }

    @discardableResult
    static func setSize(_ window: AXUIElement, _ size: CGSize) -> Bool {
        var s = size
        guard let v = AXValueCreate(.cgSize, &s) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v) == .success
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ name: String, _ value: Bool) -> Bool {
        AXUIElementSetAttributeValue(element, name as CFString, value as CFBoolean) == .success
    }

    /// Depth-first search, at most `maxDepth` levels and `budget` elements, so a huge tree can
    /// never stall the main thread.
    static func first(in root: AXUIElement, maxDepth: Int = 12, budget: Int = 4000,
                      where match: (AXUIElement) -> Bool) -> AXUIElement? {
        var visited = 0
        func walk(_ e: AXUIElement, _ depth: Int) -> AXUIElement? {
            visited += 1
            if visited > budget { return nil }
            if match(e) { return e }
            guard depth < maxDepth else { return nil }
            for child in children(e) {
                if let found = walk(child, depth + 1) { return found }
            }
            return nil
        }
        return walk(root, 0)
    }

    /// The running process for a bundle id.
    static func app(_ bundleID: String) -> AXUIElement? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
        else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        return app
    }

    static let permissionHint = "Allow Glasspad in System Settings > Privacy & Security > Accessibility."
}
