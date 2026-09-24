import Foundation

/// Localization keys for the MarkdownEngine context menu.
public enum MarkdownEditorLocalizedStringKey {
    case format
    case bold
    case italic
    case heading
    case headingLevel(Int)
    case lists
    case bullet
    case numbered
    case copyImage
    case copyImageFile
    case copyOriginalFile
    case showCopyInFinder
    case showOriginalInFinder
    case copyMarkdownReference
    case insertImageEmbed
    case insertLink
}

/// Embedders provide a localization to translate MarkdownEngine UI such as
/// the right-click context menu. When no localization is supplied the engine
/// falls back to English defaults.
public protocol MarkdownEditorLocalization {
    func string(for key: MarkdownEditorLocalizedStringKey) -> String
}

struct DefaultMarkdownEditorLocalization: MarkdownEditorLocalization {
    func string(for key: MarkdownEditorLocalizedStringKey) -> String {
        switch key {
        case .format:
            return "Format"
        case .bold:
            return "Bold"
        case .italic:
            return "Italic"
        case .heading:
            return "Heading"
        case .headingLevel(let level):
            return "H\(level)"
        case .lists:
            return "Lists"
        case .bullet:
            return "Bullet"
        case .numbered:
            return "Numbered"
        case .copyImage:
            return "Copy Image"
        case .copyImageFile:
            return "Copy Image File"
        case .copyOriginalFile:
            return "Copy Original File"
        case .showCopyInFinder:
            return "Show Copy in Finder"
        case .showOriginalInFinder:
            return "Show Original in Finder"
        case .copyMarkdownReference:
            return "Copy Markdown Reference"
        case .insertImageEmbed:
            return "Insert Image Embed"
        case .insertLink:
            return "Insert Link"
        }
    }
}
