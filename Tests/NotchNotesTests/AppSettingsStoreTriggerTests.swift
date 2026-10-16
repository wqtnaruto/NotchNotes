import Foundation
import XCTest
@testable import NotchNotes

@MainActor
final class AppSettingsStoreTriggerTests: XCTestCase {
    func testFreshInstallDefaultsToClickAndPersistsMigration() throws {
        try withIsolatedSettings { defaults in
            XCTAssertEqual(AppSettingsStore(defaults: defaults).triggerMode, .click)
            XCTAssertEqual(defaults.string(forKey: "notchNotes.triggerMode"), "click")
            XCTAssertTrue(defaults.bool(forKey: "notchNotes.completedClickTriggerMigrationV1"))
        }
    }

    func testUpgradeMigratesExistingModesToClickOnlyOnce() throws {
        for oldValue in ["hover", "click", "unknown"] {
            try withIsolatedSettings { defaults in
                defaults.set(oldValue, forKey: "notchNotes.triggerMode")
                let store = AppSettingsStore(defaults: defaults)
                XCTAssertEqual(store.triggerMode, .click)
                store.triggerMode = .hover
                XCTAssertEqual(AppSettingsStore(defaults: defaults).triggerMode, .hover)
                store.triggerMode = .click
                XCTAssertEqual(AppSettingsStore(defaults: defaults).triggerMode, .click)
            }
        }
    }

    func testInvalidOrMissingValueAfterMigrationFallsBackToClick() throws {
        for value in [nil, "unknown"] as [String?] {
            try withIsolatedSettings { defaults in
                defaults.set(true, forKey: "notchNotes.completedClickTriggerMigrationV1")
                defaults.set(value, forKey: "notchNotes.triggerMode")
                XCTAssertEqual(AppSettingsStore(defaults: defaults).triggerMode, .click)
            }
        }
    }
}
