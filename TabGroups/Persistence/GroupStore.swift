import Foundation
import Combine

final class GroupStore: ObservableObject {
    @Published private(set) var groups: [TabGroup] = []
    @Published private(set) var loadError: Error?

    private let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = GroupStore.defaultFileURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        load()
    }

    func replaceGroups(_ groups: [TabGroup]) throws {
        if let error = loadError as? GroupStoreError, case .unsupportedSchema = error {
            throw error
        }
        let document = GroupDocument(schemaVersion: GroupDocument.currentSchemaVersion, groups: groups)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)

        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        self.groups = groups
        loadError = nil
    }

    func upsert(_ group: TabGroup) throws {
        var updated = groups
        if let index = updated.firstIndex(where: { $0.id == group.id }) {
            updated[index] = group
        } else {
            updated.append(group)
        }
        try replaceGroups(updated)
    }

    func removeGroup(id: UUID) throws {
        try replaceGroups(groups.filter { $0.id != id })
    }

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let document = try JSONDecoder().decode(GroupDocument.self, from: data)
            switch document.schemaVersion {
            case GroupDocument.currentSchemaVersion:
                groups = document.groups
            case GroupDocument.windowBoundsSchemaVersion:
                groups = document.groups.map(GroupDocument.containerGroup(fromWindowBounds:))
            default:
                throw GroupStoreError.unsupportedSchema(document.schemaVersion)
            }
        } catch {
            loadError = error
        }
    }

    static var defaultFileURL: URL {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return supportDirectory.appendingPathComponent("TabGroups/groups.json")
    }
}

private struct GroupDocument: Codable {
    /// Version 2: `TabGroup.bounds` is the whole container, tab bar included.
    static let currentSchemaVersion = 2
    /// Version 1: `TabGroup.bounds` was the member window's own rectangle.
    static let windowBoundsSchemaVersion = 1

    /// Grows a version 1 group upward so its windows keep their place under the new bar.
    static func containerGroup(fromWindowBounds group: TabGroup) -> TabGroup {
        var migrated = group
        migrated.bounds = WindowBounds(x: group.bounds.x,
                                       y: group.bounds.y - GroupGeometry.barHeight,
                                       width: group.bounds.width,
                                       height: group.bounds.height + GroupGeometry.barHeight)
        return migrated
    }

    var schemaVersion: Int
    var groups: [TabGroup]
}

enum GroupStoreError: LocalizedError {
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "This Tab Groups data uses an unsupported format version (\(version)). The saved file was left untouched."
        }
    }
}
