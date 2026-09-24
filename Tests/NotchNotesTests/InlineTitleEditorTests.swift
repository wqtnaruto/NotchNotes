import AppKit
import SwiftUI
import XCTest
@testable import NotchNotes

@MainActor
final class InlineTitleEditorTests: XCTestCase {
    func testNewSessionSelectsCompleteTitleOnce() throws {
        let f = try TitleFixture()
        defer { f.cleanUp() }
        let title = String(repeating: "👨‍👩‍👧‍👦", count: 20)
        try f.store.commitTitle(for: f.store.activeTabID, change: .set(title))
        f.state.begin(tabID: f.store.activeTabID, language: .chinese)
        let view = TitleTextView()
        view.bind(state: f.state, language: .chinese)
        XCTAssertEqual(view.string, title)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: title.utf16.count))
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.bind(state: f.state, language: .english)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 0))
    }

    func testViewUpdateKeepsDraftAndSelection() throws {
        let f = try TitleFixture()
        defer { f.cleanUp() }
        f.state.begin(tabID: f.store.activeTabID, language: .chinese)
        let host = NSHostingView(rootView: InlineTitleEditor(state: f.state, language: .chinese))
        host.frame = NSRect(x: 0, y: 0, width: 160, height: 28)
        host.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(titleView(in: host))
        view.insertText("输入草稿", replacementRange: NSRange(location: 0, length: view.string.utf16.count))
        view.setSelectedRange(NSRange(location: 1, length: 2))
        host.rootView = InlineTitleEditor(state: f.state, language: .english)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(view.string, "输入草稿")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 1, length: 2))
        XCTAssertEqual(f.state.session?.draft, "输入草稿")
        XCTAssertEqual(f.state.session?.selection, NSRange(location: 1, length: 2))
    }

    func testEnterSavesAndEscapeCancelsWithoutChangingBody() throws {
        let f = try TitleFixture()
        defer { f.cleanUp() }
        f.store.updateText("正文不变")
        let id = f.store.activeTabID
        f.state.begin(tabID: id, language: .chinese)
        let view = TitleTextView()
        view.bind(state: f.state, language: .chinese)
        view.insertText("新名", replacementRange: .init(location: 0, length: view.string.utf16.count))
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertNil(f.state.session)
        XCTAssertEqual(f.store.title(for: id), "新名")
        XCTAssertEqual(f.store.text, "正文不变")
        f.state.begin(tabID: id, language: .chinese)
        view.bind(state: f.state, language: .chinese)
        view.insertText("放弃", replacementRange: .init(location: 0, length: view.string.utf16.count))
        view.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertNil(f.state.session)
        XCTAssertEqual(f.store.title(for: id), "新名")
    }

    func testErrorDescriptionUpdatesWithoutResettingDraft() throws {
        let f = try TitleFixture()
        defer { f.cleanUp() }
        f.state.begin(tabID: f.store.activeTabID, language: .chinese)
        let view = TitleTextView()
        view.bind(state: f.state, language: .chinese)
        let tooLong = String(repeating: "长", count: 51)
        view.insertText(tooLong, replacementRange: .init(location: 0, length: view.string.utf16.count))
        view.bind(state: f.state, language: .chinese)
        XCTAssertEqual(view.accessibilityHelp(), "标题最多 50 个字符，请缩短后重试。")
        view.bind(state: f.state, language: .english)
        XCTAssertEqual(view.toolTip, "Titles can contain up to 50 characters. Shorten the title and try again.")
        XCTAssertEqual(view.string, tooLong)
        view.insertText("可保存", replacementRange: .init(location: 0, length: view.string.utf16.count))
        view.bind(state: f.state, language: .chinese)
        XCTAssertNil(view.accessibilityHelp())
    }

    func testSaveFailureKeepsNativeDraftForRetry() throws {
        let f = try TitleFixture()
        defer { f.cleanUp() }
        f.state.begin(tabID: f.store.activeTabID, language: .chinese)
        let view = TitleTextView()
        view.bind(state: f.state, language: .chinese)
        view.insertText("重试名称", replacementRange: .init(location: 0, length: view.string.utf16.count))
        f.writer.shouldFail = true
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(f.state.session?.error, .saveFailed)
        XCTAssertEqual(view.string, "重试名称")
        f.writer.shouldFail = false
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertNil(f.state.session)
        XCTAssertEqual(f.store.title(for: f.store.activeTabID), "重试名称")
    }

    func testStaleNativeViewCannotModifyOrEndNewSession() throws {
        let f = try TitleFixture()
        defer { f.cleanUp() }
        let id = f.store.activeTabID
        f.state.begin(tabID: id, language: .chinese)
        let oldView = TitleTextView()
        oldView.bind(state: f.state, language: .chinese)
        f.state.cancel()
        f.state.begin(tabID: id, language: .chinese)
        let currentView = TitleTextView()
        currentView.bind(state: f.state, language: .chinese)
        currentView.insertText("当前草稿", replacementRange: .init(location: 0, length: currentView.string.utf16.count))
        currentView.setSelectedRange(NSRange(location: 1, length: 2))
        let generation = f.state.session?.generation
        let writes = f.writer.writeCount
        oldView.insertText("过期回调", replacementRange: .init(location: 0, length: oldView.string.utf16.count))
        oldView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        oldView.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(f.state.session?.generation, generation)
        XCTAssertEqual(f.state.session?.draft, "当前草稿")
        XCTAssertEqual(f.state.session?.selection, NSRange(location: 1, length: 2))
        XCTAssertEqual(f.writer.writeCount, writes)
        XCTAssertNil(f.store.tabs[0].customTitle)
    }

    func testEnterEnforcesGraphemeLimitWithoutTruncatingDraft() throws {
        let f = try TitleFixture()
        defer { f.cleanUp() }
        let id = f.store.activeTabID
        let legal = String(repeating: "👨‍👩‍👧‍👦", count: 50)
        f.state.begin(tabID: id, language: .chinese)
        let view = TitleTextView()
        view.bind(state: f.state, language: .chinese)
        view.insertText(legal, replacementRange: .init(location: 0, length: view.string.utf16.count))
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertNil(f.state.session)
        XCTAssertEqual(f.store.title(for: id), legal)
        f.state.begin(tabID: id, language: .chinese)
        view.bind(state: f.state, language: .chinese)
        view.insertText(legal + "字", replacementRange: .init(location: 0, length: view.string.utf16.count))
        let selection = view.selectedRange()
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(f.state.session?.error, .tooLong)
        XCTAssertEqual(f.state.session?.draft, legal + "字")
        XCTAssertEqual(view.selectedRange(), selection)
        XCTAssertEqual(f.store.title(for: id), legal)
        XCTAssertEqual(f.store.text, "")
    }

    private func titleView(in view: NSView) -> TitleTextView? {
        if let title = view as? TitleTextView { return title }
        return view.subviews.lazy.compactMap { self.titleView(in: $0) }.first
    }
}
