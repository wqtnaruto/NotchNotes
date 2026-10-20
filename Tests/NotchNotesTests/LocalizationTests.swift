import XCTest
@testable import NotchNotes

final class LocalizationTests: XCTestCase {
    func testSettingsAndLanguageStrings() {
        XCTAssertEqual(AppLanguage.chinese.localized(.settingsTitle), "设置")
        XCTAssertEqual(AppLanguage.english.localized(.settingsTitle), "Settings")
        XCTAssertEqual(AppLanguage.chinese.localized(.languageTitle), "语言")
        XCTAssertEqual(AppLanguage.english.localized(.languageTitle), "Language")
    }

    func testTriggerModeStrings() {
        XCTAssertEqual(AppLanguage.chinese.localized(.hover), "悬停")
        XCTAssertEqual(AppLanguage.english.localized(.hover), "Hover")
        XCTAssertEqual(AppLanguage.chinese.localized(.click), "点按")
        XCTAssertEqual(AppLanguage.english.localized(.click), "Click")
    }

    func testEditorStrings() {
        XCTAssertEqual(AppLanguage.chinese.localized(.startTyping), "开始输入…")
        XCTAssertEqual(AppLanguage.english.localized(.startTyping), "Start typing…")
        XCTAssertEqual(AppLanguage.chinese.localized(.newNote), "新建笔记")
        XCTAssertEqual(AppLanguage.english.localized(.newNote), "New note")
    }

    func testTitleErrorStringsMatchProductSpecification() {
        XCTAssertEqual(AppLanguage.chinese.localized(.titleTooLong), "标题最多 50 个字符，请缩短后重试。")
        XCTAssertEqual(AppLanguage.english.localized(.titleTooLong), "Titles can contain up to 50 characters. Shorten the title and try again.")
        XCTAssertEqual(AppLanguage.chinese.localized(.titleSaveFailed), "标题未保存，请重试或按 Esc 取消。")
        XCTAssertEqual(AppLanguage.english.localized(.titleSaveFailed), "Title wasn't saved. Try again or press Esc to cancel.")
        XCTAssertEqual(AppLanguage.chinese.localized(.titleTargetMissing), "该分页已不存在，未保存标题。")
        XCTAssertEqual(AppLanguage.english.localized(.titleTargetMissing), "This note no longer exists. The title wasn't saved.")
        for language in [AppLanguage.chinese, .english] {
            XCTAssertEqual(NoteTitleError.tooLong.localized(for: language), language.localized(.titleTooLong))
            XCTAssertEqual(NoteTitleError.saveFailed.localized(for: language), language.localized(.titleSaveFailed))
            XCTAssertEqual(NoteTitleError.targetMissing.localized(for: language), language.localized(.titleTargetMissing))
        }
    }

    func testNoteTitleStrings() {
        XCTAssertEqual(AppLanguage.chinese.localized(.untitled), "无标题")
        XCTAssertEqual(AppLanguage.english.localized(.untitled), "Untitled")
        XCTAssertEqual(AppLanguage.chinese.localized(.untitledNumbered(index: 3)), "无标题 3")
        XCTAssertEqual(AppLanguage.english.localized(.untitledNumbered(index: 3)), "Untitled 3")
    }

    func testMenuStrings() {
        XCTAssertEqual(AppLanguage.chinese.localized(.newNoteMenu), "新建笔记")
        XCTAssertEqual(AppLanguage.english.localized(.newNoteMenu), "New Note")
        XCTAssertEqual(AppLanguage.chinese.localized(.showNotesMenu), "显示笔记")
        XCTAssertEqual(AppLanguage.english.localized(.showNotesMenu), "Show Notes")
        XCTAssertEqual(AppLanguage.chinese.localized(.hideNotesMenu), "隐藏笔记")
        XCTAssertEqual(AppLanguage.english.localized(.hideNotesMenu), "Hide Notes")
    }

    func testMarkdownCommandStrings() {
        XCTAssertEqual(AppLanguage.chinese.localized(.bold), "粗体")
        XCTAssertEqual(AppLanguage.english.localized(.bold), "Bold")
        XCTAssertEqual(AppLanguage.chinese.localized(.italic), "斜体")
        XCTAssertEqual(AppLanguage.english.localized(.italic), "Italic")
    }

    func testMarkdownShortcutHelpIsLocalizedAndAccessible() {
        XCTAssertEqual(MarkdownCommand.bold.toolbarHelp(for: .chinese), "粗体  ⌘B")
        XCTAssertEqual(MarkdownCommand.bold.toolbarHelp(for: .english), "Bold  ⌘B")
        XCTAssertEqual(
            MarkdownCommand.quote.accessibilityHelp(for: .chinese),
            "引用，快捷键 Command + Shift + >"
        )
        XCTAssertEqual(
            MarkdownCommand.quote.accessibilityHelp(for: .english),
            "Quote, Shortcut Command + Shift + >"
        )
    }

    func testTriggerModeTitleStrings() {
        XCTAssertEqual(AppLanguage.chinese.localized(.triggerModeTitle), "触发方式")
        XCTAssertEqual(AppLanguage.english.localized(.triggerModeTitle), "Trigger")
    }

    func testMarkdownPlaceholderStrings() {
        XCTAssertEqual(AppLanguage.chinese.localized(.boldPlaceholder), "粗体")
        XCTAssertEqual(AppLanguage.english.localized(.boldPlaceholder), "bold")
        XCTAssertEqual(AppLanguage.chinese.localized(.italicPlaceholder), "斜体")
        XCTAssertEqual(AppLanguage.english.localized(.italicPlaceholder), "italic")
        XCTAssertEqual(AppLanguage.chinese.localized(.strikethroughPlaceholder), "删除线")
        XCTAssertEqual(AppLanguage.english.localized(.strikethroughPlaceholder), "strikethrough")
        XCTAssertEqual(AppLanguage.chinese.localized(.inlineCodePlaceholder), "代码")
        XCTAssertEqual(AppLanguage.english.localized(.inlineCodePlaceholder), "code")
        XCTAssertEqual(AppLanguage.chinese.localized(.linkTextPlaceholder), "链接文本")
        XCTAssertEqual(AppLanguage.english.localized(.linkTextPlaceholder), "link text")
    }

    func testMarkdownContextMenuStrings() {
        XCTAssertEqual(AppLanguage.chinese.localized(.formatMenu), "格式")
        XCTAssertEqual(AppLanguage.english.localized(.formatMenu), "Format")
        XCTAssertEqual(AppLanguage.chinese.localized(.insertImageEmbed), "插入图片嵌入")
        XCTAssertEqual(AppLanguage.english.localized(.insertImageEmbed), "Insert Image Embed")
        XCTAssertEqual(AppLanguage.chinese.localized(.insertLink), "插入链接")
        XCTAssertEqual(AppLanguage.english.localized(.insertLink), "Insert Link")
    }
}
