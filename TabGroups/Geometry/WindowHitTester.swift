import CoreGraphics

/// A window as the window server lists it. Bounds are in Accessibility coordinates.
struct ScreenWindow: Equatable {
    let number: CGWindowID
    let processID: pid_t
    let layer: Int
    let bounds: WindowBounds
}

enum WindowHitTester {
    /// Ordinary app windows live on layer 0; menus, the Dock and overlays sit on other layers.
    static let appWindowLayer = 0

    /// The app windows containing `point`, front to back, given the server's front-to-back list.
    static func windows(at point: CGPoint, in frontToBack: [ScreenWindow],
                        excluding excluded: Set<CGWindowID> = []) -> [ScreenWindow] {
        frontToBack.filter { window in
            window.layer == appWindowLayer && !excluded.contains(window.number) && window.bounds.contains(point)
        }
    }
}

extension WindowBounds {
    func contains(_ point: CGPoint) -> Bool {
        point.x >= x && point.x <= x + width && point.y >= y && point.y <= y + height
    }

    init(_ rect: CGRect) {
        self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }
}
