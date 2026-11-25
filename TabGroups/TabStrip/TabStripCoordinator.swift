import AppKit
import CoreGraphics

/// Owns one bar panel per group and keeps it placed and stacked with the group's windows.
final class TabStripCoordinator {
    private var panels: [UUID: TabStripPanel] = [:]

    func show(_ group: TabGroup, tabs: [TabItem],
              select: @escaping (UUID) -> Void, remove: @escaping (UUID) -> Void,
              dragChanged: @escaping (CGSize) -> Void, dragEnded: @escaping () -> Void,
              memberWindowNumbers: [CGWindowID]) {
        let panel = panels[group.id] ?? TabStripPanel()
        panels[group.id] = panel
        panel.onDragChanged = dragChanged
        panel.onDragEnded = dragEnded
        panel.update(tabs: tabs, selectedID: group.selectedMemberID, onSelect: select, onRemove: remove)
        panel.place(at: group.bounds)
        order(panel, behind: memberWindowNumbers)
    }

    func place(groupID: UUID, at container: WindowBounds) {
        panels[groupID]?.place(at: container)
    }

    func reorder(groupID: UUID, memberWindowNumbers: [CGWindowID]) {
        guard let panel = panels[groupID] else { return }
        order(panel, behind: memberWindowNumbers)
    }

    func hide(groupID: UUID) {
        panels.removeValue(forKey: groupID)?.orderOut(nil)
    }

    /// Stacks the bar directly beneath the group's frontmost window, so it is covered by whatever
    /// covers the group and fills in behind that window's rounded corners. With no known member window it is simply shown.
    private func order(_ panel: TabStripPanel, behind windowNumbers: [CGWindowID]) {
        guard let frontmost = frontmostWindowNumber(among: windowNumbers) else {
            panel.orderFront(nil)
            return
        }
        panel.orderBelow(windowNumber: frontmost)
    }

    private func frontmostWindowNumber(among windowNumbers: [CGWindowID]) -> Int? {
        let members = Set(windowNumbers.map(Int.init))
        guard !members.isEmpty,
              let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        return windows.lazy.compactMap { $0[kCGWindowNumber as String] as? Int }.first(where: members.contains)
    }
}
