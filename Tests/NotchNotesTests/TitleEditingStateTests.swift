import AppKit
import XCTest
@testable import NotchNotes

@MainActor
final class TitleEditingStateTests: XCTestCase {
    func testBeginUsesFullTitleAndRepeatedBeginKeepsDraft() throws {
        let f = try TitleFixture()
        defer { f.cleanUp() }
        let title = String(repeating: "长", count: 50)
        try f.store.commitTitle(for: f.store.activeTabID, change: .set(title))
        let id = f.store.activeTabID
        f.store.addTab()
        XCTAssertTrue(f.state.begin(tabID: id, language: .chinese))
        XCTAssertEqual(f.store.activeTabID, id)
        XCTAssertEqual(f.state.session?.draft, title)
        XCTAssertEqual(f.state.session?.selection, NSRange(location: 0, length: 50))
        let generation = f.state.session?.generation
        f.state.updateDraft("草稿", selection: NSRange(location: 1, length: 0), isComposing: false)
        XCTAssertTrue(f.state.begin(tabID: id, language: .english))
        XCTAssertEqual(f.state.session?.generation, generation)
        XCTAssertEqual(f.state.session?.draft, "草稿")
    }

    func testCommitAndCancelAreIndependentOfBodyAndSelection() throws {
        let f = try TitleFixture()
        defer { f.cleanUp() }
        f.store.updateText("# 自动\n正文")
        let id = f.store.activeTabID
        f.store.updateSelection(for: id, range: NSRange(location: 2, length: 2))
        XCTAssertTrue(f.state.begin(tabID: id, language: .chinese))
        f.state.updateDraft(" 自定义 ", selection: NSRange(location: 4, length: 0), isComposing: false)
        XCTAssertTrue(f.state.commitIfNeeded())
        XCTAssertNil(f.state.session)
        XCTAssertEqual(f.store.title(for: id), "自定义")
        XCTAssertEqual(f.store.text, "# 自动\n正文")
        XCTAssertEqual(f.store.selectionRange(for: id), NSRange(location: 2, length: 2))
        XCTAssertTrue(f.state.begin(tabID: id, language: .chinese))
        f.state.updateDraft("放弃", selection: .init(location: 2, length: 0), isComposing: false)
        let before = f.writer.writeCount
        f.state.cancel()
        XCTAssertEqual(f.writer.writeCount, before)
        XCTAssertNil(f.state.session)
        XCTAssertEqual(f.store.title(for: id), "自定义")
    }

    func testFailureKeepsDraftAndSecondSessionCannotOverwriteIt() throws {
        let f = try TitleFixture()
        defer { f.cleanUp() }
        let first = f.store.activeTabID
        f.store.addTab()
        let second = f.store.activeTabID
        XCTAssertTrue(f.state.begin(tabID: first, language: .chinese))
        let draft = String(repeating: "字", count: 51)
        f.state.updateDraft(draft, selection: .init(location: 51, length: 0), isComposing: false)
        XCTAssertFalse(f.state.begin(tabID: second, language: .chinese))
        XCTAssertEqual(f.state.session?.tabID, first)
        XCTAssertEqual(f.state.session?.draft, draft)
        XCTAssertEqual(f.state.session?.error, .tooLong)
        f.state.updateDraft("可重试", selection: .init(location: 3, length: 0), isComposing: false)
        f.writer.shouldFail = true
        XCTAssertFalse(f.state.commitIfNeeded())
        XCTAssertEqual(f.state.session?.error, .saveFailed)
        XCTAssertEqual(f.state.session?.draft, "可重试")
        f.writer.shouldFail = false
        XCTAssertTrue(f.state.begin(tabID: second, language: .chinese))
        XCTAssertEqual(f.store.title(for: first), "可重试")
        XCTAssertEqual(f.state.session?.tabID, second)
        f.state.cancel()
    }

    func testMissingTargetCannotStartSessionOrCreateNote() throws {
        let f = try TitleFixture()
        defer { f.cleanUp() }
        let ids = f.store.tabs.map(\.id)
        XCTAssertFalse(f.state.begin(tabID: UUID(), language: .chinese))
        XCTAssertNil(f.state.session)
        XCTAssertEqual(f.state.lastError, .targetMissing)
        XCTAssertEqual(f.store.tabs.map(\.id), ids)
    }

    func testDisappearedTargetDoesNotReceiveDraftOnAnotherPage() throws {
        let f = try TitleFixture()
        defer { f.cleanUp() }
        let first = f.store.activeTabID
        f.store.addTab()
        let second = f.store.activeTabID
        f.store.updateText("保留的正文")
        f.state.begin(tabID: first, language: .chinese)
        f.state.updateDraft("不得串页", selection: .init(location: 4, length: 0), isComposing: false)
        f.store.removeTab(first)
        let writes = f.writer.writeCount
        XCTAssertFalse(f.state.commitIfNeeded())
        XCTAssertNil(f.state.session)
        XCTAssertEqual(f.state.lastError, .targetMissing)
        XCTAssertEqual(f.store.tabs.map(\.id), [second])
        XCTAssertEqual(f.store.text, "保留的正文")
        XCTAssertNil(f.store.tabs[0].customTitle)
        XCTAssertEqual(f.writer.writeCount, writes)
    }

    func testRepeatedConfirmationDoesNotWriteOrCreateAnotherNote() throws {
        let f = try TitleFixture()
        defer { f.cleanUp() }
        let id = f.store.activeTabID
        f.state.begin(tabID: id, language: .chinese)
        f.state.updateDraft("仅保存一次", selection: .init(location: 5, length: 0), isComposing: false)
        let before = f.writer.writeCount
        XCTAssertTrue(f.state.commitIfNeeded())
        XCTAssertEqual(f.writer.writeCount, before + 1)
        XCTAssertTrue(f.state.commitIfNeeded())
        f.state.cancel()
        f.state.updateDraft("已结束的输入", selection: .init(location: 0, length: 0), isComposing: false)
        XCTAssertTrue(f.state.commitIfNeeded())
        XCTAssertEqual(f.writer.writeCount, before + 1)
        XCTAssertEqual(f.store.tabs.map(\.id), [id])
        XCTAssertEqual(f.store.title(for: id), "仅保存一次")
        XCTAssertNil(f.state.session)
    }

    func testUnchangedSessionAndEmptyDraftKeepAutomaticNaming() throws {
        let f = try TitleFixture()
        defer { f.cleanUp() }
        let id = f.store.activeTabID
        XCTAssertTrue(f.state.begin(tabID: id, language: .english))
        XCTAssertTrue(f.state.commitIfNeeded())
        XCTAssertNil(f.store.tabs[0].customTitle)
        try f.store.commitTitle(for: id, change: .set("已命名"))
        XCTAssertTrue(f.state.begin(tabID: id, language: .chinese))
        f.state.updateDraft("\t\n ", selection: .init(location: 3, length: 0), isComposing: false)
        XCTAssertTrue(f.state.commitIfNeeded())
        XCTAssertEqual(f.store.title(for: id, language: .english), "Untitled 1")
    }
}

@MainActor
final class TitleFixture {
    let suite = "TitleTests.\(UUID())"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults: UserDefaults
    let store: NoteStore
    let state: TitleEditingState
    let writer = TitleArchiveWriter()

    init() throws {
        _ = NSApplication.shared
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        store = NoteStore(defaults: defaults, archiveURL: directory.appendingPathComponent("notes.json"),
                          archiveWriter: writer.write)
        state = TitleEditingState(store: store)
        store.flush()
    }

    func cleanUp() {
        state.cancel()
        writer.shouldFail = false
        store.flush()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}
