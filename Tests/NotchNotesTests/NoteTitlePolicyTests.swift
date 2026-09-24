import XCTest
@testable import NotchNotes

final class NoteTitlePolicyTests: XCTestCase {
    func testNormalizationPreservesPlainTextAndInternalSpaces() throws {
        XCTAssertEqual(NoteTitlePolicy.singleLine(" A\r\n\tB  C\u{2028}\u{2029}D "), " A B  C D ")
        XCTAssertEqual(NoteTitlePolicy.normalize(" A\n\tB  C "), "A B  C")
        XCTAssertEqual(try NoteTitlePolicy.change(for: " # 标题 ", initialEffectiveTitle: "旧名"), .set("# 标题"))
    }

    func testEmptyAndUnchangedDraftsHaveDistinctMeaning() throws {
        XCTAssertEqual(try NoteTitlePolicy.change(for: " \n\t ", initialEffectiveTitle: "自动名"), .set(nil))
        XCTAssertEqual(try NoteTitlePolicy.change(for: " 自动名 ", initialEffectiveTitle: "自动名"), .unchanged)
    }

    func testLengthUsesVisibleCharactersAfterNormalization() throws {
        for character in ["汉", "👨‍👩‍👧‍👦", "e\u{301}"] {
            let valid = String(repeating: character, count: 50)
            XCTAssertEqual(try NoteTitlePolicy.change(for: " \(valid) ", initialEffectiveTitle: "旧名"), .set(valid))
            XCTAssertThrowsError(try NoteTitlePolicy.change(for: valid + character, initialEffectiveTitle: "旧名")) {
                XCTAssertEqual($0 as? NoteTitleError, .tooLong)
            }
        }
    }
}
