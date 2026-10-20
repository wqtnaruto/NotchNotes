import Foundation
import XCTest
@testable import NotchNotes

@MainActor
final class SedentaryReminderStoreTests: XCTestCase {
    func testFreshInstallDefaultsToDisabledWithSuggestedDurations() throws {
        try withIsolatedSettings { defaults in
            let store = SedentaryReminderStore(defaults: defaults, automaticallyTicks: false)

            XCTAssertFalse(store.isEnabled)
            XCTAssertEqual(store.phase, .disabled)
            XCTAssertEqual(store.interval, .fortyFive)
            XCTAssertEqual(store.activityDuration, .two)
            XCTAssertFalse(store.shouldDisplayWidget)
        }
    }

    func testEveryReminderPhaseHasABundledImage() {
        for phase in [
            SedentaryReminderPhase.countingDown,
            .due,
            .snoozed,
            .activity,
            .completed,
            .paused
        ] {
            XCTAssertNotNil(SedentaryReminderAsset.image(for: phase), "Missing asset for \(phase)")
        }
    }

    func testEnablingStartsFullIntervalAndPersistsSettings() throws {
        try withIsolatedSettings { defaults in
            let uptime = 20.0
            let store = SedentaryReminderStore(
                defaults: defaults,
                now: { uptime },
                automaticallyTicks: false
            )
            store.interval = .thirty
            store.activityDuration = .five
            store.setEnabled(true)

            XCTAssertEqual(store.phase, .countingDown)
            XCTAssertEqual(store.remainingSeconds, 1_800)
            XCTAssertTrue(store.shouldDisplayWidget)

            let restored = SedentaryReminderStore(
                defaults: defaults,
                now: { uptime },
                automaticallyTicks: false
            )
            XCTAssertTrue(restored.isEnabled)
            XCTAssertEqual(restored.interval, .thirty)
            XCTAssertEqual(restored.activityDuration, .five)
        }
    }

    func testDueReminderCanSnoozeOnlyOnce() throws {
        try withIsolatedSettings { defaults in
            var uptime = 0.0
            let store = SedentaryReminderStore(
                defaults: defaults,
                now: { uptime },
                automaticallyTicks: false
            )
            store.interval = .thirty
            store.setEnabled(true)

            uptime = 1_800
            store.tick()
            XCTAssertEqual(store.phase, .due)
            XCTAssertTrue(store.isCardPresented)

            store.snooze()
            XCTAssertEqual(store.phase, .snoozed)
            XCTAssertTrue(store.hasSnoozed)
            XCTAssertEqual(store.remainingSeconds, 300)

            uptime += 300
            store.tick()
            XCTAssertEqual(store.phase, .due)
            XCTAssertTrue(store.hasSnoozed)
            store.snooze()
            XCTAssertEqual(store.phase, .due)
        }
    }

    func testActivityCompletionShowsFeedbackThenStartsNewRound() throws {
        try withIsolatedSettings { defaults in
            var uptime = 100.0
            let store = SedentaryReminderStore(
                defaults: defaults,
                now: { uptime },
                automaticallyTicks: false
            )
            store.activityDuration = .one
            store.setEnabled(true)
            store.startActivity()

            XCTAssertEqual(store.phase, .activity)
            XCTAssertEqual(store.remainingSeconds, 60)

            uptime += 60
            store.tick()
            XCTAssertEqual(store.phase, .completed)
            XCTAssertEqual(store.remainingSeconds, 3)

            uptime += 3
            store.tick()
            XCTAssertEqual(store.phase, .countingDown)
            XCTAssertEqual(store.remainingSeconds, store.interval.seconds)
        }
    }

    func testPausePersistsAndResumeStartsFullInterval() throws {
        try withIsolatedSettings { defaults in
            var uptime = 0.0
            let store = SedentaryReminderStore(
                defaults: defaults,
                now: { uptime },
                automaticallyTicks: false
            )
            store.setEnabled(true)
            store.pause()

            XCTAssertTrue(store.isPaused)
            XCTAssertEqual(store.phase, .paused)

            let restored = SedentaryReminderStore(
                defaults: defaults,
                now: { uptime },
                automaticallyTicks: false
            )
            XCTAssertTrue(restored.isPaused)
            XCTAssertEqual(restored.phase, .paused)

            uptime = 80
            restored.resume()
            XCTAssertFalse(restored.isPaused)
            XCTAssertEqual(restored.phase, .countingDown)
            XCTAssertEqual(restored.remainingSeconds, restored.interval.seconds)
        }
    }

    func testUnlockDiscardsInterruptedRoundAndStartsFullInterval() throws {
        try withIsolatedSettings { defaults in
            var uptime = 0.0
            let store = SedentaryReminderStore(
                defaults: defaults,
                now: { uptime },
                automaticallyTicks: false
            )
            store.setEnabled(true)
            store.startActivity()
            uptime = 20
            store.tick()

            store.handleScreenUnavailable()
            XCTAssertEqual(store.phase, .waitingForUnlock)
            XCTAssertFalse(store.shouldDisplayWidget)

            uptime = 500
            store.handleScreenAvailable()
            XCTAssertEqual(store.phase, .countingDown)
            XCTAssertEqual(store.remainingSeconds, store.interval.seconds)
            XCTAssertTrue(store.shouldDisplayWidget)
        }
    }

    func testSuppressedDueReminderPresentsOnceWhenSuppressionEnds() throws {
        try withIsolatedSettings { defaults in
            var uptime = 0.0
            let store = SedentaryReminderStore(
                defaults: defaults,
                now: { uptime },
                automaticallyTicks: false
            )
            store.setEnabled(true)
            store.setPresentationSuppressed(true)
            uptime = TimeInterval(store.interval.seconds)
            store.tick()

            XCTAssertEqual(store.phase, .due)
            XCTAssertFalse(store.isCardPresented)

            store.setPresentationSuppressed(false)
            XCTAssertTrue(store.isCardPresented)
            store.dismissCard()
            store.setPresentationSuppressed(false)
            XCTAssertFalse(store.isCardPresented)
        }
    }
}
