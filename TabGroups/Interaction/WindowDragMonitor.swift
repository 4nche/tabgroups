import AppKit

final class WindowDragMonitor {
    private let catalog: WindowCatalog
    private var monitors: [Any] = []
    private var source: DiscoveredWindow?
    private var startedWithShift = false
    private var startPoint: NSPoint = .zero
    private let onDrop: (DiscoveredWindow, DiscoveredWindow) -> Void

    init(catalog: WindowCatalog, onDrop: @escaping (DiscoveredWindow, DiscoveredWindow) -> Void) {
        self.catalog = catalog
        self.onDrop = onDrop
    }

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp]
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
    }

    private func handle(_ event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        if event.type == .leftMouseDown {
            startedWithShift = shift
            startPoint = NSEvent.mouseLocation
            source = shift ? window(at: NSEvent.mouseLocation) : nil
            return
        }
        guard event.type == .leftMouseUp else { return }
        defer { source = nil; startedWithShift = false }
        let endPoint = NSEvent.mouseLocation
        guard startedWithShift, shift, let source,
              hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y) > 18 else { return }
        let target = window(at: endPoint, excluding: source.id)
        guard let target, target.id != source.id else { return }
        onDrop(source, target)
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
