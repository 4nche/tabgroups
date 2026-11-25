import AppKit
import SwiftUI

/// Lets a click act on a tab even though the bar's panel is never the key window.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The bar window of one group. Dragging the bar moves the group; dragging a tab pulls that window
/// out of the group. Either way the drag reports the offset since mouse-down in
/// screen coordinates, so moving the panel during the drag cannot distort the measurement.
final class TabStripPanel: NSPanel {
    /// Total offset since mouse-down, Accessibility axes (positive height = down).
    var onDragChanged: ((CGSize) -> Void)?
    var onDragEnded: (() -> Void)?
    /// A tab is being dragged out of the bar: its member id and the same kind of offset.
    var onTabDragChanged: ((UUID, CGSize) -> Void)?
    var onTabDragEnded: ((UUID) -> Void)?
    /// Any click or drag on the bar has finished; the window server may have raised this panel.
    var onInteractionEnded: (() -> Void)?

    private static let dragThreshold: CGFloat = 3
    /// Higher than the bar's, so a slightly shaky click on a tab does not detach it.
    private static let tabDragThreshold: CGFloat = 10
    private let host = FirstMouseHostingView(rootView: TabStripView(tabs: [], selectedID: nil,
                                                            onSelect: { _ in }, onRemove: { _ in },
                                                            onTabFrames: { _ in }))
    private var mouseDownLocation: NSPoint?
    private var isDragging = false
    private var tabFrames: [UUID: CGRect] = [:]
    /// The tab the current press started on; nil when it started on the bar itself.
    private var pressedTabID: UUID?

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
        // Transient keeps the bar out of Mission Control, where it would show as a loose strip.
        collectionBehavior = [.transient, .fullScreenAuxiliary, .ignoresCycle]
        contentView = host
    }

    func update(tabs: [TabItem], selectedID: UUID?,
                onSelect: @escaping (UUID) -> Void, onRemove: @escaping (UUID) -> Void) {
        host.rootView = TabStripView(tabs: tabs, selectedID: selectedID,
                                     onSelect: onSelect, onRemove: onRemove,
                                     onTabFrames: { [weak self] frames in self?.tabFrames = frames })
    }

    func place(at container: WindowBounds) {
        setFrame(ScreenGeometry.appKitRect(for: GroupGeometry.barBounds(of: container)), display: true)
    }

    func orderAbove(windowNumber: Int) {
        order(.above, relativeTo: windowNumber)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            // A mouse-up lost to another window must not leave the group stuck in a drag.
            if isDragging { endDrag() }
            mouseDownLocation = NSEvent.mouseLocation
            isDragging = false
            // The last tab cannot be pulled out of its own group; dragging it moves the group.
            pressedTabID = tabFrames.count > 1
                ? TabHitTester.tab(atWindowPoint: event.locationInWindow, panelHeight: frame.height, frames: tabFrames)
                : nil
            super.sendEvent(event)
        case .leftMouseDragged:
            guard let start = mouseDownLocation else { return super.sendEvent(event) }
            let now = NSEvent.mouseLocation
            let threshold = pressedTabID == nil ? Self.dragThreshold : Self.tabDragThreshold
            if !isDragging, hypot(now.x - start.x, now.y - start.y) > threshold {
                isDragging = true
            }
            guard isDragging else { return super.sendEvent(event) }
            let offset = CGSize(width: now.x - start.x, height: start.y - now.y)
            if let pressedTabID {
                onTabDragChanged?(pressedTabID, offset)
            } else {
                onDragChanged?(offset)
            }
        case .leftMouseUp:
            let wasDragging = isDragging
            mouseDownLocation = nil
            if wasDragging {
                endDrag()
            } else {
                super.sendEvent(event)
            }
            onInteractionEnded?()
        default:
            super.sendEvent(event)
        }
    }

    private func endDrag() {
        isDragging = false
        if let pressedTabID {
            onTabDragEnded?(pressedTabID)
        } else {
            onDragEnded?()
        }
        pressedTabID = nil
    }
}
