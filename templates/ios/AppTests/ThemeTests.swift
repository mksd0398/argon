import XCTest
@testable import ArgonStorefront

final class ThemeTests: XCTestCase {
    func testLightBrandColoursTakeBlackLabelsAndDarkOnesWhite() {
        XCTAssertTrue(brandIsLight("#FFFFFF"))
        XCTAssertTrue(brandIsLight("#FFEB3B"), "yellow")
        XCTAssertFalse(brandIsLight("#000000"))
        XCTAssertFalse(brandIsLight("#1E88E5"), "blue")
        XCTAssertFalse(brandIsLight("#808080"), "mid grey is below 0.5 relative luminance")
    }

    func testNoReadableBrandColourKeepsWhiteLabels() {
        XCTAssertFalse(brandIsLight(nil))
        XCTAssertFalse(brandIsLight("not a colour"))
        XCTAssertFalse(brandIsLight("#FFF"))
    }
}
