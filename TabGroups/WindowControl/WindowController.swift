import AppKit

enum WindowControlError: LocalizedError {
    case permissionMissing
    case windowUnavailable
    case moveOrResizeRejected(WindowBounds?)

    var errorDescription: String? {
        switch self {
        case .permissionMissing: return "Enable Accessibility permission to control app windows."
        case .windowUnavailable: return "This window is no longer available."
        case .moveOrResizeRejected(let actual):
            if let actual { return "The app constrained this window to \(Int(actual.width)) × \(Int(actual.height))." }
            return "This app did not accept the requested window size or position."
        }
    }
}

final class WindowController {
    private let catalog: WindowCatalog

    init(catalog: WindowCatalog) { self.catalog = catalog }

    func resolve(_ reference: WindowReference) throws -> DiscoveredWindow {
        guard AccessibilityPermission.isGranted else { throw WindowControlError.permissionMissing }
        guard case .matched(let window) = catalog.match(reference) else { throw WindowControlError.windowUnavailable }
        return window
    }

    func activate(_ reference: WindowReference, bounds: WindowBounds) throws -> WindowBounds {
        let target = try resolve(reference)
        target.window.raise()
        guard let actual = target.window.apply(bounds) else { throw WindowControlError.windowUnavailable }
        let difference = abs(actual.x - bounds.x) + abs(actual.y - bounds.y)
            + abs(actual.width - bounds.width) + abs(actual.height - bounds.height)
        guard difference <= 4 else { throw WindowControlError.moveOrResizeRejected(actual) }
        return actual
    }

    func currentBounds(_ reference: WindowReference) -> WindowBounds? {
        guard case .matched(let window) = catalog.match(reference) else { return nil }
        return window.window.bounds()
    }
}
