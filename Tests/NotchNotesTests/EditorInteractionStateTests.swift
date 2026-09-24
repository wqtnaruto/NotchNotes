import AppKit
import MarkdownEngine
import SwiftUI
import XCTest
@testable import NotchNotes

@MainActor
final class EditorInteractionStateTests: XCTestCase {
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
}

private struct HostedBody: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
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
