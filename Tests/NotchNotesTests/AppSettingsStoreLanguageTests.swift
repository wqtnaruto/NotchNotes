import Foundation
import XCTest
@testable import NotchNotes

@MainActor
final class AppSettingsStoreLanguageTests: XCTestCase {
    private let suiteName = "AppSettingsStoreLanguageTests"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "notchNotes.language")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "notchNotes.language")
        super.tearDown()
    }

    func testDefaultLanguageIsChinese() {
        let store = AppSettingsStore()
        XCTAssertEqual(store.language, .chinese)
    }

    func testLanguagePersistsAcrossInstances() {
        let firstStore = AppSettingsStore()
        firstStore.language = .english

        let secondStore = AppSettingsStore()
        XCTAssertEqual(secondStore.language, .english)
    }
}
