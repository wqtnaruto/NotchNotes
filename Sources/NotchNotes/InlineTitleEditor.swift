import AppKit
import SwiftUI

struct InlineTitleEditor: NSViewRepresentable {
    @ObservedObject var state: TitleEditingState
    let language: AppLanguage

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        let textView = TitleTextView(frame: NSRect(x: 0, y: 0, width: 160, height: 28))
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = false
        textView.minSize = NSSize(width: 0, height: 28)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 28)
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 28)
        textView.textContainer?.widthTracksTextView = false
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        (scroll.documentView as? TitleTextView)?.bind(state: state, language: language)
    }
}

final class TitleTextView: NSTextView, NSTextViewDelegate {
    private weak var editingState: TitleEditingState?
    private var generation: UUID?
    private var isApplyingSession = false

    func bind(state: TitleEditingState, language: AppLanguage) {
        editingState = state
        guard let session = state.session else { return }
        let message = session.error?.localized(for: language)
        toolTip = message
        setAccessibilityHelp(message)
        guard generation != session.generation else { return }
        generation = session.generation
        isApplyingSession = true
        defer { isApplyingSession = false }
        delegate = self
        isRichText = false
        importsGraphics = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        drawsBackground = false
        font = TabPagerMetrics.font
        textColor = .white
        insertionPointColor = .white
        textContainerInset = NSSize(width: 5, height: 6)
        string = session.draft
        setSelectedRange(session.selection)
        requestTitleFocus()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        requestTitleFocus()
    }

    override func didChangeText() {
        super.didChangeText()
        synchronizeDraft()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        synchronizeDraft()
    }

    func synchronizeDraft() {
        guard !isApplyingSession, let editingState,
              editingState.session?.generation == generation else { return }
        editingState.updateDraft(string, selection: selectedRange(), isComposing: hasMarkedText())
    }

    override func doCommand(by selector: Selector) {
        guard !hasMarkedText() else {
            super.doCommand(by: selector)
            return
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            finish(cancel: false)
        } else if selector == #selector(NSResponder.cancelOperation(_:)) {
            finish(cancel: true)
        } else {
            super.doCommand(by: selector)
        }
    }

    func finish(cancel: Bool) {
        guard let editingState, let session = editingState.session,
              session.generation == generation else { return }
        synchronizeDraft()
        let target = session.tabID
        if cancel { editingState.cancel() }
        else if !editingState.commitIfNeeded() { return }
        Self.restoreLabelFocus(tabID: target, window: window, state: editingState)
    }

    private func requestTitleFocus() {
        let expected = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, let expected,
                  self.generation == expected,
                  self.editingState?.session?.generation == expected,
                  NSApp.isActive, let window = self.window, window.isKeyWindow else { return }
            window.makeFirstResponder(self)
            self.scrollRangeToVisible(self.selectedRange())
        }
    }

    static func restoreLabelFocus(tabID: UUID, window: NSWindow?, state: TitleEditingState) {
        DispatchQueue.main.async { [weak window, weak state] in
            guard let window, let state, !state.isEditing, NSApp.isActive, window.isKeyWindow,
                  let button = findLabel(in: window.contentView, tabID: tabID) else { return }
            window.makeFirstResponder(button)
        }
    }

    private static func findLabel(in view: NSView?, tabID: UUID) -> NSView? {
        guard let view else { return nil }
        if view.identifier?.rawValue == "tab-\(tabID)" { return view }
        return view.subviews.lazy.compactMap { findLabel(in: $0, tabID: tabID) }.first
    }
}
