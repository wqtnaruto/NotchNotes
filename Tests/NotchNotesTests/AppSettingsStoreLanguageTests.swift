import Foundation
import XCTest
@testable import NotchNotes

@MainActor
final class AppSettingsStoreLanguageTests: XCTestCase {
    func testDefaultLanguageIsChinese() throws {
        try withIsolatedSettings { defaults in
            XCTAssertEqual(AppSettingsStore(defaults: defaults).language, .chinese)
        }
    }

    func testLanguagePersistsAcrossInstances() throws {
        try withIsolatedSettings { defaults in
            let firstStore = AppSettingsStore(defaults: defaults)
            firstStore.language = .english
            XCTAssertEqual(AppSettingsStore(defaults: defaults).language, .english)
        }
    }
}

@MainActor
func withIsolatedSettings(_ body: (UserDefaults) throws -> Void) throws {
    let suiteName = "NotchNotesSettingsTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    // 不在偏好设置测试中触发真实系统防休眠恢复。
    defaults.set(true, forKey: "notchNotes.completedSleepGuardRecoveryV1")
    try body(defaults)
}
