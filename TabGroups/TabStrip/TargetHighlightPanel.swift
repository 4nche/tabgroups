import AppKit
import SwiftUI

/// The blue outline drawn around the window a Shift-drag would group with.
final class TargetHighlightPanel: NSPanel {
    private enum Metrics {
        static let cornerRadius: CGFloat = 14
        static let lineWidth: CGFloat = 3
        static let fillOpacity: Double = 0.10
    }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        let shape = RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
        contentView = NSHostingView(rootView:
            shape.fill(Color.accentColor.opacity(Metrics.fillOpacity))
                .overlay(shape.strokeBorder(Color.accentColor, lineWidth: Metrics.lineWidth)))
    }

    func show(around bounds: WindowBounds) {
        setFrame(ScreenGeometry.appKitRect(for: bounds), display: true)
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }
}
