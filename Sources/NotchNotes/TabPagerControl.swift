import AppKit
import SwiftUI

@MainActor
enum TabPagerMetrics {
    static let height: CGFloat = 32
    static let buttonHeight: CGFloat = 28
    static let spacing: CGFloat = 6
    static let plusWidth: CGFloat = 28
    static let font = NSFont.systemFont(ofSize: 12, weight: .medium)

    static func titleWidth(_ title: String, availableWidth: CGFloat) -> CGFloat {
        let measured = (title as NSString).size(withAttributes: [.font: font]).width + 16
        return min(max(measured, 64), 160, max(availableWidth - plusWidth - spacing - 4, 1))
    }
}

struct TabPagerControl: View {
    @ObservedObject var store: NoteStore
    let editorInteractionState: EditorInteractionState
    let availableWidth: CGFloat
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var titleEditingState: TitleEditingState

    var body: some View {
        HStack(spacing: TabPagerMetrics.spacing) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TabPagerMetrics.spacing) {
                        ForEach(store.tabs) { tab in
                            let title = store.title(for: tab.id, language: settingsStore.language)
                            let session = titleEditingState.session
                            let isEditing = session?.tabID == tab.id
                            Group {
                                if isEditing {
                                    InlineTitleEditor(state: titleEditingState, language: settingsStore.language)
                                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                                } else {
                                    PagerButtonView(
                                        title: title,
                                        identifier: "tab-\(tab.id)",
                                        accessibilityName: settingsStore.language.localized(
                                            tab.id == store.activeTabID ? .currentNote(name: title) : .openNote(name: title)
                                        ),
                                        isSelected: tab.id == store.activeTabID,
                                        doubleAction: {
                                            rememberCurrentSelection()
                                            titleEditingState.begin(tabID: tab.id, language: settingsStore.language)
                                        }
                                    ) {
                                        rememberCurrentSelection()
                                        store.selectTab(tab.id)
                                    }
                                }
                            }
                            .frame(width: TabPagerMetrics.titleWidth(
                                isEditing ? (session?.initialEffectiveTitle ?? title) : title, availableWidth: availableWidth),
                                   height: TabPagerMetrics.buttonHeight)
                            .id(tab.id)
                            .contextMenu {
                                Button(role: .destructive) {
                                    rememberCurrentSelection()
                                    store.removeTab(tab.id)
                                } label: {
                                    Label(settingsStore.language.localized(.deleteThisNote), systemImage: "trash")
                                }
                                .disabled(store.tabs.count <= 1)
                            }
                        }
                    }
                }
                .onAppear { revealActive(using: proxy) }
                .onChange(of: store.activeTabID) { _, _ in revealActive(using: proxy) }
                .onChange(of: titles) { _, _ in revealActive(using: proxy) }
                .onChange(of: titleEditingState.session?.generation) { _, _ in revealActive(using: proxy) }
            }
            PagerButtonView(
                title: "+", identifier: "new-note",
                accessibilityName: settingsStore.language.localized(.newNote), isSelected: false
            ) {
                rememberCurrentSelection()
                store.addTab()
            }
            .frame(width: TabPagerMetrics.plusWidth, height: TabPagerMetrics.buttonHeight)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .frame(width: availableWidth, height: TabPagerMetrics.height)
        .overlay(alignment: .topLeading) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: availableWidth, alignment: .leading)
                    .background(Color(red: 0.22, green: 0.08, blue: 0.08), in: RoundedRectangle(cornerRadius: 7))
                    .offset(y: TabPagerMetrics.height + 4)
                    .allowsHitTesting(false)
            }
        }
    }

    var errorMessage: String? {
        (titleEditingState.session?.error ?? titleEditingState.lastError)?.localized(for: settingsStore.language)
    }

    private var titles: [String] {
        store.tabs.map { store.title(for: $0.id, language: settingsStore.language) }
    }

    private func revealActive(using proxy: ScrollViewProxy) {
        let id = store.activeTabID
        DispatchQueue.main.async {
            guard store.activeTabID == id else { return }
            proxy.scrollTo(id, anchor: .trailing)
        }
    }

    private func rememberCurrentSelection() {
        guard let range = editorInteractionState.currentSelectionRange(for: store.activeTabID) else { return }
        store.updateSelection(for: store.activeTabID, range: range)
    }
}

struct PagerButtonView: NSViewRepresentable {
    let title: String
    let identifier: String
    let accessibilityName: String
    let isSelected: Bool
    var doubleAction: (() -> Void)? = nil
    let action: () -> Void

    func makeNSView(context: Context) -> PagerButton {
        let button = PagerButton()
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.font = TabPagerMetrics.font
        button.lineBreakMode = .byTruncatingTail
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.target = button
        button.action = #selector(PagerButton.invokeAction)
        return button
    }

    func updateNSView(_ button: PagerButton, context: Context) {
        button.title = title
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.toolTip = identifier == "new-note" ? accessibilityName : title
        button.setAccessibilityLabel(accessibilityName)
        button.contentTintColor = .white.withAlphaComponent(isSelected ? 0.94 : 0.66)
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(isSelected ? 0.12 : 0.035).cgColor
        button.onAction = action
        button.onDoubleAction = doubleAction
    }
}

final class PagerButton: NSButton {
    var onAction: (() -> Void)?
    var onDoubleAction: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let onDoubleAction {
            onDoubleAction()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc func invokeAction() {
        onAction?()
    }
}
