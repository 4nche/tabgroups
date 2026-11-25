import AppKit
import SwiftUI

private struct GroupFrameView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.24), lineWidth: 1.25)
            .padding(1)
    }
}

final class GroupFramePanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .normal
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        contentView = NSHostingView(rootView: GroupFrameView())
    }

    func show(bounds: WindowBounds) {
        let rect = WindowScreenGeometry.appKitRect(for: bounds)
        setFrame(rect, display: true)
    }

    func translate(by delta: CGSize) {
        setFrameOrigin(NSPoint(x: frame.origin.x + delta.width, y: frame.origin.y - delta.height))
    }

    func orderAbove(windowNumber: Int) {
        order(.above, relativeTo: windowNumber)
    }
}

private enum WindowScreenGeometry {
    static var mainDisplayMaxY: CGFloat {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID()
        }?.frame.maxY ?? NSScreen.screens.first?.frame.maxY ?? 0
    }

    static func appKitRect(for bounds: WindowBounds) -> NSRect {
        NSRect(x: CGFloat(bounds.x),
               y: mainDisplayMaxY - CGFloat(bounds.y + bounds.height),
               width: CGFloat(bounds.width),
               height: CGFloat(bounds.height))
    }
}

final class TabStripPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 42),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = false
        level = .normal
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
    }

    func show(group: TabGroup, windowTitles: [UUID: (app: String, title: String)],
              onSelect: @escaping (UUID) -> Void, onRemove: @escaping (UUID) -> Void,
              onMove: @escaping (CGSize) -> Void, onMoveEnded: @escaping () -> Void) {
        let view = TabStripView(group: group, windowTitles: windowTitles,
                                onSelect: onSelect, onRemove: onRemove,
                                onMove: onMove, onMoveEnded: onMoveEnded)
        let host = NSHostingView(rootView: view)
        contentView = host
        host.layoutSubtreeIfNeeded()
        let target = group.bounds
        let groupRect = WindowScreenGeometry.appKitRect(for: target)
        let fittingSize = host.fittingSize
        let width = min(fittingSize.width, NSScreen.main?.visibleFrame.width ?? fittingSize.width)
        let height = fittingSize.height
        setFrame(NSRect(x: groupRect.minX, y: groupRect.maxY,
                        width: width, height: height), display: true)
    }

    func translate(by delta: CGSize) {
        setFrameOrigin(NSPoint(x: frame.origin.x + delta.width, y: frame.origin.y - delta.height))
    }

    func orderAbove(windowNumber: Int) {
        order(.above, relativeTo: windowNumber)
    }
}
