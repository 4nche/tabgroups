import Foundation
import XCTest
@testable import TabGroups

final class GroupStoreTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        fileURL = directory.appendingPathComponent("groups.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSavesAndLoadsMultipleGroupsInOrder() throws {
        let first = makeGroup("First")
        let second = makeGroup("Second")
        try GroupStore(fileURL: fileURL).replaceGroups([first, second])

        let loaded = GroupStore(fileURL: fileURL)
        XCTAssertEqual(loaded.groups, [first, second])
    }

    func testUnknownSchemaIsReportedAndPreserved() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = Data("{\"schemaVersion\":99,\"groups\":[]}".utf8)
        try original.write(to: fileURL)

        let store = GroupStore(fileURL: fileURL)
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.replaceGroups([makeGroup("New")]))
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
    }

    private func makeGroup(_ name: String) -> TabGroup {
        TabGroup(name: name, bounds: WindowBounds(x: 10, y: 20, width: 800, height: 600), members: [])
    }
}
