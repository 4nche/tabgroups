import ApplicationServices
import XCTest
@testable import TabGroups

final class WindowReferenceMatchingTests: XCTestCase {
    func testCurrentProcessHintOutranksAnOtherwiseSimilarWindow() {
        let saved = reference(pid: 100, title: "Editor", x: 20)
        let sameProcess = discovered(reference(pid: 100, title: "Untitled", x: 500), key: "current")
        let similarOther = discovered(reference(pid: 200, title: "Editor", x: 20), key: "similar")

        guard case .matched(let result) = WindowReferenceMatcher.match(saved, among: [similarOther, sameProcess]) else {
            return XCTFail("Expected a unique match")
        }
        XCTAssertEqual(result.id, "current")
    }

    func testEqualDuplicateWindowsRemainAmbiguous() {
        let saved = reference(pid: nil, title: "Editor", x: 20)
        let first = discovered(reference(pid: 100, title: "Editor", x: 20), key: "first")
        let second = discovered(reference(pid: 200, title: "Editor", x: 20), key: "second")

        guard case .ambiguous(let matches) = WindowReferenceMatcher.match(saved, among: [first, second]) else {
            return XCTFail("Expected duplicate windows to remain ambiguous")
        }
        XCTAssertEqual(matches.count, 2)
    }

    private func reference(pid: Int32?, title: String, x: Double) -> WindowReference {
        WindowReference(
            bundleIdentifier: "com.example.editor",
            processID: pid,
            title: title,
            lastKnownBounds: WindowBounds(x: x, y: 30, width: 800, height: 600)
        )
    }

    private func discovered(_ reference: WindowReference, key: String) -> DiscoveredWindow {
        DiscoveredWindow(
            id: key,
            appName: "Editor",
            reference: reference,
            window: AXWindow(element: AXUIElementCreateSystemWide(), processID: pid_t(reference.processID ?? 0))
        )
    }
}
