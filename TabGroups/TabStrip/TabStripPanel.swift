import AppKit
import SwiftUI

final class TabStripPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 42),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    func show(group: TabGroup, windowTitles: [UUID: (app: String, title: String)],
              onSelect: @escaping (UUID) -> Void, onRemove: @escaping (UUID) -> Void) {
        let view = TabStripView(group: group, windowTitles: windowTitles,
                                onSelect: onSelect, onRemove: onRemove)
        contentView = NSHostingView(rootView: view)
        let target = group.bounds
        let screen = NSScreen.screens.first { candidate in
            let point = CGPoint(x: CGFloat(target.x + target.width / 2),
                                y: candidate.frame.maxY - CGFloat(target.y + target.height / 2))
            return candidate.frame.contains(point)
        } ?? NSScreen.main
        if let screen {
            let height: CGFloat = 42
            setFrame(NSRect(x: CGFloat(target.x), y: screen.frame.maxY - CGFloat(target.y),
                            width: max(240, min(CGFloat(target.width), 720)), height: height), display: true)
        }
        orderFrontRegardless()
    }
}
