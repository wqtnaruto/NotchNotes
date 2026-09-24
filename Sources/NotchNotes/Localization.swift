import Foundation
import MarkdownEngine

enum LocalizedStringKey {
    // Settings
    case settingsTitle
    case triggerModeTitle
    case languageTitle
    case hover
    case click
    case keepMacAwake
    case stopKeepingMacAwake
    case changingKeepAwake
    case keepAwakeErrorRestore
    case keepAwakeErrorPrevent
    case couldNotKeepMacAwake
    case ok
    case accessibilityOn
    case accessibilityOff

    // Editor
    case startTyping
    case newNote
    case currentNote(name: String)
    case openNote(name: String)
    case deleteThisNote

    // Note titles
    case untitled
    case untitledNumbered(index: Int)
    case titleTooLong
    case titleSaveFailed
    case titleTargetMissing

    // File shelf
    case removeAllShelfItems
    case releaseToAdd
    case folder
    case file
    case removeFromShelf
    case open
    case showInFinder
    case removeFromShelfMenu
    case pressSpaceToPreview(name: String, kind: String)
    case fileUnavailable(name: String)

    // Menu bar
    case newNoteMenu
    case showNotesMenu
    case hideNotesMenu
    case quitNotchNotesMenu
    case editMenu
    case undoMenu
    case redoMenu
    case cutMenu
    case copyMenu
    case pasteMenu
    case selectAllMenu
    case findMenu
    case findDots
    case findNextMenu
    case findPreviousMenu

    // Markdown commands
    case bold
    case italic
    case strikethrough
    case inlineCode
    case link
    case quote
    case bulletedList
    case numberedList
    case todoList

    // Markdown context menu
    case formatMenu
    case headingMenu
    case listsMenu
    case bulletList
    case numberedListMenu
    case copyImage
    case copyImageFile
    case copyOriginalFile
    case showCopyInFinder
    case showOriginalInFinder
    case copyMarkdownReference
    case insertImageEmbed
    case insertLink

    // Markdown placeholders
    case boldPlaceholder
    case italicPlaceholder
    case strikethroughPlaceholder
    case inlineCodePlaceholder
    case linkTextPlaceholder
}

extension NoteTitleError {
    func localized(for language: AppLanguage) -> String {
        switch self {
        case .tooLong: return language.localized(.titleTooLong)
        case .saveFailed: return language.localized(.titleSaveFailed)
        case .targetMissing: return language.localized(.titleTargetMissing)
        }
    }
}

extension AppLanguage {
    func localized(_ key: LocalizedStringKey) -> String {
        switch key {
        // Settings
        case .settingsTitle:
            return self == .chinese ? "设置" : "Settings"
        case .triggerModeTitle:
            return self == .chinese ? "触发方式" : "Trigger"
        case .languageTitle:
            return self == .chinese ? "语言" : "Language"
        case .hover:
            return self == .chinese ? "悬停" : "Hover"
        case .click:
            return self == .chinese ? "点按" : "Click"
        case .keepMacAwake:
            return self == .chinese
                ? "即使合上盖盖也保持 Mac 唤醒"
                : "Keep Mac awake, even with the lid closed"
        case .stopKeepingMacAwake:
            return self == .chinese ? "停止保持 Mac 唤醒" : "Stop keeping Mac awake"
        case .changingKeepAwake:
            return self == .chinese ? "正在切换保持唤醒…" : "Changing keep-awake mode…"
        case .keepAwakeErrorRestore:
            return self == .chinese
                ? "需要管理员权限才能恢复正常的睡眠。"
                : "Administrator permission is required to restore normal sleep."
        case .keepAwakeErrorPrevent:
            return self == .chinese
                ? "需要管理员权限才能在合上盖盖时阻止睡眠。"
                : "Administrator permission is required to prevent sleep when the lid is closed."
        case .couldNotKeepMacAwake:
            return self == .chinese ? "无法保持 Mac 唤醒" : "Couldn’t Keep Mac Awake"
        case .ok:
            return self == .chinese ? "好" : "OK"
        case .accessibilityOn:
            return self == .chinese ? "开启" : "On"
        case .accessibilityOff:
            return self == .chinese ? "关闭" : "Off"

        // Editor
        case .startTyping:
            return self == .chinese ? "开始输入…" : "Start typing…"
        case .newNote:
            return self == .chinese ? "新建笔记" : "New note"
        case let .currentNote(name):
            return self == .chinese ? "当前笔记：\(name)" : "Current note: \(name)"
        case let .openNote(name):
            return self == .chinese ? "打开笔记：\(name)" : "Open note: \(name)"
        case .deleteThisNote:
            return self == .chinese ? "删除此笔记" : "Delete This Note"

        // Note titles
        case .titleTooLong:
            return self == .chinese
                ? "标题最多 50 个字符，请缩短后重试。"
                : "Titles can contain up to 50 characters. Shorten the title and try again."
        case .titleSaveFailed:
            return self == .chinese
                ? "标题未保存，请重试或按 Esc 取消。"
                : "Title wasn't saved. Try again or press Esc to cancel."
        case .titleTargetMissing:
            return self == .chinese
                ? "该分页已不存在，未保存标题。"
                : "This note no longer exists. The title wasn't saved."
        case .untitled:
            return self == .chinese ? "无标题" : "Untitled"
        case let .untitledNumbered(index):
            return self == .chinese ? "无标题 \(index)" : "Untitled \(index)"

        // File shelf
        case .removeAllShelfItems:
            return self == .chinese ? "移除所有文件架项目" : "Remove All Shelf Items"
        case .releaseToAdd:
            return self == .chinese ? "松开以添加" : "Release to add"
        case .folder:
            return self == .chinese ? "文件夹" : "Folder"
        case .file:
            return self == .chinese ? "文件" : "File"
        case .removeFromShelf:
            return self == .chinese ? "从文件架移除（文件仍保留在磁盘）" : "Remove from shelf (file stays on disk)"
        case .open:
            return self == .chinese ? "打开" : "Open"
        case .showInFinder:
            return self == .chinese ? "在 Finder 中显示" : "Show in Finder"
        case .removeFromShelfMenu:
            return self == .chinese ? "从文件架移除" : "Remove from Shelf"
        case let .pressSpaceToPreview(name, kind):
            return self == .chinese
                ? "\(name) · \(kind) · 按空格键预览"
                : "\(name) · \(kind) · Press Space to preview"
        case let .fileUnavailable(name):
            return self == .chinese ? "\(name) 不可用" : "\(name) is unavailable"

        // Menu bar
        case .newNoteMenu:
            return self == .chinese ? "新建笔记" : "New Note"
        case .showNotesMenu:
            return self == .chinese ? "显示笔记" : "Show Notes"
        case .hideNotesMenu:
            return self == .chinese ? "隐藏笔记" : "Hide Notes"
        case .quitNotchNotesMenu:
            return self == .chinese ? "退出 NotchNotes" : "Quit NotchNotes"
        case .editMenu:
            return self == .chinese ? "编辑" : "Edit"
        case .undoMenu:
            return self == .chinese ? "撤销" : "Undo"
        case .redoMenu:
            return self == .chinese ? "重做" : "Redo"
        case .cutMenu:
            return self == .chinese ? "剪切" : "Cut"
        case .copyMenu:
            return self == .chinese ? "拷贝" : "Copy"
        case .pasteMenu:
            return self == .chinese ? "粘贴" : "Paste"
        case .selectAllMenu:
            return self == .chinese ? "全选" : "Select All"
        case .findMenu:
            return self == .chinese ? "查找" : "Find"
        case .findDots:
            return self == .chinese ? "查找…" : "Find…"
        case .findNextMenu:
            return self == .chinese ? "查找下一个" : "Find Next"
        case .findPreviousMenu:
            return self == .chinese ? "查找上一个" : "Find Previous"

        // Markdown commands
        case .bold:
            return self == .chinese ? "粗体" : "Bold"
        case .italic:
            return self == .chinese ? "斜体" : "Italic"
        case .strikethrough:
            return self == .chinese ? "删除线" : "Strikethrough"
        case .inlineCode:
            return self == .chinese ? "行内代码" : "Inline code"
        case .link:
            return self == .chinese ? "链接" : "Link"
        case .quote:
            return self == .chinese ? "引用" : "Quote"
        case .bulletedList:
            return self == .chinese ? "项目列表" : "Bulleted list"
        case .numberedList:
            return self == .chinese ? "编号列表" : "Numbered list"
        case .todoList:
            return self == .chinese ? "待办列表" : "Todo list"

        // Markdown context menu
        case .formatMenu:
            return self == .chinese ? "格式" : "Format"
        case .headingMenu:
            return self == .chinese ? "标题" : "Heading"
        case .listsMenu:
            return self == .chinese ? "列表" : "Lists"
        case .bulletList:
            return self == .chinese ? "项目符号" : "Bullet"
        case .numberedListMenu:
            return self == .chinese ? "编号" : "Numbered"
        case .copyImage:
            return self == .chinese ? "复制图片" : "Copy Image"
        case .copyImageFile:
            return self == .chinese ? "复制图片文件" : "Copy Image File"
        case .copyOriginalFile:
            return self == .chinese ? "复制原始文件" : "Copy Original File"
        case .showCopyInFinder:
            return self == .chinese ? "在 Finder 中显示副本" : "Show Copy in Finder"
        case .showOriginalInFinder:
            return self == .chinese ? "在 Finder 中显示原始文件" : "Show Original in Finder"
        case .copyMarkdownReference:
            return self == .chinese ? "复制 Markdown 引用" : "Copy Markdown Reference"
        case .insertImageEmbed:
            return self == .chinese ? "插入图片嵌入" : "Insert Image Embed"
        case .insertLink:
            return self == .chinese ? "插入链接" : "Insert Link"

        // Markdown placeholders
        case .boldPlaceholder:
            return self == .chinese ? "粗体" : "bold"
        case .italicPlaceholder:
            return self == .chinese ? "斜体" : "italic"
        case .strikethroughPlaceholder:
            return self == .chinese ? "删除线" : "strikethrough"
        case .inlineCodePlaceholder:
            return self == .chinese ? "代码" : "code"
        case .linkTextPlaceholder:
            return self == .chinese ? "链接文本" : "link text"
        }
    }
}

struct MarkdownEditorLocalizationAdapter: MarkdownEngine.MarkdownEditorLocalization {
    let language: AppLanguage

    func string(for key: MarkdownEngine.MarkdownEditorLocalizedStringKey) -> String {
        switch key {
        case .format:
            return language.localized(.formatMenu)
        case .bold:
            return language.localized(.bold)
        case .italic:
            return language.localized(.italic)
        case .heading:
            return language.localized(.headingMenu)
        case .headingLevel(let level):
            return "H\(level)"
        case .lists:
            return language.localized(.listsMenu)
        case .bullet:
            return language.localized(.bulletList)
        case .numbered:
            return language.localized(.numberedListMenu)
        case .copyImage:
            return language.localized(.copyImage)
        case .copyImageFile:
            return language.localized(.copyImageFile)
        case .copyOriginalFile:
            return language.localized(.copyOriginalFile)
        case .showCopyInFinder:
            return language.localized(.showCopyInFinder)
        case .showOriginalInFinder:
            return language.localized(.showOriginalInFinder)
        case .copyMarkdownReference:
            return language.localized(.copyMarkdownReference)
        case .insertImageEmbed:
            return language.localized(.insertImageEmbed)
        case .insertLink:
            return language.localized(.insertLink)
        }
    }
}
