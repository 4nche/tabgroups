import AppKit

struct DragDropResult {
    var message: String
    var succeeded: Bool
}

private struct WindowHit {
    let window: DiscoveredWindow
    let windowNumber: CGWindowID
}

private struct ModeActivationSequence {
    private(set) var progress = 0
    private var startedAt: TimeInterval?
    private let interval: TimeInterval = 3

    mutating func register(_ key: Key, at time: TimeInterval) -> Bool {
        if let startedAt, time - startedAt > interval { reset() }

        let expected: Key = progress.isMultiple(of: 2) ? .shift : .tilde
        guard key == expected else {
            reset()
            if key == .shift {
                startedAt = time
                progress = 1
            }
            return false
        }

        if progress == 0 { startedAt = time }
        progress += 1
        if progress == 6 {
            reset()
            return true
        }
        return false
    }

    mutating func reset() {
        progress = 0
        startedAt = nil
    }

    enum Key { case shift, tilde }
}

final class WindowDragMonitor {
    private let catalog: WindowCatalog
    private let feedback = DragFeedbackPanel()
    private let modeBanner = DragFeedbackPanel()
    private var monitors: [Any] = []
    private var source: DiscoveredWindow?
    private var sourceWindowNumber: CGWindowID?
    private var dragWindows: [DiscoveredWindow] = []
    private var isTrackingDrag = false
    private var startPoint: NSPoint = .zero
    private var dragMoved = false
    private var hoverTargetID: String?
    private var lastHoverHitTest = 0.0
    private var activationSequence = ModeActivationSequence()
    private var shiftIsDown = false
    private var tabGroupModeActive = false
    private let onDrop: (DiscoveredWindow, DiscoveredWindow) -> DragDropResult

    init(catalog: WindowCatalog, onDrop: @escaping (DiscoveredWindow, DiscoveredWindow) -> DragDropResult) {
        self.catalog = catalog
        self.onDrop = onDrop
    }

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged, .keyDown]
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
        sourceWindowNumber = nil
        dragWindows = []
        tabGroupModeActive = false
        feedback.hide()
        modeBanner.hide()
    }

    private func handle(_ event: NSEvent) {
        if event.type == .flagsChanged || event.type == .keyDown {
            handleKeyboard(event)
            return
        }

        if event.type == .leftMouseDown {
            guard tabGroupModeActive else { return }
            isTrackingDrag = true
            dragMoved = false
            hoverTargetID = nil
            lastHoverHitTest = 0
            startPoint = NSEvent.mouseLocation
            dragWindows = catalog.scan()
            let hit = window(at: startPoint)
            source = hit?.window
            sourceWindowNumber = hit?.windowNumber
            let message: String
            let kind: DragFeedbackKind
            if !AccessibilityPermission.isGranted {
                message = "Enable Accessibility to read and group windows"
                kind = .warning
            } else if let source {
                message = "Dragging \(source.appName) — drop on another window"
                kind = .active
            } else {
                message = "No app window found at drag start"
                kind = .warning
            }
            feedback.present(message, kind: kind, at: startPoint)
            return
        }

        guard isTrackingDrag else { return }
        let currentPoint = NSEvent.mouseLocation
        if event.type == .leftMouseDragged {
            if hypot(currentPoint.x - startPoint.x, currentPoint.y - startPoint.y) > 12 { dragMoved = true }
            if dragMoved {
                feedback.follow(currentPoint)
                let now = ProcessInfo.processInfo.systemUptime
                guard now - lastHoverHitTest >= 0.1 else { return }
                lastHoverHitTest = now
                let target = source.flatMap { _ in window(at: currentPoint, excluding: sourceWindowNumber)?.window }
                let otherTarget = target
                if otherTarget?.id != hoverTargetID {
                    hoverTargetID = otherTarget?.id
                    if let source, let target = otherTarget {
                        feedback.present("Release to group \(source.appName) with \(target.appName)",
                                         kind: .active,
                                         at: currentPoint)
                    } else {
                        feedback.present("Drag over another app window to group", kind: .active, at: currentPoint)
                    }
                }
            }
            return
        }

        guard event.type == .leftMouseUp else { return }
        defer {
            source = nil
            sourceWindowNumber = nil
            dragWindows = []
            isTrackingDrag = false
            dragMoved = false
            hoverTargetID = nil
            lastHoverHitTest = 0
        }
        if hypot(currentPoint.x - startPoint.x, currentPoint.y - startPoint.y) > 12 { dragMoved = true }
        guard dragMoved else { feedback.hide(); return }
        guard let source else {
            feedback.present("Couldn’t identify the source window", kind: .warning, at: currentPoint, hideAfter: 2)
            return
        }
        guard let target = window(at: currentPoint, excluding: sourceWindowNumber)?.window,
              target.id != source.id else {
            feedback.present("No other app window detected here", kind: .warning, at: currentPoint, hideAfter: 2)
            return
        }

        let result = onDrop(source, target)
        feedback.present(result.message,
                         kind: result.succeeded ? .success : .warning,
                         at: currentPoint,
                         hideAfter: 2)
    }

    private func handleKeyboard(_ event: NSEvent) {
        if event.type == .flagsChanged {
            let isDown = event.modifierFlags.contains(.shift)
            let shiftWasPressed = isDown && !shiftIsDown
            shiftIsDown = isDown
            guard shiftWasPressed, !tabGroupModeActive else { return }
            if activationSequence.register(.shift, at: event.timestamp) { activateTabGroupMode() }
            return
        }

        if event.keyCode == 53 {
            guard tabGroupModeActive else { activationSequence.reset(); return }
            tabGroupModeActive = false
            isTrackingDrag = false
            source = nil
            sourceWindowNumber = nil
            dragWindows = []
            feedback.hide()
            modeBanner.presentAtTop("Tab Group Mode Off", kind: .active, hideAfter: 1.4)
            return
        }

        if event.characters == "~", event.modifierFlags.contains(.shift), !tabGroupModeActive {
            if activationSequence.register(.tilde, at: event.timestamp) { activateTabGroupMode() }
        } else if !tabGroupModeActive {
            activationSequence.reset()
        }
    }

    private func activateTabGroupMode() {
        activationSequence.reset()
        tabGroupModeActive = true
        modeBanner.presentAtTop("Tab Group Mode Active  •  Drag windows to group  •  Esc to exit", kind: .active)
    }

    private func window(at point: NSPoint, excluding excludedWindowNumber: CGWindowID? = nil) -> WindowHit? {
        let windows = dragWindows
        // AX uses the primary display's top-left coordinate origin. Using the
        // hovered display's height works on a single display but offsets every
        // hit test on secondary displays (and can miss windows on the primary).
        let primaryDisplay = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID()
        }
        let height = primaryDisplay?.frame.maxY ?? NSScreen.screens.first?.frame.maxY ?? 0
        let axPoint = CGPoint(x: point.x, y: height - point.y)
        // The accessibility scan is grouped by running app, so its array order
        // is not screen stacking order. Use WindowServer's front-to-back list
        // to choose the window actually under the pointer, then resolve it to
        // the matching accessible window.
        guard let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            guard let window = windows.first(where: { contains(axPoint, in: $0.bounds) }) else { return nil }
            return WindowHit(window: window, windowNumber: 0)
        }
        for info in onScreen {
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid != ProcessInfo.processInfo.processIdentifier,
                  let rawWindowNumber = info[kCGWindowNumber as String] as? NSNumber,
                  let windowNumber = CGWindowID(exactly: rawWindowNumber.intValue),
                  windowNumber != excludedWindowNumber,
                  let rawBounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary), bounds.contains(axPoint) else { continue }
            let candidates = windows.filter { $0.reference.processID == pid && contains(axPoint, in: $0.bounds) }
            guard let window = candidates.min(by: {
                boundsDistance($0.bounds, to: bounds) < boundsDistance($1.bounds, to: bounds)
            }) else { return nil }
            return WindowHit(window: window, windowNumber: windowNumber)
        }
        return nil
    }

    private func contains(_ point: CGPoint, in bounds: WindowBounds) -> Bool {
        point.x >= bounds.x && point.x <= bounds.x + bounds.width
            && point.y >= bounds.y && point.y <= bounds.y + bounds.height
    }

    private func boundsDistance(_ bounds: WindowBounds, to rect: CGRect) -> CGFloat {
        abs(CGFloat(bounds.x) - rect.minX) + abs(CGFloat(bounds.y) - rect.minY)
            + abs(CGFloat(bounds.width) - rect.width) + abs(CGFloat(bounds.height) - rect.height)
    }
}
