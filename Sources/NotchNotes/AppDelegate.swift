import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: NotchPanelController?
    private var statusItem: NSStatusItem?
    private var languageCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = NotchPanelController()
        panelController?.showDocked()
        buildStatusItem()
        buildMenu()
        observeLanguageChanges()
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.flush()
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "NotchNotes")
        item.button?.imagePosition = .imageOnly
        item.menu = makeAppMenu()
        statusItem = item
    }

    private func buildMenu() {
        let rootItem = NSMenuItem(title: "NotchNotes", action: nil, keyEquivalent: "")
        rootItem.submenu = makeAppMenu()

        let editItem = NSMenuItem(title: localized(.editMenu), action: nil, keyEquivalent: "")
        editItem.submenu = makeEditMenu()

        let mainMenu = NSMenu()
        mainMenu.addItem(rootItem)
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func makeAppMenu() -> NSMenu {
        let appMenu = NSMenu()
        let newItem = NSMenuItem(title: localized(.newNoteMenu), action: #selector(newNote), keyEquivalent: "n")
        newItem.target = self
        appMenu.addItem(newItem)

        let showItem = NSMenuItem(title: localized(.showNotesMenu), action: #selector(showNotes), keyEquivalent: "")
        showItem.target = self
        appMenu.addItem(showItem)

        let hideItem = NSMenuItem(title: localized(.hideNotesMenu), action: #selector(hideNotes), keyEquivalent: "w")
        hideItem.target = self
        appMenu.addItem(hideItem)

        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: localized(.quitNotchNotesMenu), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)

        return appMenu
    }

    private func makeEditMenu() -> NSMenu {
        let editMenu = NSMenu(title: localized(.editMenu))

        let undoItem = NSMenuItem(title: localized(.undoMenu), action: Selector(("undo:")), keyEquivalent: "z")
        undoItem.target = nil
        editMenu.addItem(undoItem)

        let redoItem = NSMenuItem(title: localized(.redoMenu), action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        redoItem.target = nil
        editMenu.addItem(redoItem)

        editMenu.addItem(.separator())

        let cutItem = NSMenuItem(title: localized(.cutMenu), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        cutItem.target = nil
        editMenu.addItem(cutItem)

        let copyItem = NSMenuItem(title: localized(.copyMenu), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        copyItem.target = nil
        editMenu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: localized(.pasteMenu), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        pasteItem.target = nil
        editMenu.addItem(pasteItem)

        editMenu.addItem(.separator())

        let selectAllItem = NSMenuItem(title: localized(.selectAllMenu), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        selectAllItem.target = nil
        editMenu.addItem(selectAllItem)

        editMenu.addItem(.separator())

        let findMenuItem = NSMenuItem(title: localized(.findMenu), action: nil, keyEquivalent: "")
        let findMenu = NSMenu(title: localized(.findMenu))
        findMenu.addItem(findCommand(
            title: localized(.findDots),
            action: .showFindInterface,
            keyEquivalent: "f"
        ))
        findMenu.addItem(findCommand(
            title: localized(.findNextMenu),
            action: .nextMatch,
            keyEquivalent: "g"
        ))
        let previousItem = findCommand(
            title: localized(.findPreviousMenu),
            action: .previousMatch,
            keyEquivalent: "g"
        )
        previousItem.keyEquivalentModifierMask = [.command, .shift]
        findMenu.addItem(previousItem)
        findMenuItem.submenu = findMenu
        editMenu.addItem(findMenuItem)

        return editMenu
    }

    private func findCommand(
        title: String,
        action: NSTextFinder.Action,
        keyEquivalent: String
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(NSTextView.performFindPanelAction(_:)),
            keyEquivalent: keyEquivalent
        )
        item.tag = action.rawValue
        item.target = nil
        return item
    }

    private func observeLanguageChanges() {
        languageCancellable?.cancel()
        languageCancellable = panelController?.settingsStore.$language
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.buildStatusItem()
                self?.buildMenu()
            }
    }

    private func localized(_ key: LocalizedStringKey) -> String {
        let language = panelController?.settingsStore.language ?? .chinese
        return language.localized(key)
    }

    @objc private func newNote() {
        panelController?.createNote()
    }

    @objc private func showNotes() {
        panelController?.expand(animated: true)
    }

    @objc private func hideNotes() {
        panelController?.collapse(animated: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
