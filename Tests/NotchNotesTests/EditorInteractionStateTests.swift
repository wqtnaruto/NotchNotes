import AppKit
import MarkdownEngine
import SwiftUI
import XCTest
@testable import NotchNotes

@MainActor
final class EditorInteractionStateTests: XCTestCase {
    func testMarkdownShortcutMappingsMatchProductSpec() {
        let cases: [(MarkdownCommand, Character, EventModifiers, String)] = [
            (.bold, "b", [.command], "⌘B"),
            (.italic, "i", [.command], "⌘I"),
            (.strikethrough, "x", [.command, .shift], "⌘⇧X"),
            (.inlineCode, "c", [.command, .shift], "⌘⇧C"),
            (.link, "k", [.command], "⌘K"),
            (.quote, ".", [.command, .shift], "⌘⇧>"),
            (.unorderedList, "8", [.command, .shift], "⌘⇧8"),
            (.orderedList, "7", [.command, .shift], "⌘⇧7"),
            (.todoList, "9", [.command, .shift], "⌘⇧9")
        ]

        for (command, key, modifiers, displayText) in cases {
            XCTAssertEqual(command.shortcut.key, key, command.id)
            XCTAssertEqual(command.shortcut.modifiers, modifiers, command.id)
            XCTAssertEqual(command.shortcut.displayText, displayText, command.id)
        }
    }

    func testMarkdownShortcutsAreUniqueAndDoNotCollideWithExistingAppCommands() {
        let signatures = MarkdownCommand.allCases.map { shortcutSignature($0.shortcut) }
        XCTAssertEqual(Set(signatures).count, MarkdownCommand.allCases.count)

        let reserved: Set<String> = [
            ("n", EventModifiers.command),
            ("w", EventModifiers.command),
            ("q", EventModifiers.command),
            ("z", EventModifiers.command),
            ("z", [EventModifiers.command, .shift]),
            ("x", EventModifiers.command),
            ("c", EventModifiers.command),
            ("v", EventModifiers.command),
            ("a", EventModifiers.command),
            ("f", EventModifiers.command),
            ("g", EventModifiers.command),
            ("g", [EventModifiers.command, .shift])
        ].map { key, modifiers in
            "\(key)|\(modifiers.rawValue)"
        }.reduce(into: Set<String>()) { $0.insert($1) }

        XCTAssertTrue(Set(signatures).isDisjoint(with: reserved))
    }

    func testAllMarkdownCommandsTransformSelectedContentLikeToolbarActions() {
        assertMarkdownCommand(.bold, input: "text", selection: NSRange(location: 0, length: 4),
                              expected: "**text**", expectedSelection: NSRange(location: 2, length: 4))
        assertMarkdownCommand(.italic, input: "text", selection: NSRange(location: 0, length: 4),
                              expected: "*text*", expectedSelection: NSRange(location: 1, length: 4))
        assertMarkdownCommand(.strikethrough, input: "text", selection: NSRange(location: 0, length: 4),
                              expected: "~~text~~", expectedSelection: NSRange(location: 2, length: 4))
        assertMarkdownCommand(.inlineCode, input: "text", selection: NSRange(location: 0, length: 4),
                              expected: "`text`", expectedSelection: NSRange(location: 1, length: 4))
        assertMarkdownCommand(.link, input: "text", selection: NSRange(location: 0, length: 4),
                              expected: "[text](url)", expectedSelection: NSRange(location: 7, length: 3))
        assertMarkdownCommand(.quote, input: "alpha\nbeta", selection: NSRange(location: 0, length: 10),
                              expected: "> alpha\n> beta", expectedSelection: NSRange(location: 0, length: 14))
        assertMarkdownCommand(.unorderedList, input: "alpha\nbeta", selection: NSRange(location: 0, length: 10),
                              expected: "- alpha\n- beta", expectedSelection: NSRange(location: 0, length: 14))
        assertMarkdownCommand(.orderedList, input: "alpha\nbeta", selection: NSRange(location: 0, length: 10),
                              expected: "1. alpha\n2. beta", expectedSelection: NSRange(location: 0, length: 16))
        assertMarkdownCommand(.todoList, input: "alpha\nbeta", selection: NSRange(location: 0, length: 10),
                              expected: "- [ ] alpha\n- [ ] beta", expectedSelection: NSRange(location: 0, length: 22))
    }

    func testAllMarkdownCommandsHandleEmptySelectionLikeToolbarActions() {
        assertMarkdownCommand(.bold, input: "", selection: .init(location: 0, length: 0),
                              expected: "**粗体**", expectedSelection: .init(location: 2, length: 2))
        assertMarkdownCommand(.italic, input: "", selection: .init(location: 0, length: 0),
                              expected: "*斜体*", expectedSelection: .init(location: 1, length: 2))
        assertMarkdownCommand(.strikethrough, input: "", selection: .init(location: 0, length: 0),
                              expected: "~~删除线~~", expectedSelection: .init(location: 2, length: 3))
        assertMarkdownCommand(.inlineCode, input: "", selection: .init(location: 0, length: 0),
                              expected: "`代码`", expectedSelection: .init(location: 1, length: 2))
        assertMarkdownCommand(.link, input: "", selection: .init(location: 0, length: 0),
                              expected: "[链接文本](url)", expectedSelection: .init(location: 1, length: 4))
        assertMarkdownCommand(.quote, input: "alpha", selection: .init(location: 2, length: 0),
                              expected: "> alpha", expectedSelection: .init(location: 0, length: 7))
        assertMarkdownCommand(.unorderedList, input: "alpha", selection: .init(location: 2, length: 0),
                              expected: "- alpha", expectedSelection: .init(location: 0, length: 7))
        assertMarkdownCommand(.orderedList, input: "alpha", selection: .init(location: 2, length: 0),
                              expected: "1. alpha", expectedSelection: .init(location: 0, length: 8))
        assertMarkdownCommand(.todoList, input: "alpha", selection: .init(location: 2, length: 0),
                              expected: "- [ ] alpha", expectedSelection: .init(location: 0, length: 11))
    }

    func testMarkdownCommandRegistersOneUndoableEdit() throws {
        let body = BodyFixture()
        body.view.string = "text"
        body.view.setSelectedRange(NSRange(location: 0, length: 4))
        body.view.allowsUndo = true
        let state = EditorInteractionState()
        state.bind(containerView: body.view, textView: body.view)

        state.applyMarkdownCommand(.bold, language: .english)

        XCTAssertEqual(body.view.string, "**text**")
        let undoManager = try XCTUnwrap(body.view.undoManager)
        XCTAssertTrue(undoManager.canUndo)
        undoManager.undo()
        XCTAssertEqual(body.view.string, "text")
    }

    func testMarkdownCommandPublishesChangeAfterApplyingFinalSelection() {
        let body = BodyFixture()
        body.view.string = "text"
        body.view.setSelectedRange(NSRange(location: 0, length: 4))
        let state = EditorInteractionState()
        state.bind(containerView: body.view, textView: body.view)
        let capture = SelectionCapture()
        let observer = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: body.view,
            queue: .main
        ) { [weak view = body.view] _ in
            MainActor.assumeIsolated {
                capture.value = view?.selectedRange()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        state.applyMarkdownCommand(.bold, language: .english)

        XCTAssertEqual(body.view.string, "**text**")
        XCTAssertEqual(capture.value, NSRange(location: 2, length: 4))
    }

    func testMarkdownCommandAppliesVisualStyleAndHidesMarkersWithoutFollowupKeystroke() throws {
        let body = BodyFixture()
        body.view.string = "text"
        body.view.setSelectedRange(NSRange(location: 0, length: 4))
        let state = EditorInteractionState()
        state.bind(containerView: body.view, textView: body.view)

        state.applyMarkdownCommand(.bold, language: .english)

        let contentFont = try XCTUnwrap(body.view.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)
        let markerFont = try XCTUnwrap(body.view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(contentFont.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertEqual(markerFont.pointSize, MarkdownEditorConfiguration.default.markers.hiddenMarkerFontSize,
                       accuracy: 0.01)
    }

    func testReplacingCommandPlaceholderKeepsRenderedStyleWithoutTrailingSpace() throws {
        let body = BodyFixture()
        body.view.string = ""
        body.view.setSelectedRange(NSRange(location: 0, length: 0))
        let state = EditorInteractionState()
        state.bind(containerView: body.view, textView: body.view)
        state.applyMarkdownCommand(.bold, language: .english)

        body.view.insertText("hello", replacementRange: body.view.selectedRange())

        XCTAssertEqual(body.view.string, "**hello**")
        XCTAssertEqual(body.view.selectedRange(), NSRange(location: 7, length: 0))
        let contentFont = try XCTUnwrap(body.view.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)
        let markerFont = try XCTUnwrap(body.view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(contentFont.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertEqual(markerFont.pointSize, MarkdownEditorConfiguration.default.markers.hiddenMarkerFontSize,
                       accuracy: 0.01)
    }

    func testToolbarKeyboardShortcutRoutesToMarkdownCommand() throws {
        try withIsolatedSettings { defaults in
            let body = BodyFixture()
            body.view.string = "text"
            body.view.setSelectedRange(NSRange(location: 0, length: 4))
            let state = EditorInteractionState()
            state.bind(containerView: body.view, textView: body.view)
            let toolbar = MarkdownShortcutToolbar(
                settingsStore: AppSettingsStore(defaults: defaults),
                editorInteractionState: state
            )
            let host = NSHostingView(rootView: toolbar)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 38),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "b",
                charactersIgnoringModifiers: "b",
                isARepeat: false,
                keyCode: 11
            ))

            XCTAssertTrue(window.performKeyEquivalent(with: event))
            XCTAssertEqual(body.view.string, "**text**")
            XCTAssertEqual(body.view.selectedRange(), NSRange(location: 2, length: 4))
        }
    }

    func testTitleViewCannotBecomeBodyBinding() {
        let state = EditorInteractionState()
        let title = TitleTextView()
        title.string = "标题草稿"
        title.setSelectedRange(NSRange(location: 1, length: 2))
        state.bind(containerView: title, textView: title)
        XCTAssertNil(state.currentSelectionRange())
        state.applyMarkdownCommand(.bold, language: .chinese)
        XCTAssertEqual(title.string, "标题草稿")
    }

    func testFieldEditorWithBodyDelegateCannotBecomeBodyBinding() {
        let body = BodyFixture()
        body.view.isFieldEditor = true
        let state = EditorInteractionState()
        state.bind(containerView: body.view, textView: body.view, documentID: UUID())
        XCTAssertNil(state.currentSelectionRange())
        XCTAssertFalse(EditorInteractionState.isBodyTextView(body.view))
    }

    func testSelectionQueryRejectsDifferentDocumentAndSuspendedFocus() {
        let body = BodyFixture()
        let state = EditorInteractionState()
        let id = UUID()
        body.view.setSelectedRange(NSRange(location: 1, length: 2))
        state.bind(containerView: body.view, textView: body.view, documentID: id)
        XCTAssertEqual(state.currentSelectionRange(for: id), NSRange(location: 1, length: 2))
        XCTAssertNil(state.currentSelectionRange(for: UUID()))
        state.isFocusSuspended = true
        XCTAssertNil(state.currentSelectionRange(for: id))
        state.isFocusSuspended = false
        state.prepareForDocument(UUID())
        XCTAssertNil(state.currentSelectionRange())
    }

    func testSuspendedFocusIgnoresQueuedRetry() {
        let body = BodyFixture()
        let state = EditorInteractionState()
        state.requestFocus(searchingIn: body.view)
        state.isFocusSuspended = true
        state.bind(containerView: body.view, textView: body.view)
        state.requestFocus(searchingIn: body.view)
        state.isFocusSuspended = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        XCTAssertEqual(body.window.focusRequests, 0)
    }

    func testSelectionNotificationKeepsOriginDocumentID() async {
        let body = BodyFixture()
        let state = EditorInteractionState()
        let firstID = UUID()
        let secondID = UUID()
        var changes: [(UUID, NSRange)] = []
        state.onDocumentSelectionChange = { changes.append(($0, $1)) }
        state.bind(containerView: body.view, textView: body.view, documentID: firstID)
        body.view.setSelectedRange(NSRange(location: 1, length: 2))
        await Task.yield()
        XCTAssertTrue(changes.contains { $0.0 == firstID && $0.1 == NSRange(location: 1, length: 2) })
        changes.removeAll()
        body.view.setSelectedRange(NSRange(location: 4, length: 1))
        state.bind(containerView: body.view, textView: body.view, documentID: secondID)
        await Task.yield()
        XCTAssertFalse(changes.contains { $0.0 == secondID })
        body.view.setSelectedRange(NSRange(location: 0, length: 3))
        await Task.yield()
        XCTAssertTrue(changes.contains { $0.0 == secondID && $0.1 == NSRange(location: 0, length: 3) })
    }

    func testBinderFindsBodyBesideTitleAndRebindsDocument() {
        let body = BodyFixture()
        let title = TitleTextView()
        title.string = "独立标题"
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        container.addSubview(title)
        container.addSubview(body.view)
        let state = EditorInteractionState()
        let first = UUID(), second = UUID()
        body.view.setSelectedRange(NSRange(location: 2, length: 2))
        let host = NSHostingView(rootView: HostedBody(view: container)
            .background(EditorFocusBinder(state: state, documentID: first)))
        host.frame = container.frame
        body.window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        XCTAssertEqual(state.currentSelectionRange(for: first), NSRange(location: 2, length: 2))
        host.rootView = HostedBody(view: container)
            .background(EditorFocusBinder(state: state, documentID: second))
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        XCTAssertNil(state.currentSelectionRange(for: first))
        XCTAssertEqual(state.currentSelectionRange(for: second), NSRange(location: 2, length: 2))
        XCTAssertEqual(title.string, "独立标题")
        XCTAssertEqual(body.window.focusRequests, 0)
    }

    func testMarkdownCommandIsIgnoredDuringTitleEditing() {
        let body = BodyFixture()
        let state = EditorInteractionState()
        state.bind(containerView: body.view, textView: body.view)
        let original = body.view.string
        state.isFocusSuspended = true
        state.applyMarkdownCommand(.bold, language: .chinese)
        XCTAssertEqual(body.view.string, original)
        XCTAssertEqual(body.window.focusRequests, 0)
    }

    private func assertMarkdownCommand(
        _ command: MarkdownCommand,
        input: String,
        selection: NSRange,
        expected: String,
        expectedSelection: NSRange,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let body = BodyFixture()
        body.view.string = input
        body.view.setSelectedRange(selection)
        let state = EditorInteractionState()
        state.bind(containerView: body.view, textView: body.view)

        state.applyMarkdownCommand(command, language: .chinese)

        XCTAssertEqual(body.view.string, expected, file: file, line: line)
        XCTAssertEqual(body.view.selectedRange(), expectedSelection, file: file, line: line)
    }

    private func shortcutSignature(_ shortcut: MarkdownShortcut) -> String {
        "\(shortcut.key)|\(shortcut.modifiers.rawValue)"
    }
}

private struct HostedBody: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class SelectionCapture: @unchecked Sendable {
    var value: NSRange?
}

@MainActor
private final class BodyFixture {
    let view = NSTextView()
    let coordinator = NativeTextViewWrapper(text: .constant("正文保持不变")).makeCoordinator()
    let window: FocusRecordingPanel

    init() {
        _ = NSApplication.shared
        window = FocusRecordingPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        view.string = "正文保持不变"
        view.delegate = coordinator
        window.contentView = view
        window.focusRequests = 0
    }
}

@MainActor
private final class FocusRecordingPanel: NSPanel {
    var focusRequests = 0
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        focusRequests += 1
        return false
    }
    override func makeKeyAndOrderFront(_ sender: Any?) {}
}
