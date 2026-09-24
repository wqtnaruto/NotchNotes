import Foundation
import XCTest
@testable import NotchNotes

@MainActor
final class NoteStoreTests: XCTestCase {
    func testPersistsNotesSelectionAndReadableTitles() throws {
        let environment = try makeEnvironment()
        defer { environment.cleanUp() }

        let store = NoteStore(
            defaults: environment.defaults,
            archiveURL: environment.archiveURL
        )
        store.updateText("# Project log\nFirst entry")
        store.updateSelection(
            for: store.activeTabID,
            range: NSRange(location: 4, length: 3)
        )
        XCTAssertEqual(store.title(for: store.activeTabID), "Project log")

        let firstTabID = store.activeTabID
        store.addTab()
        store.updateText("- [ ] Follow up")
        store.flush()

        let restored = NoteStore(
            defaults: environment.defaults,
            archiveURL: environment.archiveURL
        )
        XCTAssertEqual(restored.tabs.count, 2)
        XCTAssertEqual(restored.text, "- [ ] Follow up")
        XCTAssertEqual(restored.title(for: firstTabID), "Project log")
        XCTAssertEqual(
            restored.selectionRange(for: firstTabID),
            NSRange(location: 4, length: 3)
        )
    }

    func testDeletedNoteCanBeRestoredWithoutLosingContent() throws {
        let environment = try makeEnvironment()
        defer { environment.cleanUp() }

        let store = NoteStore(
            defaults: environment.defaults,
            archiveURL: environment.archiveURL
        )
        store.updateText("Keep this note")
        let originalID = store.activeTabID
        store.addTab()

        store.selectTab(originalID)
        store.removeActiveTab()
        XCTAssertTrue(store.canRestoreDeletedNote)
        XCTAssertFalse(store.tabs.contains(where: { $0.id == originalID }))

        store.restoreLastDeletedTab()
        XCTAssertFalse(store.canRestoreDeletedNote)
        XCTAssertEqual(store.activeTabID, originalID)
        XCTAssertEqual(store.text, "Keep this note")
    }

    func testDeletingInactiveNoteKeepsCurrentNoteActive() throws {
        let environment = try makeEnvironment()
        defer { environment.cleanUp() }

        let store = NoteStore(
            defaults: environment.defaults,
            archiveURL: environment.archiveURL
        )
        let firstID = store.activeTabID
        store.addTab()
        let activeID = store.activeTabID

        store.removeTab(firstID)

        XCTAssertEqual(store.activeTabID, activeID)
        XCTAssertFalse(store.tabs.contains(where: { $0.id == firstID }))
        XCTAssertTrue(store.canRestoreDeletedNote)
    }

    func testTitleFallsBackToLocalizedDefault() throws {
        let environment = try makeEnvironment()
        defer { environment.cleanUp() }

        let store = NoteStore(
            defaults: environment.defaults,
            archiveURL: environment.archiveURL
        )
        store.addTab()

        XCTAssertEqual(
            store.title(for: store.activeTabID, language: .chinese),
            "无标题 2"
        )
        XCTAssertEqual(
            store.title(for: store.activeTabID, language: .english),
            "Untitled 2"
        )
    }

    func testArchiveRecoversNotesWhenDefaultsDataIsMissing() throws {
        let environment = try makeEnvironment()
        defer { environment.cleanUp() }

        let store = NoteStore(
            defaults: environment.defaults,
            archiveURL: environment.archiveURL
        )
        store.updateText("Recovery copy")
        store.flush()

        environment.defaults.removeObject(forKey: "notchNotes.tabs.v1")
        environment.defaults.removeObject(forKey: "notchNotes.archive.v2")
        environment.defaults.removeObject(forKey: "notchNotes.activeTabID")

        let recovered = NoteStore(
            defaults: environment.defaults,
            archiveURL: environment.archiveURL
        )
        XCTAssertEqual(recovered.text, "Recovery copy")
    }

    func testCustomTitlePersistsWithoutChangingBodyOrSelection() throws {
        let env = try makeEnvironment()
        defer { env.cleanUp() }
        let store = NoteStore(defaults: env.defaults, archiveURL: env.archiveURL)
        store.updateText("# 正文\n保持内容")
        let id = store.activeTabID
        store.updateSelection(for: id, range: NSRange(location: 2, length: 2))
        let original = store.tabs[0]
        try store.commitTitle(for: id, change: .set("# 独立标题"))
        XCTAssertEqual(store.title(for: id), "# 独立标题")
        XCTAssertEqual(store.tabs[0].text, original.text)
        XCTAssertEqual(store.tabs[0].createdAt, original.createdAt)
        XCTAssertEqual(store.selectionRange(for: id), NSRange(location: 2, length: 2))
        let fromDefaults = NoteStore(defaults: env.defaults, archiveURL: nil)
        XCTAssertEqual(fromDefaults.tabs, store.tabs)
        env.defaults.removePersistentDomain(forName: env.suiteName)
        let fromFile = NoteStore(defaults: env.defaults, archiveURL: env.archiveURL)
        XCTAssertEqual(fromFile.tabs, store.tabs)
        fromFile.flush()
        store.flush()
    }

    func testUnchangedAutoTitleStaysAutomatic() throws {
        let env = try makeEnvironment()
        defer { env.cleanUp() }
        let writer = TitleArchiveWriter()
        let store = NoteStore(defaults: env.defaults, archiveURL: env.archiveURL, archiveWriter: writer.write)
        store.updateText("# 自动标题")
        store.flush()
        let before = writer.writeCount
        try store.commitTitle(for: store.activeTabID, change: .unchanged)
        XCTAssertEqual(writer.writeCount, before)
        XCTAssertNil(store.tabs[0].customTitle)
        store.updateText("下一段正文")
        XCTAssertEqual(store.title(for: store.activeTabID), "下一段正文")
        store.flush()
    }

    func testSavingIdenticalCustomTitleDoesNotWriteAgain() throws {
        let env = try makeEnvironment()
        defer { env.cleanUp() }
        let writer = TitleArchiveWriter()
        let store = NoteStore(defaults: env.defaults, archiveURL: env.archiveURL, archiveWriter: writer.write)
        let id = store.activeTabID
        try store.commitTitle(for: id, change: .set("已保存"))
        let before = writer.writeCount
        let archive = try Data(contentsOf: env.archiveURL)
        writer.shouldFail = true
        XCTAssertNoThrow(try store.commitTitle(for: id, change: .set("已保存")))
        XCTAssertEqual(writer.writeCount, before)
        XCTAssertEqual(try Data(contentsOf: env.archiveURL), archive)
        XCTAssertEqual(store.title(for: id), "已保存")
        writer.shouldFail = false
        store.flush()
    }

    func testClearingTitleRestoresAutomaticTitle() throws {
        let env = try makeEnvironment()
        defer { env.cleanUp() }
        let store = NoteStore(defaults: env.defaults, archiveURL: env.archiveURL)
        let id = store.activeTabID
        try store.commitTitle(for: id, change: .set("自定义"))
        store.updateText("# 改过的正文")
        XCTAssertEqual(store.title(for: id, language: .english), "自定义")
        try store.commitTitle(for: id, change: .set(nil))
        XCTAssertNil(store.tabs[0].customTitle)
        XCTAssertEqual(store.title(for: id), "改过的正文")
        store.updateText(String(repeating: "长", count: 60))
        XCTAssertEqual(store.title(for: id), String(repeating: "长", count: 41) + "…")
        store.flush()
    }

    func testDuplicateTitlesKeepDistinctTabs() throws {
        let env = try makeEnvironment()
        defer { env.cleanUp() }
        let store = NoteStore(defaults: env.defaults, archiveURL: env.archiveURL)
        store.updateText("第一页")
        let first = store.activeTabID
        try store.commitTitle(for: first, change: .set("重名"))
        store.addTab()
        store.updateText("第二页")
        try store.commitTitle(for: store.activeTabID, change: .set("重名"))
        XCTAssertNotEqual(first, store.activeTabID)
        XCTAssertEqual(store.tabs.map(\.text), ["第一页", "第二页"])
        XCTAssertEqual(store.tabs.map(\.customTitle), ["重名", "重名"])
        store.flush()
    }

    func testTitleWriteFailureDoesNotPublishOrPersistCandidate() throws {
        let env = try makeEnvironment()
        defer { env.cleanUp() }
        let writer = TitleArchiveWriter()
        let store = NoteStore(defaults: env.defaults, archiveURL: env.archiveURL, archiveWriter: writer.write)
        let id = store.activeTabID
        try store.commitTitle(for: id, change: .set("已保存"))
        store.flush()
        let fileBefore = try Data(contentsOf: env.archiveURL)
        let defaultsBefore = env.defaults.data(forKey: "notchNotes.archive.v2")
        let tabsBefore = store.tabs
        writer.shouldFail = true
        XCTAssertThrowsError(try store.commitTitle(for: id, change: .set("不得泄漏"))) {
            XCTAssertEqual($0 as? NoteTitleError, .saveFailed)
        }
        XCTAssertEqual(store.tabs, tabsBefore)
        XCTAssertEqual(try Data(contentsOf: env.archiveURL), fileBefore)
        XCTAssertEqual(env.defaults.data(forKey: "notchNotes.archive.v2"), defaultsBefore)
        let recovered = NoteStore(defaults: env.defaults, archiveURL: nil)
        XCTAssertEqual(recovered.title(for: id), "已保存")
        writer.shouldFail = false
        store.flush()
    }

    func testQueuedOldSaveCannotOverwriteCommittedTitle() throws {
        let env = try makeEnvironment()
        defer { env.cleanUp() }
        let writer = TitleArchiveWriter()
        writer.delay = 0.01
        let store = NoteStore(defaults: env.defaults, archiveURL: env.archiveURL, archiveWriter: writer.write)
        store.updateText("尚在队列中的正文")
        store.flush(waitForDisk: false)
        try store.commitTitle(for: store.activeTabID, change: .set("最新名称"))
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        let recovered = NoteStore(defaults: env.defaults, archiveURL: env.archiveURL)
        XCTAssertEqual(recovered.title(for: store.activeTabID), "最新名称")
        let data = try Data(contentsOf: env.archiveURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tabs = try XCTUnwrap(object["tabs"] as? [[String: Any]])
        XCTAssertEqual(tabs[0]["customTitle"] as? String, "最新名称")
        XCTAssertEqual(tabs[0]["text"] as? String, "尚在队列中的正文")
        recovered.flush()
        store.flush()
    }

    func testFailedRenamePreservesPendingBodySave() throws {
        let env = try makeEnvironment()
        defer { env.cleanUp() }
        let writer = TitleArchiveWriter()
        let store = NoteStore(defaults: env.defaults, archiveURL: env.archiveURL, archiveWriter: writer.write)
        store.flush()
        store.updateText("未完成自动保存的正文")
        writer.shouldFail = true
        XCTAssertThrowsError(try store.commitTitle(for: store.activeTabID, change: .set("失败名称")))
        writer.shouldFail = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        let data = try Data(contentsOf: env.archiveURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tabs = try XCTUnwrap(object["tabs"] as? [[String: Any]])
        XCTAssertEqual(tabs[0]["text"] as? String, "未完成自动保存的正文")
        XCTAssertNil(tabs[0]["customTitle"])
        store.flush()
    }

    func testMissingTargetAndMissingArchivePathFailSafely() throws {
        let env = try makeEnvironment()
        defer { env.cleanUp() }
        let store = NoteStore(defaults: env.defaults, archiveURL: nil)
        XCTAssertThrowsError(try store.commitTitle(for: UUID(), change: .unchanged)) {
            XCTAssertEqual($0 as? NoteTitleError, .targetMissing)
        }
        XCTAssertThrowsError(try store.commitTitle(for: store.activeTabID, change: .set("无归档"))) {
            XCTAssertEqual($0 as? NoteTitleError, .saveFailed)
        }
        XCTAssertNil(store.tabs[0].customTitle)
    }

    func testOldArchivesWithoutTitleKeyRemainCompatible() throws {
        for source in ["file", "archive", "tabs", "legacy"] {
            let env = try makeEnvironment()
            defer { env.cleanUp() }
            let first = UUID(), second = UUID()
            let tabs: [[String: Any]] = [
                ["id": first.uuidString, "text": "# 历史正文", "createdAt": 123,
                 "selectionLocation": 2, "selectionLength": 2],
                ["id": second.uuidString, "text": "", "createdAt": 124]
            ]
            let archive = try JSONSerialization.data(withJSONObject: [
                "tabs": tabs, "activeTabID": second.uuidString, "savedAt": 125
            ])
            switch source {
            case "file":
                try FileManager.default.createDirectory(at: env.directory, withIntermediateDirectories: true)
                try archive.write(to: env.archiveURL)
            case "archive": env.defaults.set(archive, forKey: "notchNotes.archive.v2")
            case "tabs":
                env.defaults.set(try JSONSerialization.data(withJSONObject: tabs), forKey: "notchNotes.tabs.v1")
                env.defaults.set(second.uuidString, forKey: "notchNotes.activeTabID")
            default: env.defaults.set("# 历史正文", forKey: "notchNotes.text")
            }
            let store = NoteStore(defaults: env.defaults, archiveURL: env.archiveURL)
            XCTAssertTrue(store.tabs.allSatisfy { $0.customTitle == nil })
            if source != "legacy" {
                XCTAssertEqual(store.tabs.map(\.id), [first, second])
                XCTAssertEqual(store.activeTabID, second)
                XCTAssertEqual(store.selectionRange(for: first), NSRange(location: 2, length: 2))
                XCTAssertEqual(store.title(for: second, language: .english), "Untitled 2")
                XCTAssertEqual(store.title(for: second, language: .chinese), "无标题 2")
            }
            XCTAssertEqual(store.tabs[0].text, "# 历史正文")
            store.flush()
        }
    }

    private func makeEnvironment() throws -> TestEnvironment {
        let suiteName = "NoteStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchNotesTests-\(UUID().uuidString)", isDirectory: true)
        return TestEnvironment(
            suiteName: suiteName,
            defaults: defaults,
            directory: directory,
            archiveURL: directory.appendingPathComponent("notes.json")
        )
    }
}

final class TitleArchiveWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var failing = false
    private var count = 0
    private var writeDelay: TimeInterval = 0
    var shouldFail: Bool {
        get { lock.withLock { failing } }
        set { lock.withLock { failing = newValue } }
    }
    var delay: TimeInterval {
        get { lock.withLock { writeDelay } }
        set { lock.withLock { writeDelay = newValue } }
    }
    var writeCount: Int { lock.withLock { count } }
    func write(_ data: Data, _ url: URL) throws {
        let (fails, duration) = lock.withLock { count += 1; return (failing, writeDelay) }
        if fails { throw CocoaError(.fileWriteNoPermission) }
        if duration > 0 { Thread.sleep(forTimeInterval: duration) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

private struct TestEnvironment {
    let suiteName: String
    let defaults: UserDefaults
    let directory: URL
    let archiveURL: URL

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}
