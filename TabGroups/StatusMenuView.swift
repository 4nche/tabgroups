import AppKit
import SwiftUI

struct StatusMenuView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var coordinator: GroupCoordinator

    var body: some View {
        Button("Show Groups") {
            openWindow(id: "groups")
        }

        Button("Create a Group…") {
            openWindow(id: "groups")
        }

        Button("Accessibility Permission…") {
            coordinator.permissionWasGranted()
            AccessibilityPermission.openSettings()
        }

        Divider()

        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")

        Button("Quit Tab Groups") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

struct GroupsWindowView: View {
    @ObservedObject var coordinator: GroupCoordinator
    @ObservedObject var store: GroupStore
    @State private var selectedWindowIDs: [String] = []
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WindowSelectionPicker(
                coordinator: coordinator,
                selectedWindowIDs: $selectedWindowIDs,
                searchText: $searchText
            )

            Divider()

            if store.groups.isEmpty {
                ContentUnavailableView("No groups yet", systemImage: "rectangle.on.rectangle",
                                       description: Text("Select two or more windows above and click Group."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.groups) { group in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.name).font(.system(size: 13, weight: .medium))
                            Text("\(group.members.count) windows · \(group.members.compactMap(\.title).joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if let selected = group.selectedMemberID {
                            Button("Show") { coordinator.select(groupID: group.id, memberID: selected) }
                                .buttonStyle(FilledButtonStyle())
                        }
                        Button(role: .destructive) { coordinator.deleteGroup(group) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 560)
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

private struct WindowSelectionPicker: View {
    @ObservedObject var coordinator: GroupCoordinator
    @Binding var selectedWindowIDs: [String]
    @Binding var searchText: String

    private var visibleWindows: [DiscoveredWindow] {
        coordinator.availableWindows
            .filter { window in
                searchText.isEmpty
                    || window.appName.localizedCaseInsensitiveContains(searchText)
                    || (window.reference.title ?? "").localizedCaseInsensitiveContains(searchText)
            }
            .sorted {
                if $0.appName != $1.appName { return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
                return ($0.reference.title ?? "").localizedCaseInsensitiveCompare($1.reference.title ?? "") == .orderedAscending
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("Create a Group").font(.title3.weight(.medium))
                Spacer()
                Text("\(selectedWindowIDs.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Search apps and windows", text: $searchText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))

            if visibleWindows.isEmpty {
                ContentUnavailableView("No accessible windows", systemImage: "macwindow",
                                       description: Text("Open an app window or enable Accessibility access."))
                    .frame(height: 130)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(visibleWindows) { window in
                            windowRow(window)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 190)
            }

            HStack {
                Text("The first selected window sets where the group sits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Group \(selectedWindowIDs.count) Windows") {
                    coordinator.createGroup(windowIDs: selectedWindowIDs)
                    selectedWindowIDs = []
                }
                .buttonStyle(FilledButtonStyle(tone: .accent))
                .disabled(selectedWindowIDs.count < 2)
            }
        }
    }

    private func windowRow(_ window: DiscoveredWindow) -> some View {
        let selected = selectedWindowIDs.contains(window.id)
        return Button {
            selectedWindowIDs = selected
                ? selectedWindowIDs.filter { $0 != window.id }
                : selectedWindowIDs + [window.id]
        } label: {
            HStack(spacing: 9) {
                if let processID = window.reference.processID,
                   let icon = NSRunningApplication(processIdentifier: pid_t(processID))?.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                } else {
                    Image(systemName: "macwindow")
                        .frame(width: 22, height: 22)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(window.appName).font(.system(size: 12, weight: .medium))
                    Text(window.reference.title ?? "Window")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .background(selected ? Color.accentColor.opacity(0.1) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}
