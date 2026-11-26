import Foundation

/// The one-line comment a user can put under an app on a share card.
public enum ShareNote {
    public static let maxLength = 16
    /// Quick fills offered while typing.
    public static let suggestions = ["主力", "常驻", "新欢", "付费也值"]

    /// While typing: one line only, at most `maxLength` characters. Spaces are kept so "Mac 瘦身" can be typed.
    public static func limit(_ text: String) -> String {
        let oneLine = text.components(separatedBy: .newlines).joined(separator: " ")
        return String(oneLine.prefix(maxLength))
    }

    /// What goes on the card: limited and trimmed. Empty means "no note".
    public static func normalize(_ text: String) -> String {
        limit(text).trimmingCharacters(in: .whitespaces)
    }
}
