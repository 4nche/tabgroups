import CoreGraphics
import Foundation

enum TabHitTester {
    /// The tab under a point given in the panel's AppKit coordinates (origin bottom-left).
    /// `frames` are the tabs' rectangles in the bar's own space (origin top-left).
    static func tab(atWindowPoint point: CGPoint, panelHeight: CGFloat, frames: [UUID: CGRect]) -> UUID? {
        let flipped = CGPoint(x: point.x, y: panelHeight - point.y)
        return frames.first { $0.value.contains(flipped) }?.key
    }
}
