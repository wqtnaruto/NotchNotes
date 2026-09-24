import Combine
import Foundation

@MainActor
final class TitleEditingState: ObservableObject {
    struct Session {
        let tabID: UUID
        let generation: UUID
        let initialEffectiveTitle: String
        var draft: String
        var selection: NSRange
        var isComposing = false
        var error: NoteTitleError?
    }

    @Published private(set) var session: Session?
    @Published private(set) var lastError: NoteTitleError?
    private let store: NoteStore
    var isEditing: Bool { session != nil }

    private var isCommitting = false
    var onEditingChanged: ((Bool) -> Void)?

    init(store: NoteStore) { self.store = store }

    @discardableResult
    func begin(tabID: UUID, language: AppLanguage) -> Bool {
        guard !isCommitting else { return false }
        if session?.tabID == tabID { return true }
        guard commitIfNeeded() else { return false }
        guard store.tabs.contains(where: { $0.id == tabID }) else {
            lastError = .targetMissing
            return false
        }
        let title = store.title(for: tabID, language: language)
        lastError = nil
        session = Session(tabID: tabID, generation: UUID(), initialEffectiveTitle: title,
                          draft: title, selection: NSRange(location: 0, length: title.utf16.count))
        onEditingChanged?(true)
        store.selectTab(tabID)
        return true
    }

    func updateDraft(_ value: String, selection: NSRange, isComposing: Bool) {
        guard var current = session else { return }
        let changed = current.draft != value
        current.draft = value
        current.selection = selection
        current.isComposing = isComposing
        if !isComposing {
            if NoteTitlePolicy.normalize(value).count > 50 {
                current.error = .tooLong
            } else if changed || current.error == .tooLong {
                current.error = nil
            }
        }
        session = current
    }

    @discardableResult
    func commitIfNeeded() -> Bool {
        guard !isCommitting else { return false }
        guard let current = session else { return true }
        isCommitting = true
        defer { isCommitting = false }
        do {
            guard store.tabs.contains(where: { $0.id == current.tabID }) else {
                throw NoteTitleError.targetMissing
            }
            let change = try NoteTitlePolicy.change(for: current.draft, initialEffectiveTitle: current.initialEffectiveTitle)
            try store.commitTitle(for: current.tabID, change: change)
            endSession()
            return true
        } catch {
            let failure = error as? NoteTitleError ?? .saveFailed
            if failure == .targetMissing {
                endSession()
                lastError = failure
            } else {
                session?.error = failure
            }
            return false
        }
    }

    func cancel() {
        guard !isCommitting else { return }
        endSession()
        lastError = nil
    }

    private func endSession() {
        let wasEditing = isEditing
        session = nil
        if wasEditing { onEditingChanged?(false) }
    }
}
