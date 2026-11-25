import AppKit
import CoreGraphics

/// Owns each group's bar: a tabs panel that takes clicks, and a glass backdrop panel behind it.
final class TabStripCoordinator {
    private struct Bar {
        let tabs: TabStripPanel
        let backdrop: BarBackdropPanel
        var memberWindowNumbers: [CGWindowID]
    }

    private var bars: [UUID: Bar] = [:]

    func show(_ group: TabGroup, tabs: [TabItem],
              select: @escaping (UUID) -> Void, remove: @escaping (UUID) -> Void,
              dragChanged: @escaping (CGSize) -> Void, dragEnded: @escaping () -> Void,
              tabDragChanged: @escaping (UUID, CGSize) -> Void, tabDragEnded: @escaping (UUID) -> Void,
              memberWindowNumbers: [CGWindowID]) {
        let existing = bars[group.id]
        let bar = Bar(tabs: existing?.tabs ?? TabStripPanel(),
                      backdrop: existing?.backdrop ?? BarBackdropPanel(),
                      memberWindowNumbers: memberWindowNumbers)
        bars[group.id] = bar
        bar.tabs.onDragChanged = dragChanged
        bar.tabs.onDragEnded = dragEnded
        bar.tabs.onTabDragChanged = tabDragChanged
        bar.tabs.onTabDragEnded = tabDragEnded
        bar.tabs.onInteractionEnded = { [weak self] in self?.restack(groupID: group.id) }
        bar.tabs.update(tabs: tabs, selectedID: group.selectedMemberID, onSelect: select, onRemove: remove)
        place(groupID: group.id, at: group.bounds)
        restack(bar)
    }

    func place(groupID: UUID, at container: WindowBounds) {
        guard let bar = bars[groupID] else { return }
        bar.backdrop.place(at: container)
        bar.tabs.place(at: container)
    }

    func reorder(groupID: UUID, memberWindowNumbers: [CGWindowID]) {
        guard let existing = bars[groupID] else { return }
        let bar = Bar(tabs: existing.tabs, backdrop: existing.backdrop, memberWindowNumbers: memberWindowNumbers)
        bars[groupID] = bar
        restack(bar)
    }

    /// The group one of our windows (tabs or backdrop) belongs to, if any.
    func groupID(forWindowNumber number: Int) -> UUID? {
        bars.first { $0.value.tabs.windowNumber == number || $0.value.backdrop.windowNumber == number }?.key
    }

    func hide(groupID: UUID) {
        guard let bar = bars.removeValue(forKey: groupID) else { return }
        bar.tabs.orderOut(nil)
        bar.backdrop.orderOut(nil)
    }

    private func restack(groupID: UUID) {
        guard let bar = bars[groupID] else { return }
        restack(bar)
    }

    /// Backdrop directly beneath the group's frontmost window, tabs directly above the backdrop.
    /// The whole bar is then covered by whatever covers the group, and never floats over the window.
    private func restack(_ bar: Bar) {
        if let frontmost = frontmostWindowNumber(among: bar.memberWindowNumbers) {
            bar.backdrop.order(.below, relativeTo: frontmost)
        } else {
            bar.backdrop.orderFront(nil)
        }
        bar.tabs.orderAbove(windowNumber: bar.backdrop.windowNumber)
    }

    private func frontmostWindowNumber(among windowNumbers: [CGWindowID]) -> Int? {
        let members = Set(windowNumbers.map(Int.init))
        guard !members.isEmpty,
              let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        return windows.lazy.compactMap { $0[kCGWindowNumber as String] as? Int }.first(where: members.contains)
    }
}
