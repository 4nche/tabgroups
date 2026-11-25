import XCTest
@testable import TabGroups

final class DropPlanTests: XCTestCase {
    private let a = UUID()
    private let b = UUID()

    func testTwoLooseWindowsFormANewGroup() {
        XCTAssertEqual(DropPlan.action(sourceGroup: nil, targetGroup: nil), .createGroup)
    }

    func testDropOntoAGroupAddsTheDraggedWindowToIt() {
        XCTAssertEqual(DropPlan.action(sourceGroup: nil, targetGroup: a), .addSource(toGroup: a))
    }

    func testDroppingAGroupedWindowOnALooseOneAddsTheLooseOne() {
        XCTAssertEqual(DropPlan.action(sourceGroup: a, targetGroup: nil), .addTarget(toGroup: a))
    }

    func testDroppingOneGroupOnAnotherMergesIntoTheTarget() {
        XCTAssertEqual(DropPlan.action(sourceGroup: a, targetGroup: b), .merge(group: a, into: b))
    }

    func testDropWithinTheSameGroupDoesNothing() {
        XCTAssertEqual(DropPlan.action(sourceGroup: a, targetGroup: a), .nothing)
    }

    private let start = WindowBounds(x: 100, y: 100, width: 800, height: 600)

    func testSmallJitterIsNotADrag() {
        XCTAssertEqual(DragMotion.classify(from: start, to: start.translated(dx: 3, dy: 2)), .still)
    }

    func testMovingWithoutResizingIsADrag() {
        XCTAssertEqual(DragMotion.classify(from: start, to: start.translated(dx: 40, dy: 0)), .moved)
    }

    func testResizeFromTheTopLeftIsNotADrag() {
        let resized = WindowBounds(x: 60, y: 70, width: 840, height: 630)
        XCTAssertEqual(DragMotion.classify(from: start, to: resized), .resized)
    }
}
