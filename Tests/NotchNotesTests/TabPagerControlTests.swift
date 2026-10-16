import AppKit
import SwiftUI
import XCTest
@testable import NotchNotes

@MainActor
final class TabPagerControlTests: XCTestCase {
    func testDoubleClickCurrentAndInactiveTitlesCanBeSavedAndReloaded() throws {
        let f = try PagerFixture()
        defer { f.cleanUp() }
        let first = f.store.activeTabID
        f.store.updateText("第一页正文")
        f.store.updateSelection(for: first, range: NSRange(location: 1, length: 2))
        f.store.addTab()
        let second = f.store.activeTabID
        f.store.updateText("第二页正文")
        f.store.updateSelection(for: second, range: NSRange(location: 2, length: 3))
        for id in [second, first] {
            f.layout()
            let button = try XCTUnwrap(f.buttons.first { $0.identifier?.rawValue == "tab-\(id)" })
            let width = button.bounds.width
            try f.doubleClick(button)
            f.layout()
            XCTAssertEqual(f.store.activeTabID, id)
            XCTAssertEqual(f.state.session?.tabID, id)
            let editor = try XCTUnwrap(f.titleEditors.first)
            XCTAssertEqual(f.titleEditors.count, 1)
            XCTAssertEqual(editor.enclosingScrollView?.bounds.width ?? 0, width, accuracy: 1)
            XCTAssertFalse(editor.visibleRect.isEmpty)
            editor.insertText("名称-\(id)", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            f.layout()
            XCTAssertNil(f.state.session)
            XCTAssertEqual(f.store.title(for: id), "名称-\(id)")
        }
        XCTAssertEqual(f.store.tabs.map(\.text), ["第一页正文", "第二页正文"])
        XCTAssertEqual(f.store.selectionRange(for: first), NSRange(location: 1, length: 2))
        XCTAssertEqual(f.store.selectionRange(for: second), NSRange(location: 2, length: 3))
        f.store.flush()
        let reloaded = NoteStore(defaults: f.defaults, archiveURL: f.directory.appendingPathComponent("notes.json"))
        XCTAssertEqual(reloaded.tabs.map(\.customTitle), f.store.tabs.map(\.customTitle))
        reloaded.flush()
    }

    func testInvalidDraftShowsMessageWithoutGrowingPager() throws {
        let f = try PagerFixture()
        defer { f.cleanUp() }
        f.layout()
        let height = f.host.fittingSize.height
        let id = f.store.activeTabID
        let button = try XCTUnwrap(f.buttons.first { $0.identifier?.rawValue == "tab-\(id)" })
        try f.doubleClick(button)
        f.layout()
        let editor = try XCTUnwrap(f.titleEditors.first)
        editor.insertText(String(repeating: "长", count: 51), replacementRange: .init(location: 0, length: editor.string.utf16.count))
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        f.layout()
        XCTAssertNotNil(f.host.rootView.errorMessage)
        XCTAssertEqual(f.host.rootView.errorMessage, editor.accessibilityHelp())
        XCTAssertEqual(f.host.fittingSize.height, height, accuracy: 1)
        XCTAssertEqual(editor.string.count, 51)
        XCTAssertEqual(f.state.session?.tabID, id)
    }

    func testDoubleClickThenEscapeDiscardsDraft() throws {
        let f = try PagerFixture()
        defer { f.cleanUp() }
        f.layout()
        let id = f.store.activeTabID
        let title = f.store.title(for: id)
        let button = try XCTUnwrap(f.buttons.first { $0.identifier?.rawValue == "tab-\(id)" })
        try f.doubleClick(button)
        f.layout()
        let editor = try XCTUnwrap(f.titleEditors.first)
        editor.insertText("不保存", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        f.layout()
        XCTAssertNil(f.state.session)
        XCTAssertEqual(f.store.title(for: id), title)
        XCTAssertTrue(f.titleEditors.isEmpty)
    }

    func testSelectingTextTabPreservesIdentityAndBody() throws {
        let fixture = try PagerFixture()
        defer { fixture.cleanUp() }
        fixture.store.updateText("# 第一页\n正文保持")
        let firstID = fixture.store.activeTabID
        fixture.store.updateSelection(for: firstID, range: NSRange(location: 2, length: 2))
        fixture.store.addTab()
        fixture.layout()

        let button = try XCTUnwrap(fixture.buttons.first { $0.title == "第一页" })
        button.performClick(nil)
        fixture.layout()

        XCTAssertEqual(fixture.store.activeTabID, firstID)
        XCTAssertEqual(fixture.store.text, "# 第一页\n正文保持")
        XCTAssertEqual(fixture.store.selectionRange(for: firstID), NSRange(location: 2, length: 2))
        XCTAssertEqual(button.toolTip, "第一页")
    }

    func testPlusCreatesOneVisibleActiveTab() throws {
        let fixture = try PagerFixture()
        defer { fixture.cleanUp() }
        fixture.layout()
        let plus = try XCTUnwrap(fixture.buttons.first { $0.identifier?.rawValue == "new-note" })
        plus.performClick(nil)
        fixture.layout()

        XCTAssertEqual(fixture.store.tabs.count, 2)
        let active = try XCTUnwrap(fixture.buttons.first {
            $0.identifier?.rawValue == "tab-\(fixture.store.activeTabID)"
        })
        XCTAssertFalse(active.visibleRect.isEmpty)
        XCTAssertTrue(fixture.host.bounds.contains(plus.convert(plus.bounds, to: fixture.host)))
    }

    func testOverflowKeepsSingleRowAndPlusVisible() throws {
        let fixture = try PagerFixture()
        defer { fixture.cleanUp() }
        fixture.layout()
        let initialHeight = fixture.host.fittingSize.height
        for index in 1...20 {
            fixture.store.addTab()
            fixture.store.updateText("第 \(index) 页 " + String(repeating: "长标题", count: 20))
        }
        fixture.layout()

        let tabs = fixture.buttons.filter { $0.identifier?.rawValue.hasPrefix("tab-") == true }
        XCTAssertEqual(tabs.count, 21)
        let plus = try XCTUnwrap(fixture.buttons.first { $0.identifier?.rawValue == "new-note" })
        XCTAssertEqual(fixture.host.fittingSize.height, initialHeight, accuracy: 1)
        XCTAssertEqual(fixture.host.fittingSize.height, 32, accuracy: 1)
        XCTAssertTrue(fixture.host.bounds.contains(plus.convert(plus.bounds, to: fixture.host)))
        let active = try XCTUnwrap(tabs.first { $0.identifier?.rawValue == "tab-\(fixture.store.activeTabID)" })
        XCTAssertFalse(active.visibleRect.isEmpty)
        let fullTitle = fixture.store.title(for: fixture.store.activeTabID, language: .english)
        XCTAssertEqual(active.title, fullTitle)
        XCTAssertEqual(active.toolTip, fullTitle)
        XCTAssertTrue(active.accessibilityLabel()?.contains(fullTitle) == true)
        XCTAssertEqual(active.lineBreakMode, .byTruncatingTail)
        let positions = tabs.map { $0.convert($0.bounds, to: fixture.host).midY }
        XCTAssertLessThanOrEqual((positions.max() ?? 0) - (positions.min() ?? 0), 1)

        let first = try XCTUnwrap(tabs.first)
        first.performClick(nil)
        fixture.layout()
        XCTAssertFalse(first.visibleRect.isEmpty)
        active.performClick(nil)
        fixture.layout()
        XCTAssertFalse(active.visibleRect.isEmpty)

        plus.performClick(nil)
        fixture.layout()
        XCTAssertEqual(fixture.store.tabs.count, 22)
        let newTab = try XCTUnwrap(fixture.buttons.first {
            $0.identifier?.rawValue == "tab-\(fixture.store.activeTabID)"
        })
        XCTAssertFalse(newTab.visibleRect.isEmpty)
        XCTAssertTrue(fixture.host.bounds.contains(plus.convert(plus.bounds, to: fixture.host)))
    }
}

@MainActor
private final class PagerFixture {
    let suite = "TabPagerControlTests.\(UUID())"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults: UserDefaults
    let store: NoteStore
    let state: TitleEditingState
    let host: NSHostingView<TabPagerControl>
    let window: NSPanel

    init() throws {
        _ = NSApplication.shared
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        store = NoteStore(defaults: defaults, archiveURL: directory.appendingPathComponent("notes.json"))
        state = TitleEditingState(store: store)
        // 避免设置对象的防休眠恢复逻辑影响测试环境。
        defaults.set(true, forKey: "notchNotes.completedSleepGuardRecoveryV1")
        let settings = AppSettingsStore(defaults: defaults)
        host = NSHostingView(rootView: TabPagerControl(
            store: store, editorInteractionState: EditorInteractionState(),
            availableWidth: 360, settingsStore: settings, titleEditingState: state
        ))
        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 32),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 32)
    }

    var buttons: [NSButton] {
        descendants(of: host).compactMap { $0 as? NSButton }
    }

    var titleEditors: [TitleTextView] { descendants(of: host).compactMap { $0 as? TitleTextView } }

    func doubleClick(_ button: NSButton) throws {
        let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 2, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point,
            modifierFlags: [], timestamp: 0.01, windowNumber: window.windowNumber, context: nil,
            eventNumber: 2, clickCount: 2, pressure: 0))
        NSApp.postEvent(up, atStart: true)
        button.mouseDown(with: down)
        _ = NSApp.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true)
    }

    func layout() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        host.layoutSubtreeIfNeeded()
    }

    func cleanUp() {
        store.flush()
        window.close()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}
