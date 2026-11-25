import CoreGraphics

/// Pure rules for a group's container: a tab bar on top, the member windows beneath it.
/// All `WindowBounds` use Accessibility coordinates (origin top-left of the main display, y down).
enum GroupGeometry {
    static let barHeight: Double = 36
    static let tolerance: Double = 3
    /// How far the bar's surface reaches behind the member window; larger than any window corner radius.
    static let cornerOverlap: Double = 28

    static func contentBounds(of container: WindowBounds) -> WindowBounds {
        WindowBounds(x: container.x,
                     y: container.y + barHeight,
                     width: container.width,
                     height: max(0, container.height - barHeight))
    }

    static func barBounds(of container: WindowBounds) -> WindowBounds {
        WindowBounds(x: container.x, y: container.y, width: container.width, height: barHeight)
    }

    /// The bar's panel: the bar plus a strip that reaches down behind the top of the member window,
    /// so the bar's surface shows through the gaps left by the window's rounded corners.
    static func barBackdropBounds(of container: WindowBounds) -> WindowBounds {
        let overlap = min(cornerOverlap, contentBounds(of: container).height)
        return WindowBounds(x: container.x, y: container.y, width: container.width, height: barHeight + overlap)
    }

    /// The container for a member that now sits at `member`: the bar goes above the member,
    /// unless that would push it past the usable top of the screen.
    static func container(adopting member: WindowBounds, visibleTop: Double) -> WindowBounds {
        let grown = WindowBounds(x: member.x,
                                 y: member.y - barHeight,
                                 width: member.width,
                                 height: member.height + barHeight)
        return clamped(grown, visibleTop: visibleTop)
    }

    /// The container after a member was moved or resized from outside. A pure move carries the
    /// container along at its current size; a resize makes the member's rectangle the new content.
    static func container(_ current: WindowBounds, afterMember reported: WindowBounds,
                          lastApplied: WindowBounds?, visibleTop: Double) -> WindowBounds {
        guard let lastApplied,
              abs(reported.width - lastApplied.width) + abs(reported.height - lastApplied.height) <= tolerance else {
            return container(adopting: reported, visibleTop: visibleTop)
        }
        // Measured from where the content sits now, so a repeated or late report cannot move it twice.
        let content = contentBounds(of: current)
        let moved = current.translated(dx: reported.x - content.x, dy: reported.y - content.y)
        return shiftedIntoView(moved, visibleTop: visibleTop)
    }

    /// Lowers the top edge to `visibleTop` when needed, keeping the bottom edge in place.
    static func clamped(_ container: WindowBounds, visibleTop: Double) -> WindowBounds {
        guard container.y < visibleTop else { return container }
        let bottom = container.y + container.height
        return WindowBounds(x: container.x,
                            y: visibleTop,
                            width: container.width,
                            height: max(barHeight, bottom - visibleTop))
    }

    /// Moves the container down to `visibleTop` when its bar would be above it. Size is unchanged.
    static func shiftedIntoView(_ container: WindowBounds, visibleTop: Double) -> WindowBounds {
        guard container.y < visibleTop else { return container }
        return container.translated(dx: 0, dy: visibleTop - container.y)
    }

    /// True when `reported` is the rectangle the window took the last time we placed it.
    static func isEcho(_ reported: WindowBounds, of lastApplied: WindowBounds?) -> Bool {
        guard let lastApplied else { return false }
        return reported.distance(to: lastApplied) <= tolerance
    }

    static func appKitRect(for bounds: WindowBounds, mainDisplayHeight: Double) -> CGRect {
        CGRect(x: bounds.x,
               y: mainDisplayHeight - bounds.y - bounds.height,
               width: bounds.width,
               height: bounds.height)
    }
}

extension WindowBounds {
    func translated(dx: Double, dy: Double) -> WindowBounds {
        WindowBounds(x: x + dx, y: y + dy, width: width, height: height)
    }

    func distance(to other: WindowBounds) -> Double {
        abs(x - other.x) + abs(y - other.y) + abs(width - other.width) + abs(height - other.height)
    }
}
