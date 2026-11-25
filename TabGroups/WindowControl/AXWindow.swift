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
            app.activate(options: [])
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

extension AXWindow {
    /// Caps how long a call to this window may block, so a hung app cannot freeze the bar.
    func setMessagingTimeout(_ seconds: Float) {
        AXUIElementSetMessagingTimeout(element, seconds)
    }

    func isSameWindow(as other: AXUIElement) -> Bool {
        CFEqual(element, other)
    }

    /// True while the window is minimised or in full screen, when its rectangle is not one a group should follow.
    var isMinimizedOrFullScreen: Bool {
        ["AXMinimized", "AXFullScreen"].contains { attribute in
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return false }
            return (value as? Bool) ?? false
        }
    }

    /// True only when the system says this window no longer exists; a slow or busy app is not "gone".
    var isInvalid: Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .invalidUIElement
    }

    /// The window of this window's app that currently has keyboard focus.
    func focusedWindowOfOwningApp() -> AXUIElement? {
        let app = AXUIElementCreateApplication(processID)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}

extension AXWindow {
    /// The window under a point (Accessibility coordinates), asked of the system at this moment.
    static func window(at point: CGPoint) -> AXWindow? {
        var hit: AXUIElement?
        let system = AXUIElementCreateSystemWide()
        // A timeout on the system-wide element is global to this process, so it is put back at once:
        // left in place it would also cut off the background window scan for slower apps.
        AXUIElementSetMessagingTimeout(system, LiveWindowRegistry.messagingTimeout)
        let result = AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit)
        AXUIElementSetMessagingTimeout(system, 0)
        guard result == .success,
              let hit else { return nil }
        var processID: pid_t = 0
        guard AXUIElementGetPid(hit, &processID) == .success else { return nil }
        let element = AXWindow(element: hit, processID: processID)
        element.setMessagingTimeout(LiveWindowRegistry.messagingTimeout)
        if element.readString(kAXRoleAttribute as CFString) == (kAXWindowRole as String) { return element }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(hit, kAXWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return AXWindow(element: value as! AXUIElement, processID: processID)
    }

    /// The window of a process whose rectangle is closest to `bounds`, read fresh.
    static func window(ofProcess processID: pid_t, closestTo bounds: WindowBounds) -> AXWindow? {
        var value: CFTypeRef?
        let app = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(app, LiveWindowRegistry.messagingTimeout)
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement] else { return nil }
        return elements
            .map { element -> AXWindow in
                let window = AXWindow(element: element, processID: processID)
                window.setMessagingTimeout(LiveWindowRegistry.messagingTimeout)
                return window
            }
            .compactMap { window in window.bounds().map { (window, $0.distance(to: bounds)) } }
            .min { $0.1 < $1.1 }?.0
    }
}

extension AXWindow {
    /// Finder lists the desktop as a window: untitled and covering a whole screen. It is never a tab.
    var isFinderDesktop: Bool {
        guard NSRunningApplication(processIdentifier: processID)?.bundleIdentifier == "com.apple.finder",
              (readString(kAXTitleAttribute as CFString) ?? "").isEmpty,
              let bounds = bounds() else { return false }
        let rect = CGRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height)
        return NSScreen.screens.contains { screen in
            rect.width >= screen.frame.width - 1 && rect.height >= screen.frame.height - 1
        }
    }

    var isMinimized: Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    func setMinimized(_ minimized: Bool) {
        _ = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString,
                                         minimized ? kCFBooleanTrue : kCFBooleanFalse)
    }

    /// Every window the process lists right now, read fresh.
    static func windows(ofProcess processID: pid_t) -> [AXWindow] {
        var value: CFTypeRef?
        let app = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(app, LiveWindowRegistry.messagingTimeout)
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement] else { return [] }
        return elements.map { element in
            let window = AXWindow(element: element, processID: processID)
            window.setMessagingTimeout(LiveWindowRegistry.messagingTimeout)
            return window
        }
    }
}
