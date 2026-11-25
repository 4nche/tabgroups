import SwiftUI

/// Borderless button: a filled background that darkens on press. No outline, no scaling.
struct FilledButtonStyle: ButtonStyle {
    enum Tone { case quiet, accent }

    var tone: Tone = .quiet
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(background(pressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 7))
            .opacity(isEnabled ? 1 : 0.45)
    }

    private var foreground: Color {
        tone == .accent ? .white : .primary
    }

    private func background(pressed: Bool) -> Color {
        switch tone {
        case .accent: return Color.accentColor.opacity(pressed ? 0.75 : 1)
        case .quiet: return Color.primary.opacity(pressed ? 0.16 : 0.08)
        }
    }
}
