import Foundation
import ApplicationServices
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

final class WindowGroupFactoryTests: XCTestCase {
    func testFirstSelectedWindowProvidesGroupBoundsAndInitialSelection() {
        let first = makeWindow("Calendar", title: "Week", x: 40, key: "first")
        let second = makeWindow("Mail", title: "Inbox", x: 900, key: "second")

        let group = WindowGroupFactory.make(from: [first, second], displayIdentifier: "main")

        XCTAssertEqual(group?.bounds, first.bounds)
        XCTAssertEqual(group?.selectedMemberID, first.reference.id)
        XCTAssertEqual(group?.members.map(\.id), [first.reference.id, second.reference.id])
        XCTAssertEqual(group?.name, "Calendar Group")
    }

    func testGroupRequiresAtLeastTwoWindows() {
        let first = makeWindow("Calendar", title: "Week", x: 40, key: "first")

        XCTAssertNil(WindowGroupFactory.make(from: [first], displayIdentifier: "main"))
    }

    private func makeWindow(_ appName: String, title: String, x: Double, key: String) -> DiscoveredWindow {
        let reference = WindowReference(
            bundleIdentifier: "com.example.\(appName.lowercased())",
            processID: 123,
            title: title,
            lastKnownBounds: WindowBounds(x: x, y: 20, width: 800, height: 600)
        )
        return DiscoveredWindow(
            id: key,
            appName: appName,
            reference: reference,
            window: AXWindow(element: AXUIElementCreateSystemWide(), processID: 123)
        )
    }
}
