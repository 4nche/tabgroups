import ApplicationServices
import AppKit

struct DiscoveredWindow: Identifiable {
    let id: String
    let appName: String
    let reference: WindowReference
    let window: AXWindow

    var bounds: WindowBounds { reference.lastKnownBounds }
}

enum WindowMatch {
    case matched(DiscoveredWindow)
    case ambiguous([DiscoveredWindow])
    case missing
}

enum WindowReferenceMatcher {
    static func match(_ reference: WindowReference, among windows: [DiscoveredWindow]) -> WindowMatch {
        let sameApp = windows.filter { $0.reference.bundleIdentifier == reference.bundleIdentifier }
        guard !sameApp.isEmpty else { return .missing }

        let ranked = sameApp.map { window in
            (window, score(reference, window.reference))
        }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        guard let best = ranked.first else { return .missing }
        let tied = ranked.prefix { $0.1 == best.1 }.map { $0.0 }
        if tied.count > 1 { return .ambiguous(tied) }
        return .matched(best.0)
    }

    private static func score(_ saved: WindowReference, _ live: WindowReference) -> Int {
        var score = 10
        if let pid = saved.processID, pid == live.processID { score += 100 }
        if let identifier = saved.accessibilityIdentifier,
           identifier == live.accessibilityIdentifier { score += 80 }
        if let title = saved.title, title == live.title { score += 35 }
        let a = saved.lastKnownBounds
        let b = live.lastKnownBounds
        let delta = abs(a.x - b.x) + abs(a.y - b.y) + abs(a.width - b.width) + abs(a.height - b.height)
        if delta < 24 { score += 20 }
        else if delta < 120 { score += 8 }
        return score
    }
}

final class WindowCatalog {
    func scan() -> [DiscoveredWindow] {
        guard AccessibilityPermission.isGranted else { return [] }
        return NSWorkspace.shared.runningApplications.flatMap(windows(for:))
    }

    func match(_ reference: WindowReference) -> WindowMatch {
        WindowReferenceMatcher.match(reference, among: scan())
    }

    /// Describes a window we hold a live handle to, without scanning every app.
    func describe(_ window: AXWindow) -> DiscoveredWindow? {
        guard let app = NSRunningApplication(processIdentifier: window.processID),
              let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier,
              let bounds = window.bounds() else { return nil }
        let title = window.readString(kAXTitleAttribute as CFString)
        let identifier = window.readString(kAXIdentifierAttribute as CFString)
        let reference = WindowReference(bundleIdentifier: bundleID, processID: app.processIdentifier,
                                        accessibilityIdentifier: identifier, title: title, lastKnownBounds: bounds)
        let key = [bundleID, String(app.processIdentifier), identifier ?? "", title ?? "",
                   "live-\(CFHash(window.element))"].joined(separator: "|")
        return DiscoveredWindow(id: key, appName: app.localizedName ?? bundleID, reference: reference, window: window)
    }

    private func windows(for app: NSRunningApplication) -> [DiscoveredWindow] {
        guard app.activationPolicy != .prohibited,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier else { return [] }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var rawWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &rawWindows) == .success,
              let elements = rawWindows as? [AXUIElement] else { return [] }

        return elements.enumerated().compactMap { index, element in
            let axWindow = AXWindow(element: element, processID: app.processIdentifier)
            guard let bounds = axWindow.bounds(), bounds.width > 80, bounds.height > 60 else { return nil }
            let title = axWindow.readString(kAXTitleAttribute as CFString)
            let identifier = axWindow.readString(kAXIdentifierAttribute as CFString)
            let reference = WindowReference(
                bundleIdentifier: bundleID,
                processID: app.processIdentifier,
                accessibilityIdentifier: identifier,
                title: title,
                lastKnownBounds: bounds
            )
            let key = [bundleID, String(app.processIdentifier), identifier ?? "", title ?? "", String(index)]
                .joined(separator: "|")
            return DiscoveredWindow(id: key, appName: app.localizedName ?? bundleID, reference: reference, window: axWindow)
        }
    }
}
