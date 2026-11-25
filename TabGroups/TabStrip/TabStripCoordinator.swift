import Foundation

final class TabStripCoordinator {
    private let panel = TabStripPanel()

    func show(_ group: TabGroup, titles: [UUID: (app: String, title: String)],
              select: @escaping (UUID) -> Void, remove: @escaping (UUID) -> Void) {
        panel.show(group: group, windowTitles: titles, onSelect: select, onRemove: remove)
    }

    func hide() { panel.orderOut(nil) }
}
