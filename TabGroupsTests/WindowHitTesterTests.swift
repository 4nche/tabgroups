import XCTest
@testable import TabGroups

final class WindowHitTesterTests: XCTestCase {
    private func window(_ number: CGWindowID, layer: Int = 0, x: Double, y: Double) -> ScreenWindow {
        ScreenWindow(number: number, processID: pid_t(number), layer: layer,
                     bounds: WindowBounds(x: x, y: y, width: 400, height: 300))
    }

    func testPicksTheFrontmostWindowUnderThePoint() {
        let frontToBack = [window(1, x: 0, y: 0), window(2, x: 100, y: 100)]
        XCTAssertEqual(WindowHitTester.windows(at: CGPoint(x: 150, y: 150), in: frontToBack).map(\.number), [1, 2])
    }

    func testSkipsExcludedWindowsSoTheDraggedOneIsLookedThrough() {
        let frontToBack = [window(1, x: 0, y: 0), window(2, x: 100, y: 100)]
        XCTAssertEqual(WindowHitTester.windows(at: CGPoint(x: 150, y: 150), in: frontToBack, excluding: [1])
            .first?.number, 2)
    }

    func testIgnoresWindowsThatDoNotContainThePoint() {
        XCTAssertTrue(WindowHitTester.windows(at: CGPoint(x: 900, y: 900), in: [window(1, x: 0, y: 0)]).isEmpty)
    }

    func testIgnoresMenuBarAndOverlayLayers() {
        let frontToBack = [window(9, layer: 25, x: 0, y: 0), window(2, x: 0, y: 0)]
        XCTAssertEqual(WindowHitTester.windows(at: CGPoint(x: 10, y: 10), in: frontToBack).map(\.number), [2])
    }
}
