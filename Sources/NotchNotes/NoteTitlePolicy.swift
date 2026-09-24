import Foundation

enum NoteTitleChange: Equatable {
    case unchanged
    case set(String?)
}

enum NoteTitleError: Error, Equatable {
    case tooLong
    case saveFailed
    case targetMissing
}

enum NoteTitlePolicy {
    static func singleLine(_ text: String) -> String {
        var result = ""
        var inSeparator = false
        for character in text {
            let isSeparator = character.isNewline || character == "\t"
            if isSeparator {
                if !inSeparator { result.append(" ") }
            } else {
                result.append(character)
            }
            inSeparator = isSeparator
        }
        return result
    }

    static func normalize(_ text: String) -> String {
        singleLine(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func change(for draft: String, initialEffectiveTitle: String) throws -> NoteTitleChange {
        let title = normalize(draft)
        guard title.count <= 50 else { throw NoteTitleError.tooLong }
        if title.isEmpty { return .set(nil) }
        return title == initialEffectiveTitle ? .unchanged : .set(title)
    }
}
