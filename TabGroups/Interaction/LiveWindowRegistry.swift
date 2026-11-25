import Foundation

/// Keeps a live Accessibility handle per group member for this session, so a window whose title
/// changes is not lost. Title and position matching is only the way back in after a launch or wake.
final class LiveWindowRegistry {
    static let messagingTimeout: Float = 0.25

    private var handles: [UUID: DiscoveredWindow] = [:]
    /// The rectangle each member's window actually took the last time we placed it.
    private(set) var lastApplied: [UUID: WindowBounds] = [:]

    func window(for member: WindowReference, among candidates: [DiscoveredWindow]) -> DiscoveredWindow? {
        // No probing here: a slow or hung app must not cost a round trip on every lookup.
        if let known = handles[member.id] { return known }
        guard case .matched(let live) = WindowReferenceMatcher.match(member, among: candidates) else { return nil }
        remember(live, memberID: member.id)
        return live
    }

    func remember(_ window: DiscoveredWindow, memberID: UUID) {
        window.window.setMessagingTimeout(Self.messagingTimeout)
        handles[memberID] = window
    }

    /// Drops handles whose window is gone. An app that lists other windows but not this one has
    /// closed it. An app missing from the scan entirely may only have been too busy to answer, so its
    /// windows are kept unless the system confirms they no longer exist.
    func prune(keeping scanned: [DiscoveredWindow], isGone: (AXWindow) -> Bool = { $0.isInvalid }) {
        let gone = handles.filter { _, handle in
            let sameApp = scanned.filter { $0.window.processID == handle.window.processID }
            if sameApp.isEmpty { return isGone(handle.window) }
            return !sameApp.contains { $0.window.isSameWindow(as: handle.window.element) }
        }
        gone.keys.forEach(forget(memberID:))
    }

    func handleProcessID(for memberID: UUID) -> pid_t? {
        handles[memberID]?.window.processID
    }

    func recordApplied(_ bounds: WindowBounds, memberID: UUID) {
        lastApplied[memberID] = bounds
    }

    func forget(memberID: UUID) {
        handles[memberID] = nil
        lastApplied[memberID] = nil
    }
}
