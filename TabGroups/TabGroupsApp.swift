import SwiftUI

@main
struct TabGroupsApp: App {
    @StateObject private var coordinator: GroupCoordinator

    init() {
        let coordinator = GroupCoordinator()
        _coordinator = StateObject(wrappedValue: coordinator)
        coordinator.start()
    }

    var body: some Scene {
        MenuBarExtra("Tab Groups", systemImage: "rectangle.on.rectangle") {
            StatusMenuView(coordinator: coordinator)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            Form {
                Section("Mission Control") {
                    Toggle("Show the tab switcher", isOn: $coordinator.showTabSwitcher)
                    Toggle("Show only the selected window in each group", isOn: Binding(
                        get: { !coordinator.showAllWindowsInMissionControl },
                        set: { coordinator.showAllWindowsInMissionControl = !$0 }
                    ))
                }
            }
            .formStyle(.grouped)
            .toggleStyle(.checkbox)
            .frame(width: 450)
            .fixedSize(horizontal: false, vertical: true)
        }

        Window("Tab Groups", id: "groups") {
            GroupsWindowView(coordinator: coordinator, store: coordinator.store)
        }
        .defaultSize(width: 440, height: 340)
    }
}
