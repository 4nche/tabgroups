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

    /// A point from `NSEvent.mouseLocation` in Accessibility coordinates.
    static func accessibilityPoint(fromAppKit point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: CGFloat(mainDisplayHeight) - point.y)
    }

    /// Every on-screen window, front to back, as the window server reports it.
    static func onScreenWindows() -> [ScreenWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return raw.compactMap { info in
            guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let processID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let rect = (info[kCGWindowBounds as String] as? NSDictionary)
                    .flatMap({ CGRect(dictionaryRepresentation: $0) }) else { return nil }
            return ScreenWindow(number: number, processID: processID, layer: layer, bounds: WindowBounds(rect))
        }
    }

    static func displayIdentifier(for bounds: WindowBounds) -> String? {
        let number = screen(for: bounds)?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number?.stringValue
    }
}
