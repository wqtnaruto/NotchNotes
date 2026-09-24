import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chinese:
            return "中文（简体）"
        case .english:
            return "English"
        }
    }
}
