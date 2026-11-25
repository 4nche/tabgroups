import ApplicationServices
import XCTest
@testable import TabGroups

final class LiveWindowRegistryTests: XCTestCase {
    private let memberID = UUID()
    private let bounds = WindowBounds(x: 0, y: 0, width: 400, height: 300)

    private func window(processID: pid_t, title: String) -> DiscoveredWindow {
        let reference = WindowReference(bundleIdentifier: "com.example.app", processID: processID,
                                        title: title, lastKnownBounds: bounds)
        return DiscoveredWindow(id: "\(processID)|\(title)", appName: "Example", reference: reference,
                                window: AXWindow(element: AXUIElementCreateApplication(processID), processID: processID))
    }

    private var member: WindowReference {
        WindowReference(id: memberID, bundleIdentifier: "com.example.app", title: "Old title", lastKnownBounds: bounds)
    }

    func testRememberedHandleIsReturnedWithoutRematching() {
        let registry = LiveWindowRegistry()
        let remembered = window(processID: 1, title: "Old title")
        registry.remember(remembered, memberID: memberID)

        XCTAssertEqual(registry.window(for: member, among: [])?.id, remembered.id)
    }

    func testPruneKeepsHandlesStillInTheScan() {
        let registry = LiveWindowRegistry()
        registry.remember(window(processID: 1, title: "Old title"), memberID: memberID)

        registry.prune(keeping: [window(processID: 1, title: "New title")])

        XCTAssertEqual(registry.window(for: member, among: [])?.id, "1|Old title")
    }

    func testPruneDropsHandlesMissingFromTheScan() {
        let registry = LiveWindowRegistry()
        registry.remember(window(processID: 1, title: "Old title"), memberID: memberID)
        registry.recordApplied(bounds, memberID: memberID)

        registry.prune(keeping: [window(processID: 2, title: "Other")])

        XCTAssertNil(registry.window(for: member, among: []))
        XCTAssertNil(registry.lastApplied[memberID])
    }
}
