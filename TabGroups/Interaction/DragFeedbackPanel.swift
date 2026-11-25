import AppKit
import SwiftUI

enum DragFeedbackKind {
    case active
    case success
    case warning

    var symbol: String {
        switch self {
        case .active: return "arrow.up.right"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .active: return .accentColor
        case .success: return .green
        case .warning: return .orange
        }
    }
}

private struct DragFeedbackView: View {
    let message: String
    let kind: DragFeedbackKind

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: kind.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(kind.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tab Groups")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .frame(width: 360, height: 58)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(.primary.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 6)
    }
}

/// A non-interactive status capsule that stays beside the pointer during a window drag.
final class DragFeedbackPanel: NSPanel {
    private var hideWorkItem: DispatchWorkItem?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 58),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    func present(_ message: String, kind: DragFeedbackKind, at point: NSPoint, hideAfter delay: TimeInterval? = nil) {
        hideWorkItem?.cancel()
        setContent(message, kind: kind)
        position(near: point)
        orderFrontRegardless()

        scheduleHide(after: delay)
    }

    func presentAtTop(_ message: String, kind: DragFeedbackKind, hideAfter delay: TimeInterval? = nil) {
        hideWorkItem?.cancel()
        setContent(message, kind: kind)
        let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        setFrameOrigin(NSPoint(x: visibleFrame.midX - frame.width / 2,
                               y: visibleFrame.maxY - frame.height - 10))
        orderFrontRegardless()

        scheduleHide(after: delay)
    }

    private func setContent(_ message: String, kind: DragFeedbackKind) {
        if let host = contentView as? NSHostingView<DragFeedbackView> {
            host.rootView = DragFeedbackView(message: message, kind: kind)
        } else {
            contentView = NSHostingView(rootView: DragFeedbackView(message: message, kind: kind))
        }
    }

    private func scheduleHide(after delay: TimeInterval?) {
        if let delay {
            let work = DispatchWorkItem { [weak self] in self?.orderOut(nil) }
            hideWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    func follow(_ point: NSPoint) {
        position(near: point)
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        orderOut(nil)
    }

    private func position(near point: NSPoint) {
        let size = frame.size
        let bounds = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? .zero
        let margin: CGFloat = 10
        let x = min(max(point.x + 18, bounds.minX + margin), bounds.maxX - size.width - margin)
        let y = min(max(point.y - size.height - 22, bounds.minY + margin), bounds.maxY - size.height - margin)
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
