import AppKit
import SwiftUI

/// Lets a click act on a tab even though the bar's panel is never the key window.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The bar window of one group. Dragging it anywhere reports the offset since mouse-down in
/// screen coordinates, so moving the panel during the drag cannot distort the measurement.
final class TabStripPanel: NSPanel {
    /// Total offset since mouse-down, Accessibility axes (positive height = down).
    var onDragChanged: ((CGSize) -> Void)?
    var onDragEnded: (() -> Void)?

    private static let dragThreshold: CGFloat = 3
    private let host = FirstMouseHostingView(rootView: TabStripView(tabs: [], selectedID: nil, glass: .regular,
                                                            onSelect: { _ in }, onRemove: { _ in }))
    private var mouseDownLocation: NSPoint?
    private var isDragging = false

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: GroupGeometry.barHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = false
        level = .normal
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        contentView = host
    }

    func update(tabs: [TabItem], selectedID: UUID?,
                onSelect: @escaping (UUID) -> Void, onRemove: @escaping (UUID) -> Void) {
        host.rootView = TabStripView(tabs: tabs, selectedID: selectedID, glass: GlassPreference.current,
                                     onSelect: onSelect, onRemove: onRemove)
    }

    func place(at container: WindowBounds) {
        setFrame(ScreenGeometry.appKitRect(for: GroupGeometry.barBackdropBounds(of: container)), display: true)
    }

    /// Directly beneath the group's front window: the window covers the part of the panel that
    /// reaches behind it, and only its rounded corners let the bar's surface show through.
    func orderBelow(windowNumber: Int) {
        order(.below, relativeTo: windowNumber)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            // A mouse-up lost to another window must not leave the group stuck in a drag.
            if isDragging { onDragEnded?() }
            mouseDownLocation = NSEvent.mouseLocation
            isDragging = false
            super.sendEvent(event)
        case .leftMouseDragged:
            guard let start = mouseDownLocation else { return super.sendEvent(event) }
            let now = NSEvent.mouseLocation
            if !isDragging, hypot(now.x - start.x, now.y - start.y) > Self.dragThreshold {
                isDragging = true
            }
            guard isDragging else { return super.sendEvent(event) }
            onDragChanged?(CGSize(width: now.x - start.x, height: start.y - now.y))
        case .leftMouseUp:
            let wasDragging = isDragging
            mouseDownLocation = nil
            isDragging = false
            if wasDragging {
                onDragEnded?()
            } else {
                super.sendEvent(event)
            }
        default:
            super.sendEvent(event)
        }
    }
}
