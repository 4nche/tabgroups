import AppKit

struct DragDropResult {
    var message: String
    var succeeded: Bool
}

final class WindowDragMonitor {
    private let catalog: WindowCatalog
    private let feedback = DragFeedbackPanel()
    private var monitors: [Any] = []
    private var source: DiscoveredWindow?
    private var startedWithShift = false
    private var startPoint: NSPoint = .zero
    private var dragMoved = false
    private let onDrop: (DiscoveredWindow, DiscoveredWindow) -> DragDropResult

    init(catalog: WindowCatalog, onDrop: @escaping (DiscoveredWindow, DiscoveredWindow) -> DragDropResult) {
        self.catalog = catalog
        self.onDrop = onDrop
    }

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) { monitors.append(monitor) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        source = nil
        feedback.hide()
    }

    private func handle(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            guard event.modifierFlags.contains(.shift) else { return }
            startedWithShift = true
            dragMoved = false
            startPoint = NSEvent.mouseLocation
            source = window(at: startPoint)
            let message: String
            let kind: DragFeedbackKind
            if !AccessibilityPermission.isGranted {
                message = "Enable Accessibility to read and group windows"
                kind = .warning
            } else if let source {
                message = "Dragging \(source.appName) — drop on another window"
                kind = .active
            } else {
                message = "Shift detected, but no app window was found"
                kind = .warning
            }
            feedback.present(message, kind: kind, at: startPoint)
            return
        }

        guard startedWithShift else { return }
        let currentPoint = NSEvent.mouseLocation
        if event.type == .leftMouseDragged {
            if hypot(currentPoint.x - startPoint.x, currentPoint.y - startPoint.y) > 12 { dragMoved = true }
            if dragMoved { feedback.follow(currentPoint) }
            return
        }

        guard event.type == .leftMouseUp else { return }
        defer { source = nil; startedWithShift = false; dragMoved = false }
        if hypot(currentPoint.x - startPoint.x, currentPoint.y - startPoint.y) > 12 { dragMoved = true }
        guard dragMoved else { feedback.hide(); return }
        guard let source else {
            feedback.present("Couldn’t identify the source window", kind: .warning, at: currentPoint, hideAfter: 2)
            return
        }
        guard let target = window(at: currentPoint, excluding: source.id), target.id != source.id else {
            feedback.present("Drop over another app window to group it", kind: .warning, at: currentPoint, hideAfter: 2)
            return
        }

        let result = onDrop(source, target)
        feedback.present(result.message,
                         kind: result.succeeded ? .success : .warning,
                         at: currentPoint,
                         hideAfter: 2)
    }

    private func window(at point: NSPoint, excluding: String? = nil) -> DiscoveredWindow? {
        let windows = catalog.scan()
        let height = NSScreen.screens.first(where: { $0.frame.contains(point) })?.frame.maxY
            ?? NSScreen.main?.frame.maxY ?? 0
        let axPoint = CGPoint(x: point.x, y: height - point.y)
        return windows.reversed().first { item in
            guard item.id != excluding else { return false }
            let bounds = item.bounds
            let left = CGFloat(bounds.x)
            let top = CGFloat(bounds.y)
            return axPoint.x >= left && axPoint.x <= left + CGFloat(bounds.width)
                && axPoint.y >= top && axPoint.y <= top + CGFloat(bounds.height)
        }
    }
}
