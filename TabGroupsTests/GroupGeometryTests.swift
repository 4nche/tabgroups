import CoreGraphics
import XCTest
@testable import TabGroups

final class GroupGeometryTests: XCTestCase {
    private let container = WindowBounds(x: 100, y: 200, width: 800, height: 600)

    func testContentSitsUnderBar() {
        XCTAssertEqual(GroupGeometry.contentBounds(of: container),
                       WindowBounds(x: 100, y: 236, width: 800, height: 564))
        XCTAssertEqual(GroupGeometry.barBounds(of: container),
                       WindowBounds(x: 100, y: 200, width: 800, height: 36))
    }

    func testContentHeightNeverNegative() {
        let tiny = WindowBounds(x: 0, y: 0, width: 300, height: 20)
        XCTAssertEqual(GroupGeometry.contentBounds(of: tiny).height, 0)
    }

    func testAdoptionGrowsUpwardSoMemberKeepsItsRectangle() {
        let member = WindowBounds(x: 300, y: 400, width: 700, height: 500)
        let adopted = GroupGeometry.container(adopting: member, visibleTop: 25)
        XCTAssertEqual(adopted, WindowBounds(x: 300, y: 364, width: 700, height: 536))
        XCTAssertEqual(GroupGeometry.contentBounds(of: adopted), member)
    }

    func testAdoptionClampsBarToVisibleTop() {
        let snapped = WindowBounds(x: 0, y: 25, width: 756, height: 957)
        let adopted = GroupGeometry.container(adopting: snapped, visibleTop: 25)
        XCTAssertEqual(adopted, snapped)
        XCTAssertEqual(GroupGeometry.contentBounds(of: adopted),
                       WindowBounds(x: 0, y: 61, width: 756, height: 921))
    }

    func testClampKeepsBottomEdge() {
        let above = WindowBounds(x: 0, y: 5, width: 400, height: 300)
        XCTAssertEqual(GroupGeometry.clamped(above, visibleTop: 25),
                       WindowBounds(x: 0, y: 25, width: 400, height: 280))
    }

    func testEchoWithinTolerance() {
        let applied = WindowBounds(x: 10, y: 10, width: 500, height: 400)
        XCTAssertTrue(GroupGeometry.isEcho(WindowBounds(x: 11, y: 10, width: 500, height: 401), of: applied))
        XCTAssertFalse(GroupGeometry.isEcho(WindowBounds(x: 14, y: 10, width: 500, height: 400), of: applied))
        XCTAssertFalse(GroupGeometry.isEcho(applied, of: nil))
    }

    func testConstrainedWindowReportIsAnEcho() {
        let took = WindowBounds(x: 100, y: 236, width: 797, height: 555)
        XCTAssertTrue(GroupGeometry.isEcho(took, of: took))
    }

    func testAppKitRectHandlesNegativeCoordinates() {
        let bounds = WindowBounds(x: -1200, y: -300, width: 800, height: 36)
        XCTAssertEqual(GroupGeometry.appKitRect(for: bounds, mainDisplayHeight: 1117),
                       CGRect(x: -1200, y: 1117 + 300 - 36, width: 800, height: 36))
    }

    func testPureMoveTranslatesContainerKeepingItsSize() {
        let took = WindowBounds(x: 100, y: 236, width: 797, height: 555)
        let dragged = WindowBounds(x: 150, y: 286, width: 797, height: 555)
        XCTAssertEqual(GroupGeometry.container(container, afterMember: dragged, lastApplied: took, visibleTop: 25),
                       WindowBounds(x: 150, y: 250, width: 800, height: 600))
    }

    func testResizeAdoptsMemberRectangle() {
        let took = WindowBounds(x: 100, y: 236, width: 800, height: 564)
        let snapped = WindowBounds(x: 0, y: 25, width: 756, height: 957)
        XCTAssertEqual(GroupGeometry.container(container, afterMember: snapped, lastApplied: took, visibleTop: 25),
                       snapped)
    }

    func testMoveOfNeverPlacedMemberAdoptsItsRectangle() {
        let member = WindowBounds(x: 300, y: 400, width: 700, height: 500)
        XCTAssertEqual(GroupGeometry.container(container, afterMember: member, lastApplied: nil, visibleTop: 25),
                       WindowBounds(x: 300, y: 364, width: 700, height: 536))
    }

    func testPureMoveIgnoresStaleLastAppliedPosition() {
        // The window's size matches what it last took, but the recorded position is out of date.
        let stale = WindowBounds(x: 0, y: 0, width: 797, height: 555)
        let dragged = WindowBounds(x: 150, y: 286, width: 797, height: 555)
        XCTAssertEqual(GroupGeometry.container(container, afterMember: dragged, lastApplied: stale, visibleTop: 25),
                       WindowBounds(x: 150, y: 250, width: 800, height: 600))
    }

    func testPureMoveToTopEdgeKeepsGroupSize() {
        let took = WindowBounds(x: 100, y: 236, width: 800, height: 564)
        let atTop = WindowBounds(x: 100, y: 25, width: 800, height: 564)
        XCTAssertEqual(GroupGeometry.container(container, afterMember: atTop, lastApplied: took, visibleTop: 25),
                       WindowBounds(x: 100, y: 25, width: 800, height: 600))
    }

    func testShiftIntoViewKeepsHeight() {
        let above = WindowBounds(x: 0, y: -400, width: 400, height: 300)
        XCTAssertEqual(GroupGeometry.shiftedIntoView(above, visibleTop: 25),
                       WindowBounds(x: 0, y: 25, width: 400, height: 300))
        XCTAssertEqual(GroupGeometry.shiftedIntoView(container, visibleTop: 25), container)
    }

    func testBackdropReachesBehindTheWindowsRoundedCorners() {
        XCTAssertEqual(GroupGeometry.barBackdropBounds(of: container),
                       WindowBounds(x: 100, y: 200, width: 800, height: 36 + 28))
    }

    func testBackdropNeverExtendsPastTheContainer() {
        let short = WindowBounds(x: 0, y: 0, width: 300, height: 50)
        XCTAssertEqual(GroupGeometry.barBackdropBounds(of: short).height, 50)
        let tiny = WindowBounds(x: 0, y: 0, width: 300, height: 20)
        XCTAssertEqual(GroupGeometry.barBackdropBounds(of: tiny).height, 36)
    }

    func testTranslated() {
        XCTAssertEqual(container.translated(dx: 5, dy: -7),
                       WindowBounds(x: 105, y: 193, width: 800, height: 600))
    }
}
