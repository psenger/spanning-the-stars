import Foundation

/// One Markdown block of the rules: the subset RULES.md uses.
enum CodexBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case quote(String)
    /// A list item; `marker` is "•" or the item's number.
    case item(marker: String, text: String)
    case table(header: [String], rows: [[String]])

    static func parse(_ markdown: String) -> [CodexBlock] {
        var blocks: [CodexBlock] = []
        var paragraph: [String] = []
        var table: [[String]] = []

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
            if let header = table.first {
                // The second row is the |---| separator.
                blocks.append(.table(header: header, rows: Array(table.dropFirst(2))))
            }
            table = []
        }

        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("|") {
                if !paragraph.isEmpty { flush() }
                table.append(line.split(separator: "|", omittingEmptySubsequences: false)
                    .dropFirst().dropLast().map { $0.trimmingCharacters(in: .whitespaces) })
                continue
            }
            if !table.isEmpty { flush() }
            let hashes = line.prefix(while: { $0 == "#" }).count
            if line.isEmpty {
                flush()
            } else if hashes > 0, line.dropFirst(hashes).hasPrefix(" ") {
                flush()
                blocks.append(.heading(level: hashes, text: String(line.dropFirst(hashes + 1))))
            } else if line.hasPrefix(">") {
                flush()
                let text = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { blocks.append(.quote(text)) }
            } else if line.hasPrefix("- ") {
                flush()
                blocks.append(.item(marker: "\u{2022}", text: String(line.dropFirst(2))))
            } else if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
                      line[line.index(after: dot)...].hasPrefix(" ") {
                flush()
                blocks.append(.item(marker: String(line[...dot]), text: String(line[line.index(dot, offsetBy: 2)...])))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }
}
