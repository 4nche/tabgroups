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
            guard document.schemaVersion == GroupDocument.currentSchemaVersion else {
                throw GroupStoreError.unsupportedSchema(document.schemaVersion)
            }
            groups = document.groups
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
    static let currentSchemaVersion = 1

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
