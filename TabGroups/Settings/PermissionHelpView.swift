import SwiftUI

struct PermissionHelpView: View {
    let hasPermission: Bool
    let onRequest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(hasPermission ? "Accessibility is enabled" : "Accessibility permission needed",
                  systemImage: hasPermission ? "checkmark.circle.fill" : "lock.shield")
                .font(.system(size: 13, weight: .medium))
            Text("Tab Groups needs Accessibility access to find app windows, move and resize them, and bring the selected tab forward. Your windows stay in their original apps.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Open Accessibility Settings") {
                onRequest()
                AccessibilityPermission.openSettings()
            }
            .buttonStyle(FilledButtonStyle())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }
}
