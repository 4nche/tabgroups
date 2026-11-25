import AppKit
import SwiftUI

struct StatusMenuView: View {
    @Environment(\.openWindow) private var openWindow
    let coordinator: GroupCoordinator

    var body: some View {
        Button("Show Groups") {
            openWindow(id: "groups")
        }

        Button("Accessibility Permission…") {
            coordinator.permissionWasGranted()
            AccessibilityPermission.openSettings()
        }

        Divider()

        Button("Quit Tab Groups") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

struct GroupsWindowView: View {
    @Bindable var coordinator: GroupCoordinator

    var body: some View {
        Group {
            if coordinator.store.groups.isEmpty {
                ContentUnavailableView {
                    Label("No tab groups yet", systemImage: "rectangle.on.rectangle")
                } description: {
                    Text("Hold Shift and drag one app window onto another to create a group.")
                }
            } else {
                List(coordinator.store.groups) { group in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.name).font(.headline)
                            Text("\(group.members.count) windows · \(group.members.compactMap(\.title).joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if let selected = group.selectedMemberID {
                            Button("Show") { coordinator.select(groupID: group.id, memberID: selected) }
                                .buttonStyle(.bordered)
                        }
                        Button(role: .destructive) { coordinator.deleteGroup(group) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 260)
        .padding()
        .safeAreaInset(edge: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                PermissionHelpView(hasPermission: AccessibilityPermission.isGranted) {
                    coordinator.permissionWasGranted()
                }
                if let message = coordinator.statusMessage {
                    Label(message, systemImage: "info.circle")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                UnmatchedWindowView(
                    members: coordinator.unmatchedMembers,
                    candidates: coordinator.availableWindows,
                    onAssign: coordinator.reassign(memberID:to:),
                    onRemove: coordinator.removeMember(groupID:memberID:)
                )
            }
            .padding(.horizontal)
            .padding(.top)
        }
    }
}
