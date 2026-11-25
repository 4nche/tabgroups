import AppKit

/// Bridges Accessibility coordinates (top-left origin) and AppKit screens (bottom-left origin).
enum ScreenGeometry {
    /// Height of the primary display, the one both coordinate systems are anchored to.
    static var mainDisplayHeight: Double {
        Double(NSScreen.screens.first?.frame.maxY ?? 0)
    }

    static func appKitRect(for bounds: WindowBounds) -> CGRect {
        GroupGeometry.appKitRect(for: bounds, mainDisplayHeight: mainDisplayHeight)
    }

    /// The screen holding the rectangle's centre, or the main screen when it is off every screen.
    static func screen(for bounds: WindowBounds) -> NSScreen? {
        let rect = appKitRect(for: bounds)
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(centre) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Accessibility y of the usable top (below the menu bar) of the rectangle's screen.
    static func visibleTop(for bounds: WindowBounds) -> Double {
        guard let screen = screen(for: bounds) else { return 0 }
        return mainDisplayHeight - Double(screen.visibleFrame.maxY)
    }

    static func displayIdentifier(for bounds: WindowBounds) -> String? {
        let number = screen(for: bounds)?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number?.stringValue
    }
}
