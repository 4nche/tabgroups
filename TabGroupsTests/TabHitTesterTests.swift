import XCTest
@testable import TabGroups

final class TabHitTesterTests: XCTestCase {
    private let first = UUID()
    private let second = UUID()
    private var frames: [UUID: CGRect] {
        [first: CGRect(x: 4, y: 4, width: 200, height: 28), second: CGRect(x: 206, y: 4, width: 200, height: 28)]
    }

    func testPointInsideATabFindsThatTab() {
        // Panel is 36pt tall; AppKit's y runs up from the bottom, the frames' y runs down from the top.
        XCTAssertEqual(TabHitTester.tab(atWindowPoint: CGPoint(x: 250, y: 18), panelHeight: 36, frames: frames), second)
    }

    func testPointInTheEmptyPartOfTheBarFindsNothing() {
        XCTAssertNil(TabHitTester.tab(atWindowPoint: CGPoint(x: 600, y: 18), panelHeight: 36, frames: frames))
    }

    func testVerticalAxisIsFlipped() {
        let tall = [first: CGRect(x: 0, y: 0, width: 100, height: 10)]
        XCTAssertEqual(TabHitTester.tab(atWindowPoint: CGPoint(x: 5, y: 33), panelHeight: 36, frames: tall), first)
        XCTAssertNil(TabHitTester.tab(atWindowPoint: CGPoint(x: 5, y: 3), panelHeight: 36, frames: tall))
    }
}
