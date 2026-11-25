import AppKit
import SwiftUI

/// The bar's glass surface. It is its own click-through panel, taller than the bar, and always sits
/// beneath the group's front window: the window covers the part that reaches behind it, and only the
/// gaps left by the window's rounded corners let the glass show. Because it never takes a click, the
/// window server never raises it in front of the app window.
final class BarBackdropPanel: NSPanel {
    private static let cornerRadius: CGFloat = 16

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .normal
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        contentView = NSHostingView(rootView: BarSurface(cornerRadius: Self.cornerRadius))
    }

    func place(at container: WindowBounds) {
        setFrame(ScreenGeometry.appKitRect(for: GroupGeometry.barBackdropBounds(of: container)), display: true)
    }
}

/// The system's frosted Liquid Glass, or the regular material before macOS 26.
private struct BarSurface: View {
    let cornerRadius: CGFloat

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: cornerRadius, topTrailingRadius: cornerRadius)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.regularMaterial)
        }
    }
}
