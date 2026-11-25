import ApplicationServices
import AppKit

struct AXWindow {
    let element: AXUIElement
    let processID: pid_t

    func readString(_ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    func bounds() -> WindowBounds? {
        guard let pointValue = copyValue(kAXPositionAttribute as CFString),
              let sizeValue = copyValue(kAXSizeAttribute as CFString) else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(pointValue, .cgPoint, &point),
              AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return WindowBounds(x: Double(point.x), y: Double(point.y), width: Double(size.width), height: Double(size.height))
    }

    func move(to bounds: WindowBounds) -> Bool {
        var point = CGPoint(x: CGFloat(bounds.x), y: CGFloat(bounds.y))
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    func resize(to bounds: WindowBounds) -> Bool {
        var size = CGSize(width: CGFloat(bounds.width), height: CGFloat(bounds.height))
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) == .success
    }

    @discardableResult
    func apply(_ bounds: WindowBounds) -> WindowBounds? {
        _ = move(to: bounds)
        _ = resize(to: bounds)
        return self.bounds()
    }

    func raise() {
        if let app = NSRunningApplication(processIdentifier: processID) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        _ = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    private func copyValue(_ attribute: CFString) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else { return nil }
        return (axValue as! AXValue)
    }
}
