import AppKit
import os

/// Hold Shift, drag a window onto another, let go: the two are grouped.
/// The dragged window is read from the system at the click and kept as a live handle.
final class ShiftDragMonitor {
    private struct Drag {
        let source: AXWindow
        let sourceWindowNumber: CGWindowID
        let startBounds: WindowBounds
        var hasMoved = false
        var lastLookup: TimeInterval = 0
        var target: (target: DropTarget, outline: WindowBounds)?
        /// Windows already resolved during this drag, by window number. `nil` = not a usable target.
        var resolved: [CGWindowID: (target: DropTarget, outline: WindowBounds)?] = [:]
    }

    private static let lookupInterval: TimeInterval = 0.08
    private static let log = Logger(subsystem: "com.4nche.TabGroups", category: "shift-drag")

    private weak var coordinator: GroupCoordinator?
    private let highlight = TargetHighlightPanel()
    private var monitor: Any?
    private var drag: Drag?

    init(coordinator: GroupCoordinator) {
        self.coordinator = coordinator
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    func start() {
        guard monitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
    }

    // Events reach a global monitor a little late. Every decision therefore uses the state carried
    // by the event itself: the keyboard and mouse may already have changed by the time it is handled
    // (a queued drag event handled just after release, or Shift let go a moment after the button).
    private var pointer: CGPoint { ScreenGeometry.accessibilityPoint(fromAppKit: NSEvent.mouseLocation) }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown: begin(shiftIsDown: event.modifierFlags.contains(.shift))
        case .leftMouseDragged: update(force: false, shiftIsDown: event.modifierFlags.contains(.shift))
        case .flagsChanged: update(force: true, shiftIsDown: event.modifierFlags.contains(.shift))
        case .leftMouseUp: finish(shiftIsDown: event.modifierFlags.contains(.shift))
        default: break
        }
    }

    private func begin(shiftIsDown: Bool) {
        cancel()
        guard shiftIsDown, AccessibilityPermission.isGranted else { return }
        let point = pointer
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        guard let clicked = WindowHitTester.windows(at: point, in: ScreenGeometry.onScreenWindows()).first,
              clicked.processID != ownProcess else {
            Self.log.notice("begin: no app window under the pointer")
            return
        }
        let underPointer = AXWindow.window(at: point).flatMap { $0.processID == clicked.processID ? $0 : nil }
        guard let source = underPointer ?? AXWindow.window(ofProcess: clicked.processID, closestTo: clicked.bounds),
              let startBounds = source.bounds() else {
            Self.log.notice("begin: could not read the clicked window (pid \(clicked.processID))")
            return
        }
        source.setMessagingTimeout(LiveWindowRegistry.messagingTimeout)
        drag = Drag(source: source, sourceWindowNumber: clicked.number, startBounds: startBounds)
    }

    private func update(force: Bool, shiftIsDown: Bool) {
        guard var current = drag else { return }
        // Letting go of Shift cancels. (A drag whose mouse-up was lost is cleared by the next click.)
        guard shiftIsDown else { return cancel() }
        guard force || ProcessInfo.processInfo.systemUptime - current.lastLookup >= Self.lookupInterval else { return }
        // Stamped after the work, so a slow lookup cannot let queued events pile straight through.
        defer {
            if drag != nil {
                current.lastLookup = ProcessInfo.processInfo.systemUptime
                drag = current
            }
        }

        if !current.hasMoved, let bounds = current.source.bounds() {
            switch DragMotion.classify(from: current.startBounds, to: bounds) {
            case .resized: return cancel()   // a Shift-resize also shifts the origin; it is not a drag
            case .moved: current.hasMoved = true
            case .still: break
            }
        }
        guard current.hasMoved else { return }
        current.target = target(at: pointer, for: &current)
        if let outline = current.target?.outline {
            highlight.show(around: outline)
        } else {
            highlight.hide()
        }
    }

    private func finish(shiftIsDown: Bool) {
        guard let finished = drag else { return }
        cancel()
        guard finished.hasMoved, shiftIsDown, let target = finished.target?.target else {
            Self.log.notice("finish: no drop (moved \(finished.hasMoved), shift \(shiftIsDown), target \(finished.target != nil))")
            return
        }
        Self.log.notice("finish: dropping")
        coordinator?.completeDrop(of: finished.source, onto: target)
    }

    private func cancel() {
        drag = nil
        highlight.hide()
    }

    /// The frontmost usable window under the pointer, looking through the dragged window and through
    /// everything that belongs to the dragged window's own group.
    private func target(at point: CGPoint, for drag: inout Drag) -> (target: DropTarget, outline: WindowBounds)? {
        guard let coordinator else { return nil }
        let candidates = WindowHitTester.windows(at: point, in: ScreenGeometry.onScreenWindows(),
                                                 excluding: [drag.sourceWindowNumber])
        let sourceGroup = coordinator.groupID(containing: drag.source)
        for candidate in candidates {
            let resolved: (target: DropTarget, outline: WindowBounds)?
            if let cached = drag.resolved[candidate.number] {
                resolved = cached
            } else {
                resolved = resolve(candidate, source: drag.source, coordinator: coordinator)
                drag.resolved[candidate.number] = .some(resolved)
            }
            guard let resolved else { continue }
            if case .group(let id) = resolved.target {
                if id == sourceGroup { continue }
                // A group may have moved since it was cached; outline where it is now.
                return (resolved.target, coordinator.containerBounds(ofGroup: id) ?? resolved.outline)
            }
            return (resolved.target, candidate.bounds)
        }
        return nil
    }

    private func resolve(_ candidate: ScreenWindow, source: AXWindow,
                         coordinator: GroupCoordinator) -> (target: DropTarget, outline: WindowBounds)? {
        if candidate.processID == ProcessInfo.processInfo.processIdentifier {
            // One of ours: only a group's bar counts, and it stands for its group.
            guard let groupID = coordinator.groupID(forBarWindowNumber: Int(candidate.number)),
                  let bounds = coordinator.containerBounds(ofGroup: groupID) else { return nil }
            return (.group(groupID), bounds)
        }
        guard let window = AXWindow.window(ofProcess: candidate.processID, closestTo: candidate.bounds),
              let bounds = window.bounds(),
              !window.isSameWindow(as: source.element),   // never group a window with itself
              bounds.distance(to: candidate.bounds) <= GroupGeometry.tolerance * 4 else { return nil }
        if let groupID = coordinator.groupID(containing: window),
           let container = coordinator.containerBounds(ofGroup: groupID) {
            return (.group(groupID), container)
        }
        return (.window(window), candidate.bounds)
    }
}
