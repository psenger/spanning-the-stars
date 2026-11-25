import Foundation

/// The rules text shown in the in-game Codex.
enum CodexText {
    static func load() -> String {
        if let url = ResourceLocator.url("RULES.md"), let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        return "The rules text could not be found."
    }
}
