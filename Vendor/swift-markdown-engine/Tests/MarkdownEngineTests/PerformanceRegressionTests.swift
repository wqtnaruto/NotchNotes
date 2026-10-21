import AppKit
import XCTest
@testable import MarkdownEngine

final class PerformanceRegressionTests: XCTestCase {
    func testRangeIndexFindsOverlapsWithoutScanningUnrelatedRanges() {
        let index = MarkdownRangeIndex(ranges: [
            NSRange(location: 10, length: 5),
            NSRange(location: 100, length: 20)
        ])
        XCTAssertTrue(index.intersects(NSRange(location: 12, length: 1)))
        XCTAssertTrue(index.intersects(NSRange(location: 95, length: 10)))
        XCTAssertFalse(index.intersects(NSRange(location: 30, length: 5)))
    }

    func testScopedStylingProducesNoAttributesOutsideEditedParagraph() {
        let text = "# First **bold**\n\n# Second *italic*\n"
        let nsText = text as NSString
        let scope = nsText.paragraphRange(for: NSRange(location: nsText.range(of: "Second").location, length: 0))

        let attributes = MarkdownStyler.styleAttributes(
            text: text,
            fontName: "SF Pro",
            fontSize: 15,
            caretLocation: scope.location,
            activeTokenIndices: [],
            scopedRanges: [scope]
        )

        XCTAssertFalse(attributes.isEmpty)
        XCTAssertTrue(attributes.allSatisfy { NSIntersectionRange($0.range, scope).length > 0 })
    }
}
