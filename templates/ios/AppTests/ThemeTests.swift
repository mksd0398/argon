import XCTest
@testable import ArgonStorefront

final class ThemeTests: XCTestCase {
    func testLightBrandColoursTakeBlackLabelsAndDarkOnesWhite() {
        XCTAssertTrue(brandIsLight("#FFFFFF"))
        XCTAssertTrue(brandIsLight("#FFEB3B"), "yellow")
        XCTAssertFalse(brandIsLight("#000000"))
        XCTAssertTrue(brandIsLight("#1E88E5"), "mid blue: black contrasts more")
        XCTAssertTrue(brandIsLight("#808080"), "mid grey: black contrasts more")
        XCTAssertFalse(brandIsLight("#1A237E"), "navy")
    }

    func testNoReadableBrandColourKeepsWhiteLabels() {
        XCTAssertFalse(brandIsLight(nil))
        XCTAssertFalse(brandIsLight("not a colour"))
        XCTAssertFalse(brandIsLight("#FFF"))
    }
}
