import AppKit
import SwiftUI

struct TabItem: Identifiable, Equatable {
    let id: UUID
    let appName: String
    let title: String
    let icon: NSImage?
}

/// The full-width bar on top of a group: one tab per member window.
struct TabStripView: View {
    let tabs: [TabItem]
    let selectedID: UUID?
    let glass: GlassPreference.Variant
    let onSelect: (UUID) -> Void
    let onRemove: (UUID) -> Void

    private enum Metrics {
        static let cornerRadius: CGFloat = 16
        static let tabSpacing: CGFloat = 2
        static let edgePadding: CGFloat = 4
    }

    var body: some View {
        HStack(spacing: Metrics.tabSpacing) {
            ForEach(tabs) { tab in
                TabView(tab: tab, isSelected: tab.id == selectedID,
                        onSelect: { onSelect(tab.id) }, onRemove: { onRemove(tab.id) })
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.edgePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CGFloat(GroupGeometry.barHeight))
        // The surface fills the whole panel, which reaches down behind the member window; the tabs
        // stay in the top strip that the window does not cover.
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BarSurface(cornerRadius: Metrics.cornerRadius, glass: glass))
    }
}

/// The bar's surface. With the system's glass tint off it is see-through: macOS only gives a
/// window frosted glass over what lies behind it (other apps, the wallpaper), never the unblurred
/// kind, so that look is drawn here as a faint sheen. With a tint set it is the system's own glass.
private struct BarSurface: View {
    let cornerRadius: CGFloat
    let glass: GlassPreference.Variant

    private enum Sheen {
        static let top = Color.white.opacity(0.26)
        static let bottom = Color.white.opacity(0.10)
    }

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: cornerRadius, topTrailingRadius: cornerRadius)
        if glass == .clear {
            shape.fill(LinearGradient(colors: [Sheen.top, Sheen.bottom], startPoint: .top, endPoint: .bottom))
        } else if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.regularMaterial)
        }
    }
}

private struct TabView: View {
    let tab: TabItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    @State private var isHovered = false

    private enum Metrics {
        static let maxWidth: CGFloat = 220
        static let height: CGFloat = 28
        static let iconSize: CGFloat = 16
        static let cornerRadius: CGFloat = 7
        static let closeSize: CGFloat = 16
    }

    private var fill: Color {
        if isSelected { return Color.primary.opacity(0.10) }
        return isHovered ? Color.primary.opacity(0.05) : Color.clear
    }

    var body: some View {
        HStack(spacing: 6) {
            icon
            Text(tab.appName)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .lineLimit(1)
                .layoutPriority(1)
            Text(tab.title)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isHovered ? Color.primary : Color.secondary.opacity(0.6))
                    .frame(width: Metrics.closeSize, height: Metrics.closeSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove from group")
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: Metrics.maxWidth, alignment: .leading)
        .frame(height: Metrics.height)
        .background(fill, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius))
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius))
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
        .help("\(tab.appName) · \(tab.title)")
    }

    @ViewBuilder private var icon: some View {
        if let image = tab.icon {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Metrics.iconSize, height: Metrics.iconSize)
        } else {
            Image(systemName: "macwindow")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: Metrics.iconSize, height: Metrics.iconSize)
        }
    }
}
