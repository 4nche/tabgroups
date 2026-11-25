import Foundation
import CoreGraphics

final class TabStripCoordinator {
    private struct GroupPanels {
        let tabs: TabStripPanel
        let frame: GroupFramePanel
    }

    private var panels: [UUID: GroupPanels] = [:]

    func show(_ group: TabGroup, titles: [UUID: (app: String, title: String)],
              select: @escaping (UUID) -> Void, remove: @escaping (UUID) -> Void,
              move: @escaping (CGSize) -> Void, moveEnded: @escaping () -> Void,
              memberWindowNumbers: [CGWindowID]) {
        let groupPanels = panels[group.id] ?? GroupPanels(tabs: TabStripPanel(), frame: GroupFramePanel())
        panels[group.id] = groupPanels
        groupPanels.frame.show(bounds: group.bounds)
        groupPanels.tabs.show(group: group, windowTitles: titles, onSelect: select, onRemove: remove,
                              onMove: move, onMoveEnded: moveEnded)
        orderAboveMembers(groupPanels, windowNumbers: memberWindowNumbers)
    }

    func translate(groupID: UUID, by delta: CGSize, memberWindowNumbers: [CGWindowID]) {
        guard let groupPanels = panels[groupID] else { return }
        groupPanels.frame.translate(by: delta)
        groupPanels.tabs.translate(by: delta)
        orderAboveMembers(groupPanels, windowNumbers: memberWindowNumbers)
    }

    private func orderAboveMembers(_ panels: GroupPanels, windowNumbers: [CGWindowID]) {
        let memberNumbers = Set(windowNumbers.map(Int.init))
        guard !memberNumbers.isEmpty,
              let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
              let topmostMemberNumber = windows.lazy.compactMap({ $0[kCGWindowNumber as String] as? Int })
                .first(where: memberNumbers.contains) else { return }
        panels.frame.orderAbove(windowNumber: topmostMemberNumber)
        panels.tabs.orderAbove(windowNumber: topmostMemberNumber)
    }

    func hide(groupID: UUID) {
        guard let groupPanels = panels.removeValue(forKey: groupID) else { return }
        groupPanels.tabs.orderOut(nil)
        groupPanels.frame.orderOut(nil)
    }

    func hide() {
        panels.values.forEach {
            $0.tabs.orderOut(nil)
            $0.frame.orderOut(nil)
        }
        panels.removeAll()
    }
}
