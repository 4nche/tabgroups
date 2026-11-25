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

        Window("Tab Groups", id: "groups") {
            GroupsWindowView(coordinator: coordinator, store: coordinator.store)
        }
        .defaultSize(width: 440, height: 340)
    }
}
