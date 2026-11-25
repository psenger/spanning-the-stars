import SwiftUI

/// The Concord Codex: the bundled RULES.md, rendered block by block in a scrolling sheet.
struct CodexView: View {
    @Environment(\.dismiss) private var dismiss
    private let blocks = CodexBlock.parse(CodexText.load())

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("The Concord Codex", systemImage: "book.closed.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.brass)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(BrassButtonStyle())
                    .accessibilityLabel("Done")
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            Divider().overlay(Palette.brass.opacity(0.3))
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        CodexBlockView(block: block)
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 28).padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 820, height: 700)
        .background(Palette.hex(0x0B1024))
        .environment(\.colorScheme, .dark)
    }
}

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

private func inline(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(text)
}

private struct CodexBlockView: View {
    let block: CodexBlock

    var body: some View {
        switch block {
        case let .heading(level, text):
            Text(inline(text))
                .font(.system(size: level == 1 ? 26 : level == 2 ? 19 : 16, weight: .semibold, design: .serif))
                .foregroundStyle(level == 1 ? Palette.brass : Palette.text)
                .padding(.top, level == 1 ? 0 : 12)
        case .paragraph(let text):
            Text(inline(text))
                .font(.system(size: 14))
                .foregroundStyle(Palette.text.opacity(0.92))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case .quote(let text):
            Text(inline(text))
                .font(.system(size: 15, design: .serif).italic())
                .foregroundStyle(Palette.brass)
                .padding(.leading, 14)
                .overlay(alignment: .leading) { Rectangle().fill(Palette.brass.opacity(0.6)).frame(width: 3) }
        case let .item(marker, text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.brass)
                    .frame(minWidth: 16, alignment: .trailing)
                Text(inline(text))
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.text.opacity(0.92))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 6)
        case let .table(header, rows):
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in tableCell(cell, header: true) }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in tableCell(cell, header: false) }
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.brass.opacity(0.35), lineWidth: 1))
            .fixedSize()
        }
    }

    private func tableCell(_ text: String, header: Bool) -> some View {
        Text(inline(text))
            .font(.system(size: 13.5, weight: header ? .semibold : .regular))
            .foregroundStyle(header ? Palette.brass : Palette.text)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(header ? Palette.brass.opacity(0.1) : Color.clear)
    }
}
