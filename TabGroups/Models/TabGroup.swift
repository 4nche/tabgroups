import Foundation

struct TabGroup: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var displayIdentifier: String?
    var bounds: WindowBounds
    var members: [WindowReference]
    var selectedMemberID: UUID?

    init(
        id: UUID = UUID(),
        name: String = "Window Group",
        displayIdentifier: String? = nil,
        bounds: WindowBounds,
        members: [WindowReference],
        selectedMemberID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.displayIdentifier = displayIdentifier
        self.bounds = bounds
        self.members = members
        self.selectedMemberID = selectedMemberID ?? members.first?.id
    }
}
