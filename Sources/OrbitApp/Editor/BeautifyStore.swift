import AppKit
import OrbitCore

/// Remembers the last used beautify look, so the next screenshot starts with it.
enum BeautifyStore {
    private static let key = "orbit.beautify.style.v1"

    static func load() -> BeautifyStyle {
        var style = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(BeautifyStyle.self, from: $0) }
            ?? BeautifyPreset.social.style()
        if style.signature.isEmpty { style.signature = NSFullUserName() }
        return style
    }

    static func save(_ style: BeautifyStyle) {
        if let data = try? JSONEncoder().encode(style) { UserDefaults.standard.set(data, forKey: key) }
    }
}
