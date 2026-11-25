import XCTest
@testable import TabGroups

final class GlassPreferenceTests: XCTestCase {
    func testNoTintMeansSeeThroughGlass() {
        XCTAssertEqual(GlassPreference.variant(systemTintAmount: 0), .clear)
    }

    func testAnyTintMeansFrostedGlass() {
        XCTAssertEqual(GlassPreference.variant(systemTintAmount: 0.4), .regular)
        XCTAssertEqual(GlassPreference.variant(systemTintAmount: 1), .regular)
    }

    func testMissingSettingFallsBackToTheSystemDefaultLook() {
        XCTAssertEqual(GlassPreference.variant(systemTintAmount: nil), .regular)
    }
}
