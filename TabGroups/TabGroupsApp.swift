import SwiftUI

@main
struct TabGroupsApp: App {
    @State private var coordinator: GroupCoordinator

    init() {
        let coordinator = GroupCoordinator()
        _coordinator = State(initialValue: coordinator)
        coordinator.start()
    }

    var body: some Scene {
        MenuBarExtra("Tab Groups", systemImage: "rectangle.on.rectangle") {
            StatusMenuView(coordinator: coordinator)
        }
        .menuBarExtraStyle(.menu)

        Window("Tab Groups", id: "groups") {
            GroupsWindowView(coordinator: coordinator)
        }
        .defaultSize(width: 440, height: 340)
    }
}
