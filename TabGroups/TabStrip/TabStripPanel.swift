import AppKit
import SwiftUI

private struct GroupFrameView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 2)
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
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        contentView = NSHostingView(rootView: GroupFrameView())
    }

    func show(bounds: WindowBounds) {
        let rect = WindowScreenGeometry.appKitRect(for: bounds)
        setFrame(rect, display: true)
        orderFrontRegardless()
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
        let groupRect = WindowScreenGeometry.appKitRect(for: target)
        let height: CGFloat = 42
        setFrame(NSRect(x: groupRect.minX, y: groupRect.maxY,
                        width: max(240, min(CGFloat(target.width), 720)), height: height), display: true)
        orderFrontRegardless()
    }
}
