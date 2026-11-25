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

    /// Drops handles whose window no longer appears in a fresh scan (closed, or its app quit).
    func prune(keeping scanned: [DiscoveredWindow]) {
        let gone = handles.filter { _, handle in
            !scanned.contains { $0.window.isSameWindow(as: handle.window.element) }
        }
        gone.keys.forEach(forget(memberID:))
    }

    func recordApplied(_ bounds: WindowBounds, memberID: UUID) {
        lastApplied[memberID] = bounds
    }

    func forget(memberID: UUID) {
        handles[memberID] = nil
        lastApplied[memberID] = nil
    }
}
